#!/usr/bin/env bash
# ==============================================================================
# Home Assistant add-on: DuckDNS Updater
#
# Keeps one or more DuckDNS accounts pointed at the public IP address of this
# host. An account is a token together with the domains that belong to it, so
# domains spread over several DuckDNS accounts can be updated from a single
# add-on instance.
#
# The script deliberately does not use `set -e`: this is a long running service
# and a single failed lookup or request must never take the whole add-on down.
# ==============================================================================
set -o nounset
set -o pipefail

readonly OPTIONS_FILE="${OPTIONS_FILE:-/data/options.json}"
readonly STATE_FILE="${STATE_FILE:-/data/state.json}"
readonly DUCKDNS_URL="${DUCKDNS_URL:-https://www.duckdns.org/update}"
readonly CURL_TIMEOUT="${CURL_TIMEOUT:-30}"
readonly LOOKUP_TIMEOUT="${LOOKUP_TIMEOUT:-10}"
readonly UPDATE_ATTEMPTS=3
readonly RETRY_DELAY=5

# Services used to find out the public address of this host. They are tried in
# order; the first one that answers with a valid address wins.
readonly IPV4_LOOKUP_URLS=(
    "https://ipv4.icanhazip.com"
    "https://api.ipify.org"
)
readonly IPV6_LOOKUP_URLS=(
    "https://ipv6.icanhazip.com"
    "https://api6.ipify.org"
)

# ------------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------------
declare -A LOG_LEVEL_VALUES=(
    [trace]=0
    [debug]=1
    [info]=2
    [notice]=3
    [warning]=4
    [error]=5
    [fatal]=6
)
LOG_THRESHOLD=2

log::write() {
    local level="${1}"
    shift
    local value="${LOG_LEVEL_VALUES[${level}]:-2}"
    if (( value >= LOG_THRESHOLD )); then
        printf '[%s] %s: %s\n' "$(date +%H:%M:%S)" "${level^^}" "${*}"
    fi
    return 0
}

log::trace() { log::write trace "${@}"; }
log::debug() { log::write debug "${@}"; }
log::info() { log::write info "${@}"; }
log::notice() { log::write notice "${@}"; }
log::warning() { log::write warning "${@}"; }
log::error() { log::write error "${@}"; }
log::fatal() { log::write fatal "${@}"; }

log::set_level() {
    local requested="${1,,}"
    if [[ -z "${LOG_LEVEL_VALUES[${requested}]:-}" ]]; then
        log::warning "Unknown log level '${1}', falling back to 'info'."
        LOG_THRESHOLD=2
        return 0
    fi
    LOG_THRESHOLD="${LOG_LEVEL_VALUES[${requested}]}"
    return 0
}

# ------------------------------------------------------------------------------
# Small helpers
# ------------------------------------------------------------------------------
string::trim() {
    local value="${1}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
}

