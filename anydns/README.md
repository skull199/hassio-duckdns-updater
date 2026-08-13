# AnyDNS

Home Assistant add-on that keeps DuckDNS domains pointed at the public IP
address of your Home Assistant host - with support for **several DuckDNS
accounts**, each token with its own list of domains.

Supported provider: **DuckDNS only** (as of version 1.0.0). Other dynamic
DNS providers are planned - see [DOCS.md](DOCS.md#supported-dns-providers).

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
```

See [DOCS.md](DOCS.md) for the full documentation.
