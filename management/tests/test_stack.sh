#!/usr/bin/env bash
# Static checks on the management compose file rendered with .env.example
# (nothing is started). Covers the Authentik part:
# - the Authentik secrets and data directory are required;
# - the internal and public host names have separate HTTPS routers, so each
#   gets its own certificate, and an empty public name falls back to the
#   internal one;
# - the outpost router catches /outpost.goauthentik.io/ ahead of host routers;
# - the forward-auth middleware calls the embedded outpost;
# - PostgreSQL stays on the private network, no Authentik port is published,
#   and the worker has neither root nor the Docker socket;
# - the worker gets the versioned blueprints read-only and the host names they
#   read (the outpost uses the public Authentik name when set, else the
#   internal one), and the blueprints themselves hold no host name, URL or
#   address;
# - Uptime Kuma is behind forward auth, except its /api/push/ path.
# Needs Docker Compose 2.23+ and jq. Usage: ./tests/test_stack.sh
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# Renders the compose file with test.env plus the given VAR=value overrides.
render() { env "$@" docker compose --project-directory "$stack_dir" \
  --env-file "$work_dir/test.env" config --format json; }

# Required values are empty in .env.example.
sed -e "s|^ACME_CA_SERVER=.*|ACME_CA_SERVER=https://ca.test/acme/acme/directory|" \
  -e "s|^AUTHENTIK_HOST_LOCAL=.*|AUTHENTIK_HOST_LOCAL=auth.home.test|" \
  -e "s|^MANAGEMENT_AUTHENTIK_DATA_DIR=.*|MANAGEMENT_AUTHENTIK_DATA_DIR=$work_dir/authentik|" \
  -e "s|^MANAGEMENT_PORTAINER_DATA_DIR=.*|MANAGEMENT_PORTAINER_DATA_DIR=$work_dir/portainer|" \
  -e "s|^MANAGEMENT_UPTIME_KUMA_DATA_DIR=.*|MANAGEMENT_UPTIME_KUMA_DATA_DIR=$work_dir/uptime-kuma|" \
  -e "s|^PROXMOX_HOST_LOCAL=.*|PROXMOX_HOST_LOCAL=pve.home.test|" \
  -e "s|^UPTIME_HOST_LOCAL=.*|UPTIME_HOST_LOCAL=uptime.home.test|" \
  -e "s|^PROXMOX_UPSTREAM_URL=.*|PROXMOX_UPSTREAM_URL=https://192.0.2.10:8006|" \
  "$stack_dir/.env.example" > "$work_dir/test.env"

for var in AUTHENTIK_SECRET_KEY AUTHENTIK_PG_PASS AUTHENTIK_HOST_LOCAL UPTIME_HOST_LOCAL MANAGEMENT_AUTHENTIK_DATA_DIR; do
  if render "$var=" >/dev/null 2>&1; then fail "$var is not required"; fi
done

config="$(render)"
server='.services.authentik_server'
label() { jq -r "$server.labels[\"$1\"]" <<<"$config"; }

[ "$(label traefik.http.routers.authentik.rule)" = 'Host(`auth.home.test`)' ] \
  || fail "internal HTTPS router does not match only the internal host"
[ "$(label traefik.http.routers.authentik_pub.rule)" = 'Host(`auth.home.test`)' ] \
  || fail "public router does not fall back to the internal host"
public_rule="$(render AUTHENTIK_HOST_PUBLIC=auth.example.test \
  | jq -r "$server.labels[\"traefik.http.routers.authentik_pub.rule\"]")"
[ "$public_rule" = 'Host(`auth.example.test`)' ] \
  || fail "public router does not match AUTHENTIK_HOST_PUBLIC: $public_rule"
for router in authentik authentik_pub; do
  [ "$(label "traefik.http.routers.$router.tls.certresolver")" = stepca ] \
    || fail "router $router has no certificate resolver"
done

[ "$(label traefik.http.routers.authentik_outpost.rule)" = 'PathPrefix(`/outpost.goauthentik.io/`)' ] \
  || fail "outpost router does not catch the outpost path"
[ "$(label traefik.http.routers.authentik_outpost.priority)" = 1000 ] \
  || fail "outpost router is not ahead of the host routers"