# Shorten and flatten a server response before it ends up in the log.
string::summarize() {
    local value="${1//$'\n'/ }"
    value="${value//$'\r'/}"
    value="$(string::trim "${value}")"
    if (( ${#value} > 200 )); then
        value="${value:0:200}..."
    fi
    printf '%s' "${value}"
}

# ------------------------------------------------------------------------------
# Add-on options
# ------------------------------------------------------------------------------
OPT_IPV4="auto"
OPT_IPV6=""
OPT_SECONDS=300
OPT_SKIP_UNCHANGED="true"
OPT_FORCE_HOURS=24

options::string() {
    local key="${1}" default="${2:-}" value
    value="$(jq -r --arg key "${key}" --arg default "${default}" '
        (if (.[$key] // null) == null then $default else .[$key] end) | tostring
    ' "${OPTIONS_FILE}" 2>/dev/null)" || value="${default}"
    printf '%s' "$(string::trim "${value}")"
}

options::number() {
    local key="${1}" default="${2}" value
    value="$(options::string "${key}" "${default}")"
    if [[ ! "${value}" =~ ^[0-9]+$ ]]; then
        # The caller reads this function through a command substitution, so the
        # message has to go to stderr to stay out of the returned value.
        log::warning "Option '${key}' is not a positive number ('${value}'), using ${default}." >&2
        value="${default}"
    fi
    printf '%s' "${value}"
}

options::bool() {
    local key="${1}" default="${2}" value
    value="$(options::string "${key}" "${default}")"
    case "${value,,}" in
        true | yes | on | 1) printf 'true' ;;
        false | no | off | 0) printf 'false' ;;
        *) printf '%s' "${default}" ;;
    esac
}

options::load() {
    if [[ ! -s "${OPTIONS_FILE}" ]]; then
        log::fatal "Configuration file ${OPTIONS_FILE} is missing or empty."
        return 1
    fi
    if ! jq -e 'type == "object"' "${OPTIONS_FILE}" > /dev/null 2>&1; then
        log::fatal "Configuration file ${OPTIONS_FILE} does not contain valid JSON."
        return 1
    fi

    log::set_level "$(options::string 'log_level' 'info')"

    OPT_IPV4="$(options::string 'ipv4' 'auto')"
    OPT_IPV6="$(options::string 'ipv6' '')"
    OPT_SECONDS="$(options::number 'seconds' 300)"
    OPT_SKIP_UNCHANGED="$(options::bool 'skip_unchanged' 'true')"
    OPT_FORCE_HOURS="$(options::number 'force_update_hours' 24)"

    if (( OPT_SECONDS < 60 )); then
        log::warning "An update interval of ${OPT_SECONDS}s is too aggressive, using 60s."
        OPT_SECONDS=60
    fi
    return 0
}

# ------------------------------------------------------------------------------
# Accounts (token + the domains that belong to it)
# ------------------------------------------------------------------------------
# Every entry is "<name>\t<token>\t<domain,domain,...>".
declare -a ACCOUNTS=()

domain::normalize() {
    local value="${1,,}"
    value="${value//[[:space:]]/}"
    value="${value#http://}"
    value="${value#https://}"
    value="${value%/}"
    value="${value%.}"
    value="${value%.duckdns.org}"
    printf '%s' "${value}"
}

domain::is_valid() {
    [[ "${1}" =~ ^[a-z0-9][a-z0-9.-]*$ ]]
}

token::looks_like_uuid() {
    [[ "${1}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

accounts::load() {
    ACCOUNTS=()

    local total
    total="$(jq -r '(.accounts // []) | length' "${OPTIONS_FILE}" 2>/dev/null)"
    [[ "${total}" =~ ^[0-9]+$ ]] || total=0

    if (( total == 0 )); then
        log::fatal "No DuckDNS accounts configured."
        log::fatal "Add at least one entry with a token and its domains to the 'accounts' option."
        return 1
    fi

    local -A seen_domains=()
    local index entry name token domain domain_list
    local -a domains=()

    for (( index = 0; index < total; index++ )); do
        entry="$(jq -c --argjson i "${index}" '.accounts[$i] // {}' "${OPTIONS_FILE}" 2>/dev/null)"
        [[ -n "${entry}" ]] || entry='{}'

        name="$(string::trim "$(jq -r '(.name // "") | tostring' <<< "${entry}" 2>/dev/null)")"
        token="$(string::trim "$(jq -r '(.token // "") | tostring' <<< "${entry}" 2>/dev/null)")"
        [[ -n "${name}" ]] || name="account #$(( index + 1 ))"

        domains=()
        while IFS= read -r domain; do
            domain="$(domain::normalize "${domain}")"
            [[ -n "${domain}" ]] || continue
            if ! domain::is_valid "${domain}"; then
                log::warning "${name}: '${domain}' is not a valid DuckDNS domain, ignoring it."
                continue
            fi
            if [[ -n "${seen_domains[${domain}]:-}" ]]; then
                log::warning "${name}: domain '${domain}' is also used by '${seen_domains[${domain}]}'."
                log::warning "${name}: both accounts would update the same domain - remove one of them."
            else
                seen_domains[${domain}]="${name}"
            fi
            domains+=("${domain}")
        done < <(jq -r '(.domains // []) | .[]? | select(. != null) | tostring' <<< "${entry}" 2>/dev/null)

        if [[ -z "${token}" ]]; then
            log::error "${name}: no token configured, skipping this account."
            continue
        fi
        if (( ${#domains[@]} == 0 )); then
            log::error "${name}: no usable domains configured, skipping this account."
            continue
        fi
        if ! token::looks_like_uuid "${token}"; then
            log::warning "${name}: the token does not look like a DuckDNS token (expected a UUID)."
        fi

        domain_list="$(IFS=,; printf '%s' "${domains[*]}")"
        ACCOUNTS+=("${name}"$'\t'"${token}"$'\t'"${domain_list}")
        log::info "Account '${name}': ${#domains[@]} domain(s) -> ${domain_list}"
    done

    if (( ${#ACCOUNTS[@]} == 0 )); then
        log::fatal "None of the configured accounts is usable, check the add-on configuration."
        return 1
    fi
    return 0
}

# ------------------------------------------------------------------------------
# IP addresses
# ------------------------------------------------------------------------------
CURRENT_IPV4=""
CURRENT_IPV6=""

ip::is_valid() {
    local family="${1}" value="${2}"
    case "${family}" in
        4)
            [[ "${value}" =~ ^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$ ]]
            ;;
        6)
            [[ "${value}" == *:* && "${value}" =~ ^[0-9a-fA-F:.]+$ ]]
            ;;
        *)
            return 1
            ;;
    esac
}

ip::detect() {
    local family="${1}" url response
    local -a urls=()

    case "${family}" in
        4) urls=("${IPV4_LOOKUP_URLS[@]}") ;;
        6) urls=("${IPV6_LOOKUP_URLS[@]}") ;;
        *) return 1 ;;
    esac

    # The detected address is returned on stdout, so every message goes to
    # stderr - the add-on log picks up both.
    for url in "${urls[@]}"; do
        response="$(curl "-${family}" --silent --max-time "${LOOKUP_TIMEOUT}" "${url}" 2> /dev/null)"
        response="$(string::trim "${response}")"
        if ip::is_valid "${family}" "${response}"; then
            log::debug "Public IPv${family} address ${response} (via ${url})." >&2
            printf '%s' "${response}"
            return 0
        fi
        log::debug "IPv${family} lookup via ${url} did not return an address." >&2
    done
    return 1
}

# Works out which addresses this cycle should send to DuckDNS. An empty result
# means "do not send that address family", which for IPv4 makes DuckDNS fall
# back to the source address of the request.
ip::resolve() {
    CURRENT_IPV4=""
    CURRENT_IPV6=""

    case "${OPT_IPV4,,}" in
        "" | duckdns | source)
            log::debug "IPv4 is left to DuckDNS (source address of the request)."
            ;;
        auto)
            if ! CURRENT_IPV4="$(ip::detect 4)"; then
                CURRENT_IPV4=""
                log::warning "Could not determine the public IPv4 address, letting DuckDNS use the source address."
            fi
            ;;
        *)
            if ip::is_valid 4 "${OPT_IPV4}"; then
                CURRENT_IPV4="${OPT_IPV4}"
            else
                log::error "Option 'ipv4' is not a valid IPv4 address ('${OPT_IPV4}'), letting DuckDNS use the source address."
            fi
            ;;
    esac

    case "${OPT_IPV6,,}" in
        "" | disabled | off | "false")
            ;;
        auto)
            if ! CURRENT_IPV6="$(ip::detect 6)"; then
                CURRENT_IPV6=""
                log::warning "Could not determine the public IPv6 address, the AAAA record is left untouched."
            fi
            ;;
        *)
            if ip::is_valid 6 "${OPT_IPV6}"; then
                CURRENT_IPV6="${OPT_IPV6}"
            else
                log::error "Option 'ipv6' is not a valid IPv6 address ('${OPT_IPV6}'), the AAAA record is left untouched."
            fi
            ;;
    esac
    return 0
}

