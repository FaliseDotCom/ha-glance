# Development

How the Glance app is put together, and how to test a change before it reaches users.

## Repository layout

```text
repository.yaml              App repository definition, read by the Supervisor
glance/
  config.yaml                App definition: version, ports and folder mappings
  Dockerfile                 Builds the Glance Editor from source, with Glance alongside
  DOCS.md                    User documentation, shown on the Documentation tab
  README.md                  Short description, shown in the app store
  CHANGELOG.md               Release notes, shown when an update is available
  icon.png, logo.png         Artwork, resized from Glance's own app icon
  translations/              Port descriptions (en, nl)
scripts/
  update-glance.sh           Moves every pin to the newest release the app may use
  check-glance.sh            Runs the editor's own checks against the app's Glance
  check-security.sh          Fails on known vulnerabilities that have a fix
  smoke-test.sh              Builds the image, saves a dashboard, checks it is served
  lib.sh                     Helpers shared by the scripts
  compat/                    The throwaway image check-glance.sh runs the editor's tests in
.github/
  workflows/ci.yml           Lint, compatibility, security and smoke tests; weekly too
  workflows/update.yml       Weekly: opens a pull request when anything can be updated
  dependabot.yml             Keeps the workflows' actions up to date
.devcontainer/, .vscode/     Home Assistant development environment
.docs/                       Documentation for contributors
```

## How the app works

