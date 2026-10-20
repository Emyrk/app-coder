# Keep the tag in sync with "version" in config.yaml. Home Assistant only
# offers an update when that version changes.
FROM ghcr.io/coder/coder:v2.37.5

USER root
RUN apk add --no-cache jq su-exec

COPY --chmod=755 run.sh bootstrap.sh /usr/local/bin/

HEALTHCHECK --interval=30s --timeout=5s --start-period=2m \
	CMD curl -fsS http://127.0.0.1:3000/healthz || exit 1

ENTRYPOINT ["/usr/local/bin/run.sh"]