# ------------------------------------------------------------------------------
# DuckDNS API
# ------------------------------------------------------------------------------
DUCKDNS_RESPONSE=""
DUCKDNS_ERROR=""

# The token is passed with --data-urlencode so it never shows up in the log,
# and curl's own error output is scrubbed before it is logged.
duckdns::request() {
    local token="${1}" domains="${2}"
    local status stderr_file
    local -a args=(
        --silent
        --show-error
        --location
        --max-time "${CURL_TIMEOUT}"
        --get "${DUCKDNS_URL}"
        --data-urlencode "domains=${domains}"
        --data-urlencode "token=${token}"
        --data-urlencode "verbose=true"
    )

    if [[ -n "${CURRENT_IPV4}" ]]; then
        args+=(--data-urlencode "ip=${CURRENT_IPV4}")
    else
        # No explicit address: the request must travel over IPv4 so DuckDNS
        # picks up an IPv4 source address for the A record.
        args+=(--ipv4)
    fi
    if [[ -n "${CURRENT_IPV6}" ]]; then
        args+=(--data-urlencode "ipv6=${CURRENT_IPV6}")
    fi

    DUCKDNS_RESPONSE=""
    DUCKDNS_ERROR=""
    stderr_file="$(mktemp -t duckdns.XXXXXX 2> /dev/null)" || stderr_file="/tmp/duckdns.err"

    DUCKDNS_RESPONSE="$(curl "${args[@]}" 2> "${stderr_file}")"
    status=$?

    DUCKDNS_ERROR="$(string::summarize "$(cat "${stderr_file}" 2> /dev/null)")"
    DUCKDNS_ERROR="${DUCKDNS_ERROR//"${token}"/<token>}"
    rm -f "${stderr_file}"

    return "${status}"
}

