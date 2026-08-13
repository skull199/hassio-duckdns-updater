# AnyDNS Add-ons for Home Assistant

A custom add-on repository for Home Assistant.

[![Open your Home Assistant instance and show the add add-on repository dialog with a specific repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fskull199%2Fhassio-duckdns-updater)

## Add-ons in this repository

### [AnyDNS](anydns)

Keeps your dynamic DNS domains pointed at the public IP address of the Home
Assistant host. Several accounts are supported - every token gets its own
list of domains, so domains spread over more than one account are updated by
a single add-on.

**Supported provider: DuckDNS only** (version 1.0.0). Other dynamic DNS
providers are planned, see
[the documentation](anydns/DOCS.md#supported-dns-providers).

- [Documentation](anydns/DOCS.md)
- [Changelog](anydns/CHANGELOG.md)

## Installation

1. **Settings → Add-ons → Add-on Store**, three-dot menu → **Repositories**.
2. Add `https://github.com/skull199/hassio-duckdns-updater`.
3. Install **AnyDNS**, configure it, press **Start**, and turn on
   **Start on boot** and **Watchdog**.

The add-on is built by the Supervisor on your own machine the first time it
is installed; no prebuilt images have to be pulled.

## Hitri začetek (slovensko)

1. V Home Assistantu odpri **Nastavitve → Dodatki → Trgovina z dodatki**, v
   meniju s tremi pikami izberi **Repozitoriji** in dodaj
   `https://github.com/skull199/hassio-duckdns-updater`.
2. Namesti dodatek **AnyDNS**.
3. V zavihku **Konfiguracija** vpiši račune - za vsak DuckDNS žeton svoj vnos
   z domenami, ki mu pripadajo:

   ```yaml
   accounts:
     - name: doma
       token: 11111111-2222-3333-4444-555555555555
       domains:
         - mojadomena
         - mojadomena-vpn
     - name: starsi
       token: aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
       domains:
         - hisa-starsev
   ```

4. Zaženi dodatek ter vklopi **Zaženi ob zagonu** in **Nadzornik**.

Privzeto se javni naslov preveri vsakih 5 minut (`seconds: 300`), na DuckDNS
pa se pošlje samo ob spremembi naslova oziroma enkrat na 24 ur
(`force_update_hours: 24`). Vsi koraki so vidni v dnevniku dodatka.

## License

MIT - see [LICENSE](LICENSE).
