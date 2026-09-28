# Custom layered build for Frappe Builder on Frappe version-16.
#
# Based on frappe/frappe_docker images/layered/Containerfile, with one
# addition: Builder's develop branch imports two modules from Frappe's
# in-core ui package that only exist on frappe/develop
#   - @framework/ui/telemetry
#   - @framework/ui/components/TrialBanner
# They are vendored in after app install and before the asset build, so
# Builder develop can compile on the version-16 framework.
ARG FRAPPE_BRANCH=version-16
ARG FRAPPE_IMAGE_PREFIX=frappe

FROM ${FRAPPE_IMAGE_PREFIX}/build:${FRAPPE_BRANCH} AS builder

ARG FRAPPE_BRANCH=version-16
ARG FRAPPE_PATH=https://github.com/frappe/frappe
ARG CACHE_BUST=""

USER frappe

# Install the framework and the apps (from apps.json) without building assets yet.
RUN --mount=type=secret,id=apps_json,target=/opt/frappe/apps.json,uid=1000,gid=1000 \
  : "${CACHE_BUST}" && \
  export APP_INSTALL_ARGS="" && \
  if [ -f /opt/frappe/apps.json ] && [ -s /opt/frappe/apps.json ]; then \
    export APP_INSTALL_ARGS="--apps_path=/opt/frappe/apps.json"; \
  fi && \
  bench init ${APP_INSTALL_ARGS}\
    --skip-assets \
    --frappe-branch=${FRAPPE_BRANCH} \
    --frappe-path=${FRAPPE_PATH} \
    --no-procfile \
    --no-backups \
    --skip-redis-config-generation \
    --verbose \
    /home/frappe/frappe-bench

# Vendor the two framework ui modules that Builder develop imports and that
# are not present on the version-16 branch.
RUN git clone --depth 1 --branch develop https://github.com/frappe/frappe /tmp/frappe-develop && \
  cp -r /tmp/frappe-develop/ui/src/telemetry /home/frappe/frappe-bench/apps/frappe/ui/src/telemetry && \
  cp -r /tmp/frappe-develop/ui/src/components/TrialBanner /home/frappe/frappe-bench/apps/frappe/ui/src/components/TrialBanner && \
  rm -rf /tmp/frappe-develop

# Build assets now that the missing modules are in place.
RUN cd /home/frappe/frappe-bench && \
  echo "{}" > sites/common_site_config.json && \
  bench build && \
  find apps -mindepth 1 -path "*/.git" | xargs rm -fr

FROM ${FRAPPE_IMAGE_PREFIX}/base:${FRAPPE_BRANCH} AS backend

USER frappe

COPY --from=builder --chown=frappe:frappe /home/frappe/frappe-bench /home/frappe/frappe-bench

WORKDIR /home/frappe/frappe-bench

# Move assets to image-layer storage
RUN cp -r /home/frappe/frappe-bench/sites/assets /home/frappe/frappe-bench/assets && \
  rm -rf /home/frappe/frappe-bench/sites/assets

VOLUME [ \
  "/home/frappe/frappe-bench/sites", \
  "/home/frappe/frappe-bench/logs" \
]

USER root
# This entrypoint script link build assets of the image to the mounted sites volume at container initialization
COPY resources/core/main-entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh

COPY resources/core/start.sh /usr/local/bin/start.sh
RUN chmod 755 /usr/local/bin/start.sh

USER frappe
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["start.sh"]
