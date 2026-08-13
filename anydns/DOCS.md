# Home Assistant add-on: AnyDNS

AnyDNS keeps your DuckDNS domains pointed at the public IP address of the
Home Assistant host.

Unlike the official DuckDNS add-on it is not tied to a single token: the
configuration is a list of **accounts**, and every account carries its own
token together with the domains that belong to it. Domains spread over
several DuckDNS accounts are therefore updated by one add-on.

## Supported DNS providers

| Provider | Status | Notes |
| --- | --- | --- |
| [DuckDNS](https://www.duckdns.org) | Supported since 1.0.0 | Any number of accounts, IPv4 (A) and IPv6 (AAAA) records |
| Other dynamic DNS providers | Not supported yet | - |

**As of version 1.0.0 the only supported provider is DuckDNS.** Every
account is sent to `https://www.duckdns.org/update`, and the `token` option
is a DuckDNS token. The name AnyDNS reflects where the add-on is headed -
support for further providers is planned but not implemented, so there is no
provider option to choose from yet.

## Installation

1. In Home Assistant go to **Settings → Add-ons → Add-on Store**, open the
   three-dot menu and choose **Repositories**.
2. Add `https://github.com/skull199/hassio-duckdns-updater` and close the
   dialog.
3. Install **AnyDNS** from the newly added repository.
4. Fill in the configuration (see below) and press **Start**.
5. Turn on **Start on boot** and **Watchdog**.

## Configuration

Add-on configuration is edited in YAML mode on the add-on's
**Configuration** tab:

```yaml
accounts:
  - name: home
    token: 11111111-2222-3333-4444-555555555555
    domains:
      - myhome
      - myhome-vpn
  - name: parents
    token: aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
    domains:
      - parents-house
ipv4: auto
ipv6: ""
seconds: 300
skip_unchanged: true
force_update_hours: 24
log_level: info
```

Your token is shown on <https://www.duckdns.org> after signing in. Each
DuckDNS account has exactly one token, and a token may only update the
domains that were created in that account - which is why the domains are
grouped per token.

### Option: `accounts` (required)

A list of DuckDNS accounts. One entry per token.

| Key | Required | Description |
| --- | --- | --- |
| `name` | no | Free-form label used in the log. Defaults to `account #1`, `account #2`, ... |
| `token` | yes | The DuckDNS token of that account. Stored as a password field and never written to the log. |
| `domains` | yes | The domains belonging to that token. |

Domains may be written with or without the `.duckdns.org` suffix -
`myhome`, `myhome.duckdns.org` and `https://myhome.duckdns.org/` all end up
as `myhome`. All domains of one account are sent to DuckDNS in a single
request.

The same domain must not appear under two accounts; the add-on logs a
warning if it does, because the two accounts would keep overwriting each
other.

### Option: `ipv4`

Controls the A record.

| Value | Behaviour |
| --- | --- |
| `auto` (default) | The add-on looks up the public IPv4 address and sends it to DuckDNS. This is what makes `skip_unchanged` work. |
| `""` (empty) | Nothing is sent and DuckDNS uses the source address of the request. Useful if the lookup services are unreachable. |
| e.g. `203.0.113.7` | That fixed address is sent on every update. |

### Option: `ipv6`

Controls the AAAA record. Empty by default, so the AAAA record is left
untouched.

| Value | Behaviour |
| --- | --- |
| `""` (default) | IPv6 is not touched. |
| `auto` | The add-on looks up the public IPv6 address and sends it. If the host has no IPv6 connectivity a warning is logged and only IPv4 is updated. |
| e.g. `2001:db8::1` | That fixed address is sent on every update. |

### Option: `seconds`

How often the add-on runs an update cycle, in seconds. Default `300`
(5 minutes), allowed range 60 - 86400. A cycle looks up the current address
and updates the accounts that need it.

### Option: `skip_unchanged`

When `true` (default) an account is only sent to DuckDNS when its address
actually changed since the last successful update. When `false` every
account is updated on every cycle.

The setting has no effect when `ipv4` is empty *and* `ipv6` is empty or
disabled, because then the address is decided by DuckDNS and the add-on has
nothing to compare.

### Option: `force_update_hours`

Even when nothing changed, each account is refreshed after this many hours
(default `24`). DuckDNS deletes domains that have not been updated for 30
days, so do not set this too high. `0` disables the periodic refresh.

### Option: `log_level`

One of `trace`, `debug`, `info` (default), `notice`, `warning`, `error`,
`fatal`. Use `debug` to see the outcome of every cycle, including the
skipped ones.

## How the update works

1. On start the add-on validates the configuration and logs every account
   with its domains (tokens are never logged).
2. Every cycle it determines the current address once and reuses it for all
   accounts.
3. An account is updated when the address changed, when no successful update
   has been recorded yet (this includes every add-on restart), when
   `force_update_hours` has passed, or when `skip_unchanged` is `false`.
4. Failed requests are retried up to 3 times with a 5 second pause. A `KO`
   answer from DuckDNS is not retried, because it means the token or a
   domain is wrong.
5. The result of the last successful update is stored in
   `/data/state.json`, which survives add-on restarts.

## What the log looks like

At the default `info` level every step is written to the add-on log: the
check of the public address, the address that was found, which accounts were
updated and why, which ones were left alone, and the answer DuckDNS gave.

```text
[21:15:02] INFO: Starting the AnyDNS add-on...
[21:15:02] INFO: Account 'home': 2 domain(s) -> myhome,myhome-vpn
[21:15:02] INFO: Account 'parents': 1 domain(s) -> parents-house
[21:15:02] INFO: Update interval: 300s, IPv4: auto, IPv6: disabled
[21:15:02] INFO: Unchanged addresses are skipped, with a forced refresh every 24h.
[21:15:02] INFO: Checking the public IP address...
[21:15:03] INFO: IPv4: current public address is 203.0.113.7.
[21:15:03] INFO: home: updating myhome,myhome-vpn - no successful update recorded yet.
[21:15:03] INFO: home: myhome,myhome-vpn -> IPv4 203.0.113.7 (UPDATED)
[21:15:03] INFO: parents: updating parents-house - no successful update recorded yet.
[21:15:04] INFO: parents: parents-house -> IPv4 203.0.113.7 (UPDATED)
[21:20:04] INFO: Checking the public IP address...
[21:20:04] INFO: IPv4: current public address is 203.0.113.7.
[21:20:04] INFO: home: myhome,myhome-vpn unchanged (203.0.113.7), no update needed.
[21:20:04] INFO: parents: parents-house unchanged (203.0.113.7), no update needed.
[21:25:05] INFO: Checking the public IP address...
[21:25:05] INFO: IPv4: current public address is 203.0.113.42.
[21:25:05] INFO: home: updating myhome,myhome-vpn - the IPv4 address changed (203.0.113.7 -> 203.0.113.42).
[21:25:06] INFO: home: myhome,myhome-vpn -> IPv4 203.0.113.42 (UPDATED)
```

`UPDATED` / `NOCHANGE` at the end of a result line is DuckDNS' own answer -
`NOCHANGE` means DuckDNS already had that address on record.

Set `log_level: debug` to additionally see which lookup service answered and
when the next cycle is due. Tokens never appear in the log, not even in
error messages from `curl`.

## Troubleshooting

**`DuckDNS refused the update (KO)`**
The token is wrong, or one of the domains in that account does not belong to
that token. Open <https://www.duckdns.org>, check which domains are listed
under that account, and move the others to their own `accounts` entry.

**`Could not determine the public IPv4 address`**
The lookup services (`ipv4.icanhazip.com`, `api.ipify.org`) were not
reachable. The add-on falls back to letting DuckDNS use the source address
of the request, so the update still happens. If your network blocks these
services, set `ipv4: ""` to make that the permanent behaviour.

**`Could not determine the public IPv6 address`**
The host has no working IPv6 connectivity. Set `ipv6: ""` to stop the
lookup, or fix IPv6 on the host.

**The address never changes although my ISP changed it**
If Home Assistant sits behind a carrier-grade NAT, the address you get is
shared and cannot be used for port forwarding - DuckDNS will still be
updated, but incoming connections will not work.

## Not included

This add-on only updates DNS records. It does not request Let's Encrypt
certificates - use the official **Let's Encrypt** or **DuckDNS** add-on for
that. Both can run next to AnyDNS as long as they do not manage the same
domains.
