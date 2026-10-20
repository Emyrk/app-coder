#!/bin/bash
# Runs next to coderd. Creates the first owner user and adds the license from
# the app options once the server is healthy. Every step is idempotent, so it
# is safe to run on each start.
set -uo pipefail

OPTIONS=/data/options.json
API=http://127.0.0.1:3000
LICENSE_HASH_FILE=/data/license.sha256

opt() {
	jq -r --arg k "$1" '.[$k] // empty' "$OPTIONS"
}

log() {
	echo "[coder-app] $*"
}

# api METHOD PATH [TOKEN]: sends stdin as the JSON body so secrets never
# appear in process arguments. Prints the body, then the status code on the
# last line.
api() {
	local args=(-sS -X "$1" -H "Content-Type: application/json" -w '\n%{http_code}')
	[[ -n "${3:-}" ]] && args+=(-H "Coder-Session-Token: $3")
	[[ "$1" != GET ]] && args+=(--data-binary @-)
	curl "${args[@]}" "${API}$2"
}

status_of() { tail -n1 <<<"$1"; }
body_of() { sed '$d' <<<"$1"; }
message_of() { body_of "$1" | jq -r '[.message, .detail] | map(select(. != null and . != "")) | join(": ")' 2>/dev/null; }

email="$(opt admin_email)"
username="$(opt admin_username)"
password="$(opt admin_password)"
license="$(opt license)"

for _ in $(seq 1 150); do
	curl -fsS "${API}/healthz" >/dev/null 2>&1 && break
	sleep 2
done
if ! curl -fsS "${API}/healthz" >/dev/null 2>&1; then
	log "Coder did not become healthy; skipping first user and license setup."
	exit 0
fi

if [[ -n "$email" && -n "$password" ]]; then
	resp="$(api GET /api/v2/users/first </dev/null)"
	if [[ "$(status_of "$resp")" == 404 ]]; then
		[[ -n "$username" ]] || username="${email%%@*}"
		resp="$(jq -n --arg e "$email" --arg u "$username" --arg p "$password" \
			'{email: $e, username: $u, password: $p}' | api POST /api/v2/users/first)"
		if [[ "$(status_of "$resp")" == 201 ]]; then
			log "Created first owner user ${username}."
		else
			log "Could not create first user: $(message_of "$resp")"
		fi
	fi
fi

[[ -n "$license" ]] || exit 0

hash="$(printf '%s' "$license" | sha256sum | cut -d' ' -f1)"
if [[ -f "$LICENSE_HASH_FILE" && "$(cat "$LICENSE_HASH_FILE")" == "$hash" ]]; then
	exit 0
fi

if [[ -z "$email" || -z "$password" ]]; then
	log "A license is set, but admin_email and admin_password are not. Add the license in the dashboard under Deployment > Licenses."
	exit 0
fi

resp="$(jq -n --arg e "$email" --arg p "$password" '{email: $e, password: $p}' |
	api POST /api/v2/users/login)"
if [[ "$(status_of "$resp")" != 201 ]]; then
	log "Could not log in as ${email} to add the license: $(message_of "$resp")"
	exit 0
fi
token="$(body_of "$resp" | jq -r .session_token)"

resp="$(jq -n --arg l "$license" '{license: $l}' | api POST /api/v2/licenses "$token")"
case "$(status_of "$resp")" in
201)
	log "Added the Coder license."
	echo "$hash" >"$LICENSE_HASH_FILE"
	;;
*)
	msg="$(message_of "$resp")"
	if grep -qi "duplicate\|already exists\|unique" <<<"$msg"; then
		log "The Coder license is already installed."
		echo "$hash" >"$LICENSE_HASH_FILE"
	else
		log "Could not add the license: ${msg}"
	fi
	;;
esac

api POST /api/v2/users/logout "$token" </dev/null >/dev/null 2>&1 || true
