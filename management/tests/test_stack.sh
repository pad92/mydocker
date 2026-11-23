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
#   and the worker has neither root nor the Docker socket.
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
  -e "s|^PROXMOX_UPSTREAM_URL=.*|PROXMOX_UPSTREAM_URL=https://192.0.2.10:8006|" \
  "$stack_dir/.env.example" > "$work_dir/test.env"

for var in AUTHENTIK_SECRET_KEY AUTHENTIK_PG_PASS AUTHENTIK_HOST_LOCAL MANAGEMENT_AUTHENTIK_DATA_DIR; do
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

echo "OK"
