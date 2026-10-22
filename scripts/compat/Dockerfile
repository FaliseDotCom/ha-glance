# The editor's build stage with the Glance the app builds, to run the editor's
# own checks against that Glance. Built and run by scripts/check-glance.sh;
# never part of the app image.
#
# The editor's checks read the Glance version from its glance.version file, so
# this image points that file at the app's Glance. The change only exists in
# this throwaway image.
ARG BASE=local/glance-app-build
ARG GLANCE_BUILD=local/glance-app-glance

FROM ${GLANCE_BUILD} AS glance

FROM ${BASE}
ARG GLANCE_VERSION
ARG GLANCE_COMMIT
COPY --from=glance /glance /usr/local/bin/glance
COPY --from=glance /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
# Glance's own example configuration, the import fixture of the editor's
# round-trip tests. The editor's script for it needs Docker and curl.
ADD https://raw.githubusercontent.com/glanceapp/glance/${GLANCE_COMMIT}/docs/glance.yml /opt/upstream-example/glance.yml
COPY upstream-example.sh /src/test/upstream-example.sh
COPY run.sh /usr/local/bin/compat-run
RUN sed -i \
    -e "s|^GLANCE_VERSION=.*|GLANCE_VERSION=${GLANCE_VERSION}|" \
    -e "s|^GLANCE_COMMIT=.*|GLANCE_COMMIT=${GLANCE_COMMIT}|" \
    /src/glance.version \
  && chmod 0755 /src/test/upstream-example.sh /usr/local/bin/compat-run /opt/upstream-example \
  && chmod 0644 /opt/upstream-example/glance.yml \
  && chown -R node:node /src
# Some tests check that a read-only file stops a save, which root ignores.
USER node
ENV GLANCE_BIN=/usr/local/bin/glance
CMD [ "compat-run" ]