account::update() {
    local name="${1}" token="${2}" domains="${3}"
    local attempt status reported_v4 reported_v6 change
    local -a lines=()

    for (( attempt = 1; attempt <= UPDATE_ATTEMPTS; attempt++ )); do
        duckdns::request "${token}" "${domains}"
        status=$?

        if (( status != 0 )); then
            log::warning "${name}: request to DuckDNS failed (curl exit code ${status}, attempt ${attempt}/${UPDATE_ATTEMPTS})${DUCKDNS_ERROR:+: ${DUCKDNS_ERROR}}"
        else
            mapfile -t lines <<< "${DUCKDNS_RESPONSE//$'\r'/}"
            case "$(string::trim "${lines[0]:-}")" in
                OK)
                    reported_v4="$(string::trim "${lines[1]:-}")"
                    reported_v6="$(string::trim "${lines[2]:-}")"
                    change="$(string::trim "${lines[3]:-}")"
                    log::info "${name}: ${domains} -> IPv4 ${reported_v4:-unchanged}${reported_v6:+, IPv6 ${reported_v6}} (${change:-OK})"
                    return 0
                    ;;
                KO)
                    log::error "${name}: DuckDNS refused the update (KO)."
                    log::error "${name}: check that the token is correct and that it owns every domain: ${domains}"
                    # A rejected token or domain will not fix itself, so no retry.
                    return 1
                    ;;
                *)
                    log::warning "${name}: unexpected answer from DuckDNS (attempt ${attempt}/${UPDATE_ATTEMPTS}): $(string::summarize "${DUCKDNS_RESPONSE}")"
                    ;;
            esac
        fi

        if (( attempt < UPDATE_ATTEMPTS )); then
            sleep "${RETRY_DELAY}"
        fi
    done

    log::error "${name}: could not update ${domains}, retrying at the next interval."
    return 1
}

# ------------------------------------------------------------------------------
# State, so unchanged addresses do not trigger pointless requests
# ------------------------------------------------------------------------------
state::init() {
    if [[ ! -s "${STATE_FILE}" ]] || ! jq -e 'type == "object"' "${STATE_FILE}" > /dev/null 2>&1; then
        printf '{}\n' > "${STATE_FILE}" 2> /dev/null \
            || log::warning "Cannot write ${STATE_FILE}, every cycle will send an update."
    fi
    return 0
}

