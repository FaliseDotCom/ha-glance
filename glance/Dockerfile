# Glance and the Glance Editor (glance-ui), packaged as a Home Assistant app.
#
# The editor's published image is built for amd64 only, so the app builds the
# editor from source instead: the same stages as the editor's own Dockerfile,
# with its source downloaded at a pinned commit. The Glance and Node images are
# the ones that editor release pins, by the digest of their multi-architecture
# index, so they resolve to the right build on amd64 and aarch64.
#
# Bump the editor version, its commit, the Glance image and version, and the
# `version` in config.yaml together (see .docs/releasing.md).
ARG EDITOR_VERSION=1.2.0
ARG EDITOR_COMMIT=0b3fdc1ba5585fe72b1e51e128848756d7a1a733
ARG GLANCE_VERSION=v0.8.6
ARG GLANCE_COMMIT=fbd9c1b6ae0c50ec015843f1bea48c400cddb518
ARG GLANCE_IMAGE=glanceapp/glance:v0.8.6@sha256:9dfb09470b207dcb67ac715994bdb1929374ba3f9c0d7df7462c24adf10fd073
ARG NODE_IMAGE=node:24-slim@sha256:d6aa754f16b3197301076f047b5def2f02ea1dbbc2ca920407d46d7ec7f87b20

FROM ${GLANCE_IMAGE} AS glance

FROM ${NODE_IMAGE} AS build
ARG EDITOR_COMMIT
ARG GLANCE_VERSION
ARG GLANCE_COMMIT
ARG GLANCE_IMAGE
ARG NODE_IMAGE
WORKDIR /src
ADD https://github.com/gcarstoiu/glance-ui/archive/${EDITOR_COMMIT}.tar.gz /tmp/glance-ui.tar.gz
RUN tar -xzf /tmp/glance-ui.tar.gz --strip-components=1 && rm /tmp/glance-ui.tar.gz
# The editor validates every save with the Glance binary it was released with,
# so the pins above must match the ones in the editor's own source.
RUN for pin in "GLANCE_VERSION=${GLANCE_VERSION}" "GLANCE_COMMIT=${GLANCE_COMMIT}" "GLANCE_IMAGE=${GLANCE_IMAGE}"; \
  do grep -qxF "$pin" glance.version || { echo "$pin does not match the editor's glance.version." >&2; exit 1; }; \
  done; \
  grep -qxF "ARG NODE_IMAGE=${NODE_IMAGE}" Dockerfile || { echo "NODE_IMAGE does not match the editor's Dockerfile." >&2; exit 1; }
RUN npm ci --no-audit --no-fund && npm -w apps/editor run build

# From here on, the final stage of the editor's own Dockerfile.
FROM ${NODE_IMAGE}
ARG EDITOR_VERSION
ARG GLANCE_COMMIT
ARG GLANCE_VERSION
LABEL org.opencontainers.image.title="Glance Editor" \
      org.opencontainers.image.version="${EDITOR_VERSION}" \
      org.opencontainers.image.licenses="GPL-3.0-only" \
      org.glance-editor.glance-commit="${GLANCE_COMMIT}"
COPY --from=glance /app/glance /usr/local/bin/glance
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
