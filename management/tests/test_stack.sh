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
# - the server gets the branding files read-only where Authentik serves the
#   "homelab/..." file names of the blueprints (files: tests/test_media.sh);
# - Uptime Kuma is behind forward auth, except its /api/push/ path;
# - Portainer is behind forward auth, with no bypass router, and mounts the
#   step-ca root read-only (its OAuth login calls Authentik over HTTPS);
# - the OpenObserve, Forgejo and Gramps Web host names reach the blueprints (OpenObserve
#   routers are checked in openobserve/tests/test_stack.sh).
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
  -e "s|^NG_HOST_LOCAL=.*|NG_HOST_LOCAL=media.home.test|" \
  -e "s|^PORTAINER_HOST_LOCAL=.*|PORTAINER_HOST_LOCAL=portainer.home.test|" \
  -e "s|^OPENOBSERVE_HOST_LOCAL=.*|OPENOBSERVE_HOST_LOCAL=logs.home.test|" \
  -e "s|^FORGEJO_HOST_LOCAL=.*|FORGEJO_HOST_LOCAL=git.home.test|" \
  -e "s|^GRAMPSWEB_HOST_LOCAL=.*|GRAMPSWEB_HOST_LOCAL=genealogy.home.test|" \
  -e "s|^UNIFI_HOST_LOCAL=.*|UNIFI_HOST_LOCAL=unifi.home.test|" \
  -e "s|^NAS_HOST_LOCAL=.*|NAS_HOST_LOCAL=nas.home.test|" \
  -e "s|^SWITCH_HOST_LOCAL=.*|SWITCH_HOST_LOCAL=192.0.2.30|" \
  -e "s|^PROXMOX_UPSTREAM_URL=.*|PROXMOX_UPSTREAM_URL=https://192.0.2.10:8006|" \
  "$stack_dir/.env.example" > "$work_dir/test.env"

for var in AUTHENTIK_SECRET_KEY AUTHENTIK_PG_PASS CA_CERT_NAME MANAGEMENT_SHARE_CA_CERTIFICATES_DATA_DIR AUTHENTIK_HOST_LOCAL UPTIME_HOST_LOCAL NG_HOST_LOCAL PORTAINER_HOST_LOCAL OPENOBSERVE_HOST_LOCAL FORGEJO_HOST_LOCAL GRAMPSWEB_HOST_LOCAL UNIFI_HOST_LOCAL NAS_HOST_LOCAL SWITCH_HOST_LOCAL MANAGEMENT_AUTHENTIK_DATA_DIR; do
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
[ "$(jq -r "$worker.environment.BLUEPRINT_NG_HOST" <<<"$config")" = media.home.test ] \
  || fail "BLUEPRINT_NG_HOST is not NG_HOST_LOCAL"
[ "$(jq -r "$worker.environment.BLUEPRINT_PORTAINER_HOST" <<<"$config")" = portainer.home.test ] \
  || fail "BLUEPRINT_PORTAINER_HOST is not PORTAINER_HOST_LOCAL"
[ "$(jq -r "$worker.environment.BLUEPRINT_OPENOBSERVE_HOST" <<<"$config")" = logs.home.test ] \
  || fail "BLUEPRINT_OPENOBSERVE_HOST is not OPENOBSERVE_HOST_LOCAL"
[ "$(jq -r "$worker.environment.BLUEPRINT_FORGEJO_HOST" <<<"$config")" = git.home.test ] \
  || fail "BLUEPRINT_FORGEJO_HOST is not FORGEJO_HOST_LOCAL"
[ "$(jq -r "$worker.environment.BLUEPRINT_GRAMPSWEB_HOST" <<<"$config")" = genealogy.home.test ] \
  || fail "BLUEPRINT_GRAMPSWEB_HOST is not GRAMPSWEB_HOST_LOCAL"
[ "$(jq -r "$worker.environment.BLUEPRINT_UNIFI_HOST" <<<"$config")" = unifi.home.test ] \
  || fail "BLUEPRINT_UNIFI_HOST is not UNIFI_HOST_LOCAL"
[ "$(jq -r "$worker.environment.BLUEPRINT_NAS_HOST" <<<"$config")" = nas.home.test ] \
  || fail "BLUEPRINT_NAS_HOST is not NAS_HOST_LOCAL"
[ "$(jq -r "$worker.environment.BLUEPRINT_SWITCH_HOST" <<<"$config")" = 192.0.2.30 ] \
  || fail "BLUEPRINT_SWITCH_HOST is not SWITCH_HOST_LOCAL"
[ "$(jq -r "$worker.environment.AUTHENTIK_SECRET_KEY" <<<"$config")" != null ] \
  || fail "worker lost the shared Authentik environment"
# Private names belong in .env only: no domain, URL, e-mail or IP address in
# the versioned blueprints. goauthentik.io/... are Authentik managed keys.
jq -e "$server.volumes[] | select(.source == \"$stack_dir/authentik/media\"
  and .target == \"/data/media/public/homelab\" and .read_only == true)" <<<"$config" >/dev/null \
  || fail "server does not mount the branding files read-only on /data/media/public/homelab"
if grep -nE '[A-Za-z0-9-]+\.(lan|local|home|internal|com|fr|net|org|io)\b|https?://[^"%]|@|([0-9]{1,3}\.){3}[0-9]{1,3}' \
  "$stack_dir"/authentik/blueprints/*.yaml | grep -vE '^[^:]+:[0-9]+:\s*#|goauthentik\.io/(outposts|blueprints|providers)/'; then
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

portainer='.services.portainer.labels'
[ "$(jq -r "$portainer[\"traefik.http.routers.portainer.middlewares\"]" <<<"$config")" = \
  authentik@docker,portainer-stripprefix@docker ] \
  || fail "Portainer router is not behind forward auth (first middleware)"
# Every router on the Portainer host other than the HTTP redirect must carry
# the middleware: a bypass router would expose the whole API.
jq -r "$portainer | to_entries[] | select(.key | test(\"^traefik.http.routers.[^.]+.rule$\"))
  | select(.value | contains(\"portainer.home.test\")) | .key | split(\".\")[3]" <<<"$config" \
  | while read -r router; do
      [ "$router" = portainer_http ] && continue
      jq -r "$portainer[\"traefik.http.routers.$router.middlewares\"] // \"\"" <<<"$config" \
        | grep -q '^authentik@docker' || fail "Portainer router $router bypasses forward auth"
    done
ca_name="$(sed -n 's/^CA_CERT_NAME=//p' "$work_dir/test.env")"
ca_dir="$(sed -n 's/^MANAGEMENT_SHARE_CA_CERTIFICATES_DATA_DIR=//p' "$work_dir/test.env")"
[ -n "$ca_name" ] && [ -n "$ca_dir" ] || fail "CA_CERT_NAME or its directory is empty in .env.example"
jq -e ".services.portainer.volumes[] | select(.source == \"$ca_dir/$ca_name\"
  and .target == \"/etc/ssl/certs/$ca_name\" and .read_only == true)" <<<"$config" >/dev/null \
  || fail "Portainer does not mount the step-ca root read-only: OAuth login would fail on TLS"

echo "OK"