state::get() {
    local key="${1}" field="${2}"
    jq -r --arg key "${key}" --arg field "${field}" '
        ((.[$key] // {})[$field] // "") | tostring
    ' "${STATE_FILE}" 2> /dev/null || printf ''
}

state::set() {
    local key="${1}" ipv4="${2}" ipv6="${3}" timestamp="${4}"
    local temporary="${STATE_FILE}.tmp"

    if jq --arg key "${key}" --arg ipv4 "${ipv4}" --arg ipv6 "${ipv6}" --argjson updated "${timestamp}" '
            .[$key] = {ipv4: $ipv4, ipv6: $ipv6, updated: $updated}
        ' "${STATE_FILE}" > "${temporary}" 2> /dev/null; then
        mv -f "${temporary}" "${STATE_FILE}"
    else
        rm -f "${temporary}"
        log::warning "Could not store the update state in ${STATE_FILE}."
    fi
    return 0
}

# ------------------------------------------------------------------------------
# Update cycle
# ------------------------------------------------------------------------------
cycle::run() {
    local now force_seconds entry name token domains previous_v4 previous_v6 updated reason

    ip::resolve

    now="$(date +%s)"
    force_seconds=$(( OPT_FORCE_HOURS * 3600 ))

    for entry in "${ACCOUNTS[@]}"; do
        IFS=$'\t' read -r name token domains <<< "${entry}"

        previous_v4="$(state::get "${domains}" 'ipv4')"
        previous_v6="$(state::get "${domains}" 'ipv6')"
        updated="$(state::get "${domains}" 'updated')"
        [[ "${updated}" =~ ^[0-9]+$ ]] || updated=0

        reason=""
        if [[ "${OPT_SKIP_UNCHANGED}" != "true" ]]; then
            reason="'skip_unchanged' is disabled"
        elif [[ -z "${CURRENT_IPV4}" && -z "${CURRENT_IPV6}" ]]; then
            reason="the address is determined by DuckDNS itself"
        elif (( updated == 0 )); then
            reason="no successful update recorded yet"
        elif [[ "${CURRENT_IPV4}" != "${previous_v4}" ]]; then
            reason="the IPv4 address changed (${previous_v4:-none} -> ${CURRENT_IPV4:-none})"
        elif [[ "${CURRENT_IPV6}" != "${previous_v6}" ]]; then
            reason="the IPv6 address changed (${previous_v6:-none} -> ${CURRENT_IPV6:-none})"
        elif (( force_seconds > 0 && now - updated >= force_seconds )); then
            reason="periodic refresh after ${OPT_FORCE_HOURS}h"
        fi

        if [[ -z "${reason}" ]]; then
            log::debug "${name}: ${domains} still points at ${CURRENT_IPV4:-${CURRENT_IPV6}}, nothing to do."
            continue
        fi

        log::debug "${name}: updating ${domains} because ${reason}."
        if account::update "${name}" "${token}" "${domains}"; then
            state::set "${domains}" "${CURRENT_IPV4}" "${CURRENT_IPV6}" "${now}"
        fi
    done
    return 0
}

# ------------------------------------------------------------------------------
# Service life cycle
# ------------------------------------------------------------------------------
RUNNING="true"
SLEEP_PID=""

service::terminate() {
    RUNNING="false"
    log::info "Stopping the DuckDNS Updater add-on..."
    if [[ -n "${SLEEP_PID}" ]]; then
        kill "${SLEEP_PID}" 2> /dev/null
    fi
    return 0
}

# A backgrounded sleep keeps the signal handlers responsive, so the add-on
# stops immediately instead of waiting out the interval.
service::wait() {
    sleep "${1}" &
    SLEEP_PID=$!
    wait "${SLEEP_PID}" 2> /dev/null
    SLEEP_PID=""
    return 0
}

main() {
    trap service::terminate TERM INT

    log::info "Starting the DuckDNS Updater add-on..."

    local dependency
    for dependency in curl jq; do
        if ! command -v "${dependency}" > /dev/null 2>&1; then
            log::fatal "Required tool '${dependency}' is missing from the container image."
            exit 1
        fi
    done

    options::load || exit 1
    accounts::load || exit 1
    state::init

    log::info "Update interval: ${OPT_SECONDS}s, IPv4: ${OPT_IPV4:-<source address>}, IPv6: ${OPT_IPV6:-disabled}"
    if [[ "${OPT_SKIP_UNCHANGED}" == "true" ]]; then
        log::info "Unchanged addresses are skipped, with a forced refresh every ${OPT_FORCE_HOURS}h."
    else
        log::info "Every account is updated on every cycle."
    fi

    while [[ "${RUNNING}" == "true" ]]; do
        cycle::run
        if [[ "${RUN_ONCE:-false}" == "true" ]]; then
            break
        fi
        [[ "${RUNNING}" == "true" ]] && service::wait "${OPT_SECONDS}"
    done

    log::info "DuckDNS Updater stopped."
    return 0
}

main "${@}"