[ "$(label traefik.http.middlewares.authentik.forwardauth.address)" = \
  http://authentik_server:9000/outpost.goauthentik.io/auth/traefik ] \
  || fail "forward-auth middleware does not call the embedded outpost"

[ "$(jq -c '.services.authentik_postgresql.networks | keys' <<<"$config")" = '["authentik"]' ] \
  || fail "PostgreSQL is reachable outside the authentik network"
for service in authentik_postgresql authentik_server authentik_worker; do
  [ "$(jq -r ".services.$service.ports // [] | length" <<<"$config")" = 0 ] \
    || fail "$service publishes a host port"
  jq -e ".services.$service.security_opt | index(\"no-new-privileges:true\")" <<<"$config" >/dev/null \
    || fail "$service lacks no-new-privileges"
done
[ "$(jq -r '.services.authentik_worker.user // ""' <<<"$config")" = "" ] \
  || fail "worker runs with an explicit user (root in the official file)"
if jq -e '.services.authentik_worker.volumes[] | select(.source == "/var/run/docker.sock")' <<<"$config" >/dev/null; then
  fail "worker mounts the Docker socket"
fi

worker='.services.authentik_worker'
jq -e "$worker.volumes[] | select(.source == \"$stack_dir/authentik/blueprints\"
  and .target == \"/blueprints/custom\" and .read_only == true)" <<<"$config" >/dev/null \
  || fail "worker does not mount the blueprints read-only on /blueprints/custom"
[ "$(jq -r "$worker.environment.BLUEPRINT_AUTHENTIK_HOST" <<<"$config")" = auth.home.test ] \
  || fail "BLUEPRINT_AUTHENTIK_HOST does not fall back to AUTHENTIK_HOST_LOCAL"
outpost_host="$(render AUTHENTIK_HOST_PUBLIC=auth.example.test \
  | jq -r "$worker.environment.BLUEPRINT_AUTHENTIK_HOST")"
[ "$outpost_host" = auth.example.test ] \
  || fail "BLUEPRINT_AUTHENTIK_HOST is not AUTHENTIK_HOST_PUBLIC when set: $outpost_host"
[ "$(jq -r "$worker.environment.BLUEPRINT_UPTIME_HOST" <<<"$config")" = uptime.home.test ] \
  || fail "BLUEPRINT_UPTIME_HOST is not UPTIME_HOST_LOCAL"
[ "$(jq -r "$worker.environment.AUTHENTIK_SECRET_KEY" <<<"$config")" != null ] \
  || fail "worker lost the shared Authentik environment"
# Private names belong in .env only: no domain, URL, e-mail or IP address in
# the versioned blueprints.
if grep -nE '[A-Za-z0-9-]+\.(lan|local|home|internal|com|fr|net|org|io)\b|https?://[^"%]|@|([0-9]{1,3}\.){3}[0-9]{1,3}' \
  "$stack_dir"/authentik/blueprints/*.yaml | grep -vE '^[^:]+:[0-9]+:\s*#|goauthentik\.io/(outposts|blueprints)'; then
  fail "a blueprint holds a host name, URL, e-mail or address"
fi

uptime='.services["uptime-kuma"].labels'
[ "$(jq -r "$uptime[\"traefik.http.routers.uptime.middlewares\"]" <<<"$config")" = authentik@docker ] \
  || fail "Uptime Kuma router is not behind forward auth"
[ "$(jq -r "$uptime[\"traefik.http.routers.uptime_push.rule\"]" <<<"$config")" = \
  'Host(`uptime.home.test`) && PathPrefix(`/api/push/`)' ] \
  || fail "push router does not match only /api/push/ on the Uptime Kuma host"
[ "$(jq -r "$uptime[\"traefik.http.routers.uptime_push.middlewares\"] // \"\"" <<<"$config")" = "" ] \
  || fail "push router has a middleware: push monitors would need a login"
[ "$(jq -r "$uptime[\"traefik.http.routers.uptime_push.service\"]" <<<"$config")" = uptime ] \
  || fail "push router does not target the Uptime Kuma service"

echo "OK"
