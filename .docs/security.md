# Security

How the app finds and fixes known vulnerabilities in what it runs, without changing the
editor's or Glance's code.

## What the app runs

| Part                 | Comes from                                   | Kept current by |
| -------------------- | -------------------------------------------- | --------------- |
| Glance               | Its source, built on the device              | Newest Glance patch release, newest Go patch release, `GLANCE_GO_UPDATES` |
| The editor           | Its source, built on the device              | Newest editor release; its runtime dependencies are bundled into its build |
| Node.js              | `node:<major>-slim`, by digest               | Newest image of the editor's Node major version |
| Debian packages      | The Node image                               | The newest Node image, plus `apt-get upgrade` at build time |

The Node image's package managers (npm, npx, corepack, yarn) are removed from the final
image: nothing uses them at runtime, and they carry their own dependencies.

## How vulnerabilities are found

`scripts/check-security.sh` runs in CI on every pull request and every week, and fails on any
known vulnerability **with a fix available**:

- **govulncheck** on Glance's code and Go modules, as the app builds them. It reports only
  vulnerabilities that Glance's code can actually reach.
- **npm audit** on the editor's runtime dependencies.
- **Trivy** on the app image, at high or critical severity: Debian packages, the Glance
  binary, and any other package it recognises.

Vulnerabilities without a released fix do not fail the check, because there is nothing to
update to. Trivy lists them when run without `--ignore-unfixed`:

```bash
docker run --rm -v //var/run/docker.sock:/var/run/docker.sock aquasec/trivy:0.76.1 image \
  --scanners vuln --severity HIGH,CRITICAL local/glance-app
```

## When the check fails

Fix it by updating, never by patching upstream code:

1. **Run the Update workflow first** (or `scripts/update-glance.sh`). A newer Node image, Go
   release or Glance patch release often already contains the fix.
2. **A Go module of Glance** (govulncheck names it, with the fixed version): add
   `module@version` to `GLANCE_GO_UPDATES` in `glance/Dockerfile`, separated by spaces, and
   run `scripts/check-glance.sh` to make sure Glance still works with it. The update script
   drops the entry once a Glance release requires that version itself.
3. **The Go standard library:** the update script picks the newest Go patch release; if the
   fix is only in a newer Go minor version, raise `GO_IMAGE` by hand and run the checks.
4. **A Debian package:** fixed by the next Node image, or by `apt-get upgrade` once Debian
   publishes the fix; rebuild.
5. **An editor dependency:** report it to the
   [Glance Editor](https://github.com/gcarstoiu/glance-ui/issues) and wait for its release.
   The editor bundles its dependencies at build time, so the app cannot replace them without
   changing the editor's lock file.

Report vulnerabilities in Glance itself to the [Glance project](https://github.com/glanceapp/glance/security).

## By design

These are known and documented for users in `glance/DOCS.md`:

- **The editor has no login.** Anyone who can reach its port can change the dashboard and
  read the values in `.env`. Users are told to keep it on their home network and to close
  its port when they are not editing.
- **No Docker access.** The app does not ask for `docker_api`, so neither Glance nor the
  editor can reach Docker.
- **Ports are published on the host**, not behind Home Assistant's login; see the ingress
  decision in [Development](development.md#design-decisions).

## Status at the first release

At 1.2.0 (22 October 2026), an image with the Glance binary from Glance v0.8.7's official
image and Node 24.21.0 had 3 critical and 16 high vulnerabilities with a fix available. The changes below
brought that to none:

- Glance built with Go 1.27.3 instead of 1.27.1: fixes a crypto/x509 man-in-the-middle issue
  and denial-of-service issues in net/http and crypto/tls.
- `golang.org/x/net` v0.60.0 instead of v0.58.0: fixes five HTTP/2 vulnerabilities that
  govulncheck found reachable from Glance's code.
- Node.js 24.22.1 (security release) instead of 24.21.0.
- npm and its dependencies (brace-expansion, tar, undici, ip-address and others) removed.
- Debian security updates (perl-base) installed at build time.
