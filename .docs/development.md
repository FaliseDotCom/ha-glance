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
.devcontainer/, .vscode/     Home Assistant development environment
.docs/                       Documentation for contributors
scripts/update-glance.sh     Bumps the app to a new Glance Editor release
```

## How the app works

The app packages the [Glance Editor](https://github.com/gcarstoiu/glance-ui) (glance-ui)
all-in-one container. That container already runs everything the app needs, so the app adds
no start script of its own; it only builds the image and sets where the data lives.

### The image

The editor publishes `ghcr.io/gcarstoiu/glance-editor` for `amd64` only. To support `aarch64`
as well, the Dockerfile builds the editor from source on the user's device:

1. **`glance` stage:** the official `glanceapp/glance` image, pinned by the digest of its
   multi-architecture index, so each device gets its own build of the binary.
2. **`build` stage:** downloads the editor's source as a GitHub archive at a pinned commit,
   checks that the Glance and Node pins in the Dockerfile match the editor's own
   `glance.version` and `Dockerfile` (the build stops when they differ), then runs `npm ci`
   and builds the SvelteKit app.
3. **final stage:** a copy of the final stage of the editor's own Dockerfile, followed by the
   Home Assistant settings described below.

Each editor release pins one Glance version and validates every save with that exact binary,
so the two are always updated together.

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

## Testing a change

Work through these in order. Each catches problems the previous one cannot.

### 1. Lint

```bash
docker run --rm -v "$PWD/scripts:/mnt" koalaman/shellcheck:stable /mnt/update-glance.sh
```

### 2. Build and run with Docker

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

### 3. In Home Assistant

Open the repository in VS Code with the Dev Containers extension and select **Reopen in
Container**. Run the **Start Home Assistant** task, open <http://localhost:7123>, and install
the app from the **Local apps** repository. This checks `config.yaml`, the translations, the
ports and the health check as the Supervisor sees them.
