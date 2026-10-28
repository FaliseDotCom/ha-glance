# Glance for Home Assistant

[![Add repository to Home Assistant][repository-badge]][repository-url]
![Glance Editor 1.2.0][editor-shield]
![Glance v0.8.7][glance-shield]
![Supports aarch64 Architecture][aarch64-shield]
![Supports amd64 Architecture][amd64-shield]
[![License: MIT][license-shield]](LICENSE)

Run [Glance](https://github.com/glanceapp/glance), the self-hosted dashboard for your feeds and
services, as a Home Assistant app, together with the
[Glance Editor](https://github.com/gcarstoiu/glance-ui), a no-code editor for it. Build your
dashboard in the browser instead of writing YAML by hand.

## Features

- Glance and its editor in one app, with a private preview of every change before it goes
  live.
- Every Glance widget, community widgets, themes, backgrounds and an icon finder.
- Every save is checked by Glance itself and kept as a version you can go back to.
- Bring a Glance you already run: upload a `.zip` of its folder.
- `glance.yml`, its `.env` values and the assets live in the app configuration folder, reachable
  through the Samba share, and are included in Home Assistant backups.
- Photos from Home Assistant's media and share folders as backgrounds.
- Uses the Home Assistant time zone.
- Runs on `amd64` and `aarch64` (Raspberry Pi 4 and 5).
- Kept current and patched: Glance patch releases are tested against the editor's own test
  suite before they ship, Glance is built with the latest Go security fixes, and every
  release is scanned for known vulnerabilities. See [Security](.docs/security.md).

## Installation

Select the button above, or add the repository by hand:

1. In Home Assistant, go to **Settings** > **Apps** > **Install app**.
2. Open the three-dots menu in the top-right corner and select **Repositories**.
3. Add `https://github.com/FaliseDotCom/ha-glance` and select **Add**.
4. Find **Glance** in the app store and select **Install**.

Then follow the [app documentation](glance/DOCS.md) to build your first dashboard. The same
documentation is shown on the app's **Documentation** tab in Home Assistant.

> [!NOTE]
> The editor does not answer over IPv6 yet. When `http://homeassistant.local:8090` stays empty,
> open the editor by your Home Assistant's IP address instead, such as
> `http://192.168.1.10:8090`. The dashboard is not affected. A fix is
> [offered to the editor](.docs/pr/2026-10-28-editor-host-ipv6.md); see
> [Troubleshooting](glance/DOCS.md#troubleshooting).

## Apps in this repository

| App                 | Description                                                         |
| ------------------- | ------------------------------------------------------------------- |
| [Glance](glance/)   | Self-hosted dashboard for your feeds and services, with an editor.  |

## Contributing

Bug reports and pull requests are welcome. [Development](.docs/development.md) explains how
the app works and how to test changes, [Releasing](.docs/releasing.md) covers updates and
the automation behind them, and [Security](.docs/security.md) how vulnerabilities are found
and fixed.

The app is YAML, Dockerfiles and shell scripts. Pull requests should follow these
conventions:

- **Formatting:** two spaces per indentation level, as in the existing files. `.editorconfig`
  sets the basics for most editors.
- **Checks:** CI must pass: [ShellCheck](https://www.shellcheck.net/), the editor's checks
  against the app's Glance, the security checks, and the smoke test on both architectures.
  [Development](.docs/development.md#testing-a-change) shows how to run them with Docker.
- **User-facing changes:** update [`glance/DOCS.md`](glance/DOCS.md) and add an entry to
  [`glance/CHANGELOG.md`](glance/CHANGELOG.md).
- **Upstream code:** the editor and Glance are never patched here. A change they need belongs
  in their own repositories.

## AI coding guidelines

This repository has no PHP, JavaScript or CSS of its own, so none of the language skills
apply to its files. Shell scripts follow the global formatting rules: two-space indentation
and `then`/`do` on their own line, as in `scripts/update-glance.sh`. Apply the `javascript`
skill only if the app ever gains scripts of its own; never edit the editor's code in this
repository.

## License

The files in this repository are released under the [MIT License](LICENSE), except for
`glance/icon.png` and `glance/logo.png`. This repository contains no code from either
upstream project, apart from the short build steps in `glance/Dockerfile` that follow their
own Dockerfiles. The app downloads and builds the
[Glance Editor](https://github.com/gcarstoiu/glance-ui) (GPL-3.0) and
[Glance](https://github.com/glanceapp/glance) (AGPL-3.0) on the user's device, with their
source unchanged; only Glance's Go dependencies may be raised to their security releases. Their
licences are included in the built image under `/usr/share/doc/`. Neither project is
affiliated with this one.

The Glance name and the icon images (`glance/icon.png` and `glance/logo.png`, resized from
Glance's own app icon) belong to the Glance project. They are used only to identify the app,
and remain under the Glance project's terms.

[repository-badge]: https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg
[repository-url]: https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2FFaliseDotCom%2Fha-glance
[editor-shield]: https://img.shields.io/badge/Glance_Editor-1.2.0-blue.svg
[glance-shield]: https://img.shields.io/badge/Glance-v0.8.7-blue.svg
[aarch64-shield]: https://img.shields.io/badge/aarch64-yes-green.svg
[amd64-shield]: https://img.shields.io/badge/amd64-yes-green.svg
[license-shield]: https://img.shields.io/badge/license-MIT-green.svg
