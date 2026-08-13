# Changelog

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
