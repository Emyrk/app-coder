#!/bin/bash
# Entrypoint for the Coder Home Assistant app. Translates the app options in
# /data/options.json into Coder server environment variables, then starts
# coderd as the unprivileged coder user.
set -euo pipefail

OPTIONS=/data/options.json

opt() {
	jq -r --arg k "$1" '.[$k] // empty' "$OPTIONS"
}

fail() {
	echo "[coder-app] ERROR: $*" >&2
	exit 1
}

access_url="$(opt access_url)"
pg_url="$(opt pg_connection_url)"

[[ -n "$access_url" ]] || fail "access_url is required."
[[ -n "$pg_url" ]] || fail "pg_connection_url is required. This app does not run its own PostgreSQL."

# Extra settings from the env_vars option. They are exported before the
# settings below so that the app-managed values always win.
while IFS=$'\t' read -r name value; do
	[[ -n "$name" ]] || continue
	export "$name"="$(base64 -d <<<"$value")"
done < <(jq -r '.env_vars[]? | "\(.name)\t\(.value | @base64)"' "$OPTIONS")

mkdir -p /data/cache /data/config
chown -R coder:coder /data/cache /data/config

export CODER_ACCESS_URL="$access_url"
export CODER_PG_CONNECTION_URL="$pg_url"
export CODER_HTTP_ADDRESS="0.0.0.0:3000"
# Only external provisioner daemons run workspace builds.
export CODER_PROVISIONER_DAEMONS=0
export CODER_CACHE_DIRECTORY=/data/cache
export CODER_CONFIG_DIR=/data/config
export HOME=/data/config

if [[ -n "$(opt license)" || -n "$(opt admin_email)" ]]; then
	# Detach so the init process, not coderd, reaps it when it exits.
	(/usr/local/bin/bootstrap.sh &)
fi

echo "[coder-app] Starting Coder with access URL ${access_url}"
exec su-exec coder:coder /opt/coder server
