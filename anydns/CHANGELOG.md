# Changelog

## 1.2.2

- Dropped the `armhf`, `armv7` and `i386` architectures, which Home Assistant
  no longer supports since 2025.12. The add-on is built for `aarch64` and
  `amd64`.
- Removed `boot` from the add-on configuration, it only repeated the default.

## 1.2.1

- Quieter log: the recurring checks (address lookup, DNS records, accounts
  that were left alone) moved from `info` to `debug`. At `info` a cycle that
  changes nothing no longer writes anything, while updates, their reason,
  the answer of DuckDNS, and every warning are still logged.

## 1.2.0

- New option `verify_dns` (on by default): every domain of an account is
  looked up and compared with the current public address, so a record that
  drifted, disappeared or never took effect is corrected even when the stored
  state says everything is fine. Where each domain points is now visible in
  the log.
- New option `dns_server` (default `1.1.1.1`) for those lookups, with an
  automatic fallback to the resolver of the container.

## 1.1.0

- New option `update_on_start` (on by default): every account is updated once
  right after the add-on starts, even when the stored address is unchanged.
  Restarting the add-on is now enough to force a refresh.

## 1.0.0

First release.

- Update DuckDNS domains from several accounts, each token with its own list
  of domains.
- Public IPv4 detection (`auto`), a fixed address, or the source address as
  seen by DuckDNS.
- Optional IPv6 (AAAA) updates.
- Updates are skipped while the address is unchanged, with a configurable
  periodic refresh so domains do not expire.
- Retries on transient network errors, configurable log level, tokens are
  kept out of the log.
