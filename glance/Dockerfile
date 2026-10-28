# Glance and the Glance Editor (glance-ui), packaged as a Home Assistant app.
#
# The editor's published image is built for amd64 only, so the app builds the
# editor from source instead: the same stages as the editor's own Dockerfile,
# with its source downloaded at a pinned commit. All images are pinned by the
# digest of their multi-architecture index, so they resolve to the right build
# on amd64 and aarch64.
#
# Pins come in two kinds (see .docs/development.md#pins):
# - EDITOR_*: what the editor release pins. The build checks these against the
#   editor's own source, and builds the editor with that Node image.
# - GLANCE_*, GO_IMAGE, GLANCE_GO_UPDATES and NODE_IMAGE: what the app runs.
#   Glance is built from its unchanged source with a patched Go toolchain and
#   dependency security updates, and runs on the newest Node of the editor's
#   major version. scripts/check-glance.sh and scripts/check-security.sh test
#   these.
#
# scripts/update-glance.sh updates all of them and the `version` in
# config.yaml together (see .docs/releasing.md).
ARG EDITOR_VERSION=1.2.0
ARG EDITOR_COMMIT=0b3fdc1ba5585fe72b1e51e128848756d7a1a733
ARG EDITOR_GLANCE_VERSION=v0.8.6
ARG EDITOR_GLANCE_COMMIT=fbd9c1b6ae0c50ec015843f1bea48c400cddb518
ARG EDITOR_GLANCE_IMAGE=glanceapp/glance:v0.8.6@sha256:9dfb09470b207dcb67ac715994bdb1929374ba3f9c0d7df7462c24adf10fd073
ARG EDITOR_NODE_IMAGE=node:24-slim@sha256:d6aa754f16b3197301076f047b5def2f02ea1dbbc2ca920407d46d7ec7f87b20
ARG GLANCE_VERSION=v0.8.7
ARG GLANCE_COMMIT=698db7126f8e744263cb7f4ed6301c248f7a3d9c
ARG GLANCE_GO_UPDATES=golang.org/x/net@v0.62.0
ARG GO_IMAGE=golang:1.27.3-alpine@sha256:b8c9b82affbbb82a020bbcf998dad2ba9516944ac7e883524642a481a9505e9c
ARG NODE_IMAGE=node:24-slim@sha256:55fb5f5a527ea2c5c4a95f963e48ef90aa38c7b346054fdc8ee9957a2b55d205

# Glance, built the way its own Dockerfile does, from its unchanged source.
# GLANCE_GO_UPDATES raises Go modules Glance depends on to their security
# releases; Glance's code is not touched.
FROM ${GO_IMAGE} AS glance
ARG GLANCE_COMMIT
ARG GLANCE_GO_UPDATES
WORKDIR /src
ADD https://github.com/glanceapp/glance/archive/${GLANCE_COMMIT}.tar.gz /tmp/glance.tar.gz
RUN tar -xzf /tmp/glance.tar.gz --strip-components=1 && rm /tmp/glance.tar.gz
RUN if [ -n "${GLANCE_GO_UPDATES}" ]; then go get ${GLANCE_GO_UPDATES}; fi
RUN CGO_ENABLED=0 GOTOOLCHAIN=local go build -o /glance .

FROM ${EDITOR_NODE_IMAGE} AS build
ARG EDITOR_COMMIT
ARG EDITOR_GLANCE_VERSION
ARG EDITOR_GLANCE_COMMIT
ARG EDITOR_GLANCE_IMAGE
ARG EDITOR_NODE_IMAGE
WORKDIR /src
ADD https://github.com/gcarstoiu/glance-ui/archive/${EDITOR_COMMIT}.tar.gz /tmp/glance-ui.tar.gz
RUN tar -xzf /tmp/glance-ui.tar.gz --strip-components=1 && rm /tmp/glance-ui.tar.gz
# The editor pins one Glance version and one Node image; the pins above must
# match the ones in its own source.
RUN for pin in "GLANCE_VERSION=${EDITOR_GLANCE_VERSION}" "GLANCE_COMMIT=${EDITOR_GLANCE_COMMIT}" "GLANCE_IMAGE=${EDITOR_GLANCE_IMAGE}"; \
  do grep -qxF "$pin" glance.version || { echo "$pin does not match the editor's glance.version." >&2; exit 1; }; \
  done; \
  grep -qxF "ARG NODE_IMAGE=${EDITOR_NODE_IMAGE}" Dockerfile || { echo "EDITOR_NODE_IMAGE does not match the editor's Dockerfile." >&2; exit 1; }
RUN npm ci --no-audit --no-fund && npm -w apps/editor run build

# From here on, the final stage of the editor's own Dockerfile, on the newer
# Node image and with the Glance built above.
FROM ${NODE_IMAGE}
ARG EDITOR_VERSION
ARG GLANCE_COMMIT
ARG GLANCE_VERSION
LABEL org.opencontainers.image.title="Glance Editor" \
      org.opencontainers.image.version="${EDITOR_VERSION}" \
      org.opencontainers.image.licenses="GPL-3.0-only" \
      org.glance-editor.glance-commit="${GLANCE_COMMIT}"
# Security updates released for the Debian base after the Node image was
# published. The package managers that ship with the Node image (npm, npx,
# corepack, yarn) are not used at runtime, so they are removed with their
# dependencies.
RUN apt-get update \
  && apt-get upgrade -y --no-install-recommends \
  && rm -rf /var/lib/apt/lists/* \
  && rm -rf /usr/local/lib/node_modules /opt/yarn-* \
    /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack /usr/local/bin/yarn /usr/local/bin/yarnpkg
COPY --from=glance /glance /usr/local/bin/glance
# Glance verifies HTTPS sites against these certificates; node:slim has none.
COPY --from=glance /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=build /src/third_party/glance/LICENSE /src/third_party/glance/README.md /usr/share/doc/glance/
COPY --from=build /src/LICENSE /usr/share/doc/glance-editor/LICENSE
WORKDIR /app
COPY --from=build /src/apps/editor/build build
COPY --from=build /src/image/start.ts /src/image/docker-gate.ts /src/image/dotenv.ts image/
# Only root reaches /run, and no setuid program can make the editor's user root.
RUN echo '{"type":"module"}' > package.json \
  && chmod 0700 /run && find / -xdev -perm -4000 -type f -exec chmod u-s {} +
ENV NODE_ENV=production PORT=3000 GLANCE_BIN=/usr/local/bin/glance GLANCE_VERSION=${GLANCE_VERSION} \
    GLANCE_CONFIG=/glance-config/glance.yml EDITOR_DATA_DIR=/data BODY_SIZE_LIMIT=100M
# start.ts starts as root, and runs the editor as PUID:PGID.
ENV PUID=99 PGID=100

# Home Assistant: keep the dashboard in the app configuration folder instead of
# /data, so glance.yml, .env and the assets are reachable through the
# app_configs share. start.ts derives every other path from DATA_DIR. The
# Home Assistant media and share folders are offered for backgrounds.
ENV DATA_DIR=/config SERVER_FOLDERS=/media,/share

EXPOSE 8080 3000
# The Supervisor shows the app as starting until this check passes, and its
# watchdog restarts the app when it fails. It runs inside the container, so it
# keeps working when the editor's port is not published.
HEALTHCHECK --start-period=60s --interval=30s --timeout=3s \
  CMD [ "node", "-e", "fetch('http://127.0.0.1:3000/healthz').then(r=>process.exit(r.ok?0:1),()=>process.exit(1))" ]
CMD [ "node", "/app/image/start.ts" ]