The app packages the [Glance Editor](https://github.com/gcarstoiu/glance-ui) (glance-ui)
all-in-one container. That container already runs everything the app needs, so the app adds
no start script of its own; it only builds the image and sets where the data lives.

### The image

The editor publishes `ghcr.io/gcarstoiu/glance-editor` for `amd64` only. To support `aarch64`
as well, the Dockerfile builds the editor from source on the user's device:

1. **`glance` stage:** builds Glance the way its own Dockerfile does (`CGO_ENABLED=0 go
   build`), from its source at a pinned commit, with the newest Go patch release. Before
   building, `go get` raises the Go modules listed in `GLANCE_GO_UPDATES` to their security
   releases. Glance's own code is not changed.
2. **`build` stage:** downloads the editor's source as a GitHub archive at a pinned commit,
   checks that the `EDITOR_*` pins match the editor's own `glance.version` and `Dockerfile`
   (the build stops when they differ), then runs `npm ci` and builds the SvelteKit app with
   the editor's own Node image.
3. **final stage:** the final stage of the editor's own Dockerfile, on the newest Node image
   of the same major version and with the Glance from stage 1. It also installs Debian's
   security updates and removes the package managers (npm, npx, corepack, yarn) that the Node
   image ships but nothing uses at runtime. Then the Home Assistant settings described below.

The editor validates every save with the same Glance binary that serves the dashboard.

### Pins

All pins are `ARG` lines at the top of `glance/Dockerfile`, and `scripts/update-glance.sh`
moves them all. Images are pinned by the digest of their multi-architecture index.

| Pin                     | What it is                                                  | Rule |
| ----------------------- | ----------------------------------------------------------- | ---- |
| `EDITOR_VERSION`, `EDITOR_COMMIT` | The Glance Editor release and its commit           | Newest release |
| `EDITOR_GLANCE_*`, `EDITOR_NODE_IMAGE` | What that editor release pins                 | Copied from the editor; the build checks them |
| `GLANCE_VERSION`, `GLANCE_COMMIT` | The Glance the app builds and runs                 | Newest patch release in the editor's minor series, never older than the editor's pin |
| `GO_IMAGE`              | The Go toolchain Glance is built with                       | Newest patch release of the Go version in Glance's `go.mod` |
| `GLANCE_GO_UPDATES`     | Go modules raised to their security releases               | Added by hand when `check-security.sh` asks; dropped automatically once Glance requires that version itself |
| `NODE_IMAGE`            | The image the app runs on                                   | Newest image of the editor's Node major version |

**Running ahead of the editor.** The editor's widget forms, rules and community widget
snapshot are made for one Glance version. A Glance patch release normally changes no
configuration, so the app may run one before the editor is updated, but only once
`scripts/check-glance.sh` passed it (see [Testing a change](#testing-a-change)): the editor's
own test suite runs against it, and Glance's configuration reference is compared, for a person
to review. A minor or major Glance release always waits for an editor release.

### At runtime

The container command is the editor's `image/start.ts`, run by Node. Docker's `init`
(`init: true`) runs it as a child of a minimal init process, which forwards signals and reaps
zombies. `start.ts` starts as root and runs:

| Process     | Listens on                    | Runs as         | Restarted when it stops |
| ----------- | ----------------------------- | --------------- | ----------------------- |
| editor      | `3000`, published as `8090`   | `PUID:PGID`     | Yes                     |
| glance      | `8080`, published as `8080`   | root            | Yes, once `glance.yml` exists |
| preview     | `127.0.0.1:47801`             | root            | Yes, once the editor wrote its config |
| Docker gate | `127.0.0.1:47802`             | root (in-process) | No                    |

The editor serves the preview Glance under `/preview`. Glance's own port comes from
`glance.yml` (`server: port`, default 8080). `start.ts` restarts both Glance processes when
`config/.env` changes, because Glance reads its environment only at start. On `SIGTERM` it
stops all children and exits within eight seconds, inside the Supervisor's default timeout.

### Home Assistant settings

| Setting                                   | Why                                                                 |
| ----------------------------------------- | ------------------------------------------------------------------- |
| `DATA_DIR=/config`                        | Keeps the dashboard in the app configuration folder (`map: app_config:rw`), reachable through the `app_configs` share, instead of the private `/data`. `start.ts` derives every other path from it. |
| `SERVER_FOLDERS=/media,/share`            | Offers Home Assistant's media and share folders (`map: media:ro, share:ro`) as background sources. `start.ts` drops folders that are not mounted. |
| `PUID=99`, `PGID=100` (editor default)    | The editor runs unprivileged. `start.ts` gives the data folder to this user on every start. |
| `webui` on port 3000                      | **Open web UI** opens the editor, which is where a fresh install starts. |
| No `watchdog` URL                         | The editor's port may be cleared to close it. The Docker health check (`/healthz` on `127.0.0.1:3000`) runs inside the container, so the Supervisor's watchdog keeps working without a published port. |
| No options                                | Everything about the dashboard, including `${VARIABLE}` values in `.env`, is set in the editor. |

### Storage

| Path in the container      | Contents                                          | In backups |
| -------------------------- | ------------------------------------------------- | ---------- |
| `/config/config/glance.yml`| The dashboard                                     | Yes        |
| `/config/config/.env`      | Values for `${VARIABLES}`, passed to Glance only  | Yes        |
| `/config/assets/`          | Glance's assets folder, served under `/assets/`   | Yes        |
| `/config/editor/`          | The editor's versions and settings                | Yes        |
| `/config/preview/`         | The preview Glance's configuration                | Yes        |
| `/data/options.json`       | App options (empty), written by the Supervisor    | Yes        |

All of it is plain files, so the default hot backup is consistent enough: at worst a backup
taken during a save misses that save.

### Design decisions

**Build from source instead of `FROM ghcr.io/gcarstoiu/glance-editor`.** The published image
is `amd64` only. Building from a pinned commit costs a few minutes at installation but gives
`aarch64` users (Raspberry Pi) the same app. If the editor starts publishing multi-architecture
images, the Dockerfile can shrink to a `FROM` line plus the Home Assistant settings.

**No ingress.** Ingress serves an app under a per-app sub-path
(`/api/hassio_ingress/<token>/`). The editor's browser code calls absolute paths such as
`/api/state` and `/preview/`, and Glance needs its `base-url` set in `glance.yml`, which the
editor owns. Neither works without changing upstream code. The app publishes ports and sets
`webui` instead; `DOCS.md` explains how to add a sidebar entry with a Webpage dashboard.
Glance sends no `X-Frame-Options` header, so it can be framed.

**No Docker socket.** `docker_api: true` would let Glance's Docker containers widget work, but
it requires users to turn off protection mode and gives the app the lowest security rating.
The gate in `start.ts` finds no socket and stays idle.

**No login on the editor.** The editor has none by design (its ADR-0004: LAN only; mutating
requests must carry an `Origin` matching `Host`, with a JSON body). `DOCS.md` tells users to
close the editor's port when they are not editing.

**Building Glance instead of copying it from its image.** The official image is built with
whatever Go release was current when Glance was released, and Glance releases are months
apart. Building it on the device with the newest Go patch release, and raising vulnerable Go
modules, fixes known vulnerabilities in between without changing Glance's code. It adds a
minute or two to the installation. See [Security](security.md).

## Testing a change

Work through these in order. Each catches problems the previous one cannot. CI runs the
first four on every pull request, so they also run when the Update workflow proposes an
update. All of them need only Bash and Docker, also in Git Bash on Windows.

### 1. Lint

```bash
docker run --rm --network none -v "$PWD:/mnt:ro" -w /mnt koalaman/shellcheck:v0.11.0 \
  -x scripts/*.sh scripts/compat/*.sh
```

`.shellcheckrc` makes ShellCheck follow `source` lines relative to each script.

### 2. Glance against the editor

```bash
scripts/check-glance.sh
```

Builds the `glance` and `build` stages, then a throwaway image (`scripts/compat/`) that puts
the app's Glance binary next to the editor's source and points the editor's `glance.version`
at it. In that image it runs:

- the editor's `glance-source-data` script, comparing the widget types and themes in
  Glance's source with the editor's catalogue (version stamps aside);
- the editor's whole unit test suite (Vitest), many of whose tests run the Glance binary,
  including one that validates every community widget the editor offers;
- `config:validate` on each of the editor's fixtures, which Glance must accept or refuse.

When the app runs a newer Glance than the editor's pin, it also prints the changes to Glance's
configuration reference between the two. Read them: a new option is fine, a changed one may
need an editor release first.

The harness runs the tests as the unprivileged `node` user, because one of them checks that a
read-only file stops a save, and replaces the editor's `test/upstream-example.sh` (which needs
Docker and curl) with `scripts/compat/upstream-example.sh`. It leaves out one test by name:
the one asserting that the community widget snapshot records the version in `glance.version`,
which the harness changes on purpose.

To see that it catches real differences, build the compatibility image with an older Glance,
such as v0.8.5: the widget schema and icon tests fail.

### 3. Security

```bash
scripts/check-security.sh
```

Runs govulncheck on Glance's code as built, `npm audit` on the editor's runtime
dependencies, and Trivy on the app image. It fails on any known vulnerability with a fix
available. See [Security](security.md) for what to do when it fails.

### 4. Smoke test

```bash
scripts/smoke-test.sh
```

Builds the image, starts it with `--init` as the Supervisor does, starts an empty dashboard
through the editor's API, saves it, waits for Glance to serve it and for the health check to
pass, and checks that the app stops cleanly. CI runs it on `amd64` and `arm64` runners.

### 5. Build and run by hand

This checks the image without Home Assistant. It needs Docker Desktop or any Docker Engine.

```bash
docker build -t local/glance-app glance

mkdir -p test/data test/config test/media
echo '{}' > test/data/options.json

docker run --rm --init --name glance-test -p 8080:8080 -p 8090:3000 -e TZ=Europe/Amsterdam \
  -v "$PWD/test/data:/data" -v "$PWD/test/config:/config" -v "$PWD/test/media:/media:ro" \
  local/glance-app
```

Open <http://localhost:8090>, choose **Start empty**, and **Save**. The log should show
`[glance]` starting, and <http://localhost:8080> should show the dashboard. Check that
`test/config/config/glance.yml` exists, and that **Add images** > **Server folder** lists
`/media`. Stop with `docker stop glance-test`; the log should show `[start] stopping` and the
container should exit within a few seconds.
The `test/` folder is ignored by Git.

To build for the other architecture, add `--platform linux/arm64` (or `linux/amd64`) to
`docker build`; Docker Desktop emulates it, slowly.

### 6. In Home Assistant

Open the repository in VS Code with the Dev Containers extension and select **Reopen in
Container**. Run the **Start Home Assistant** task, open <http://localhost:7123>, and install
the app from the **Local apps** repository. This checks `config.yaml`, the translations, the
ports and the health check as the Supervisor sees them.
