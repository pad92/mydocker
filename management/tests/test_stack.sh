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
# - Uptime Kuma and the Beszel hub run on ns01: Traefik gets their host names
#   and upstream URLs, and the routes of traefik_dynamic.toml.example keep
#   Uptime Kuma behind forward auth, except its /api/push/ path;
# - the Docker socket proxy is read-only (no POST, socket mounted read-only,
#   no published port) and its router only accepts the allowed source IPs;
# - Portainer is behind forward auth, with no bypass router, and mounts the
#   step-ca root read-only (its OAuth login calls Authentik over HTTPS);
# - the Traefik dashboard router (/traefik and /api) is behind forward auth;
#   only that router: the other apps on the same host are not affected;
# - the VictoriaLogs, VictoriaMetrics, Victoria Grafana, Forgejo, Gramps Web,
#   Immich, Donetick and Open WebUI (ollama) host names reach
#   the blueprints (the victoria routers are checked in
#   victoria/tests/test_stack.sh).
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
  -e "s|^BESZEL_HOST_LOCAL=.*|BESZEL_HOST_LOCAL=beszel.example.test|" \
  -e "s|^BESZEL_UPSTREAM_URL=.*|BESZEL_UPSTREAM_URL=http://192.0.2.1:8090|" \
  -e "s|^UPTIME_UPSTREAM_URL=.*|UPTIME_UPSTREAM_URL=http://192.0.2.1:3001|" \
  -e "s|^DOCKER_PROXY_ALLOWED_IPS=.*|DOCKER_PROXY_ALLOWED_IPS=192.0.2.1/32|" \
  -e "s|^DOCKER_PROXY_HOST_LOCAL=.*|DOCKER_PROXY_HOST_LOCAL=docker.example.test|" \
  -e "s|^PROXMOX_HOST_LOCAL=.*|PROXMOX_HOST_LOCAL=pve.home.test|" \
  -e "s|^UPTIME_HOST_LOCAL=.*|UPTIME_HOST_LOCAL=uptime.example.test|" \
  -e "s|^NG_HOST_LOCAL=.*|NG_HOST_LOCAL=media.home.test|" \
  -e "s|^PORTAINER_HOST_LOCAL=.*|PORTAINER_HOST_LOCAL=portainer.home.test|" \
  -e "s|^TRAEFIK_HOST_LOCAL=.*|TRAEFIK_HOST_LOCAL=proxy.example.test|" \
  -e "s|^VICTORIA_LOGS_HOST_LOCAL=.*|VICTORIA_LOGS_HOST_LOCAL=logs.home.test|" \
  -e "s|^VICTORIA_METRICS_HOST_LOCAL=.*|VICTORIA_METRICS_HOST_LOCAL=metrics.home.test|" \
  -e "s|^VICTORIA_GRAFANA_HOST_LOCAL=.*|VICTORIA_GRAFANA_HOST_LOCAL=grafana.home.test|" \
  -e "s|^ALERTMANAGER_HOST_LOCAL=.*|ALERTMANAGER_HOST_LOCAL=alertmanager.example.test|" \
  -e "s|^FORGEJO_HOST_LOCAL=.*|FORGEJO_HOST_LOCAL=git.home.test|" \
  -e "s|^GRAMPSWEB_HOST_LOCAL=.*|GRAMPSWEB_HOST_LOCAL=genealogy.home.test|" \
  -e "s|^IMMICH_HOST_LOCAL=.*|IMMICH_HOST_LOCAL=photos.home.test|" \
  -e "s|^DONETICK_HOST_LOCAL=.*|DONETICK_HOST_LOCAL=todo.example.test|" \
  -e "s|^OLLAMA_HOST_LOCAL=.*|OLLAMA_HOST_LOCAL=ollama.example.test|" \
  -e "s|^UNIFI_HOST_LOCAL=.*|UNIFI_HOST_LOCAL=unifi.home.test|" \
  -e "s|^NAS_HOST_LOCAL=.*|NAS_HOST_LOCAL=nas.home.test|" \
  -e "s|^SWITCH_HOST_LOCAL=.*|SWITCH_HOST_LOCAL=192.0.2.30|" \
  -e "s|^PROXMOX_UPSTREAM_URL=.*|PROXMOX_UPSTREAM_URL=https://192.0.2.10:8006|" \
  "$stack_dir/.env.example" > "$work_dir/test.env"

for var in AUTHENTIK_SECRET_KEY AUTHENTIK_PG_PASS CA_CERT_NAME MANAGEMENT_SHARE_CA_CERTIFICATES_DATA_DIR AUTHENTIK_HOST_LOCAL UPTIME_HOST_LOCAL NG_HOST_LOCAL PORTAINER_HOST_LOCAL TRAEFIK_HOST_LOCAL VICTORIA_LOGS_HOST_LOCAL VICTORIA_METRICS_HOST_LOCAL VICTORIA_GRAFANA_HOST_LOCAL ALERTMANAGER_HOST_LOCAL FORGEJO_HOST_LOCAL GRAMPSWEB_HOST_LOCAL IMMICH_HOST_LOCAL DONETICK_HOST_LOCAL OLLAMA_HOST_LOCAL UNIFI_HOST_LOCAL NAS_HOST_LOCAL SWITCH_HOST_LOCAL MANAGEMENT_AUTHENTIK_DATA_DIR UPTIME_UPSTREAM_URL BESZEL_HOST_LOCAL BESZEL_UPSTREAM_URL DOCKER_PROXY_HOST_LOCAL DOCKER_PROXY_ALLOWED_IPS; do
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
[ "$(jq -r "$worker.environment.BLUEPRINT_UPTIME_HOST" <<<"$config")" = uptime.example.test ] \
  || fail "BLUEPRINT_UPTIME_HOST is not UPTIME_HOST_LOCAL"
[ "$(jq -r "$worker.environment.BLUEPRINT_NG_HOST" <<<"$config")" = media.home.test ] \
  || fail "BLUEPRINT_NG_HOST is not NG_HOST_LOCAL"
[ "$(jq -r "$worker.environment.BLUEPRINT_PORTAINER_HOST" <<<"$config")" = portainer.home.test ] \
  || fail "BLUEPRINT_PORTAINER_HOST is not PORTAINER_HOST_LOCAL"
[ "$(jq -r "$worker.environment.BLUEPRINT_TRAEFIK_HOST" <<<"$config")" = proxy.example.test ] \
  || fail "BLUEPRINT_TRAEFIK_HOST is not TRAEFIK_HOST_LOCAL"
[ "$(jq -r "$worker.environment.BLUEPRINT_VICTORIA_LOGS_HOST" <<<"$config")" = logs.home.test ] \
  || fail "BLUEPRINT_VICTORIA_LOGS_HOST is not VICTORIA_LOGS_HOST_LOCAL"
[ "$(jq -r "$worker.environment.BLUEPRINT_VICTORIA_METRICS_HOST" <<<"$config")" = metrics.home.test ] \
  || fail "BLUEPRINT_VICTORIA_METRICS_HOST is not VICTORIA_METRICS_HOST_LOCAL"
[ "$(jq -r "$worker.environment.BLUEPRINT_VICTORIA_GRAFANA_HOST" <<<"$config")" = grafana.home.test ] \
  || fail "BLUEPRINT_VICTORIA_GRAFANA_HOST is not VICTORIA_GRAFANA_HOST_LOCAL"
[ "$(jq -r "$worker.environment.BLUEPRINT_ALERTMANAGER_HOST" <<<"$config")" = alertmanager.example.test ] \
  || fail "BLUEPRINT_ALERTMANAGER_HOST is not ALERTMANAGER_HOST_LOCAL"
[ "$(jq -r "$worker.environment.BLUEPRINT_FORGEJO_HOST" <<<"$config")" = git.home.test ] \
  || fail "BLUEPRINT_FORGEJO_HOST is not FORGEJO_HOST_LOCAL"
[ "$(jq -r "$worker.environment.BLUEPRINT_GRAMPSWEB_HOST" <<<"$config")" = genealogy.home.test ] \
  || fail "BLUEPRINT_GRAMPSWEB_HOST is not GRAMPSWEB_HOST_LOCAL"
[ "$(jq -r "$worker.environment.BLUEPRINT_IMMICH_HOST" <<<"$config")" = photos.home.test ] \
  || fail "BLUEPRINT_IMMICH_HOST is not IMMICH_HOST_LOCAL"
[ "$(jq -r "$worker.environment.BLUEPRINT_DONETICK_HOST" <<<"$config")" = todo.example.test ] \
  || fail "BLUEPRINT_DONETICK_HOST is not DONETICK_HOST_LOCAL"
[ "$(jq -r "$worker.environment.BLUEPRINT_OLLAMA_HOST" <<<"$config")" = ollama.example.test ] \
  || fail "BLUEPRINT_OLLAMA_HOST is not OLLAMA_HOST_LOCAL"
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

[ "$(jq -r '.services["uptime-kuma"] // "none"' <<<"$config")" = none ] \
  || fail "Uptime Kuma is still in this stack: it runs on ns01 (uptime-kuma/)"
for pair in UPTIME_HOST_LOCAL=uptime.example.test UPTIME_UPSTREAM_URL=http://192.0.2.1:3001 \
  BESZEL_HOST_LOCAL=beszel.example.test BESZEL_UPSTREAM_URL=http://192.0.2.1:8090; do
  jq -e --arg p "$pair" '.services.traefik.environment | to_entries[]
    | select("\(.key)=\(.value)" == $p)' <<<"$config" >/dev/null \
    || fail "Traefik does not get $pair for the ns01 routes"
done
# Routes towards ns01 (file provider). Go templates stay as plain strings.
python3 - "$stack_dir/traefik_dynamic.toml.example" <<'PY' || fail "ns01 routes in traefik_dynamic.toml.example"
import sys, tomllib
r = tomllib.load(open(sys.argv[1], "rb"))["http"]["routers"]
host = '{{ env "UPTIME_HOST_LOCAL" }}'
assert r["uptime"]["middlewares"] == ["authentik@docker"], "uptime router not behind forward auth"
assert r["uptime_push"]["rule"] == f"Host(`{host}`) && PathPrefix(`/api/push/`)", "push rule"
assert "middlewares" not in r["uptime_push"], "push router has a middleware"
for name in ("uptime", "uptime_push", "uptime_http"):
    assert r[name]["service"] == "uptime-svc", name
for name in ("beszel", "beszel_http"):
    assert r[name]["service"] == "beszel-svc", name
PY

proxy='.services["docker-socket-proxy"]'
jq -e "$proxy.environment.POST == \"0\" and $proxy.environment.CONTAINERS == \"1\"" <<<"$config" >/dev/null \
  || fail "Docker socket proxy is not read-only on the containers endpoints"
jq -e "$proxy.volumes[] | select(.source == \"/var/run/docker.sock\" and .read_only == true)" <<<"$config" >/dev/null \
  || fail "Docker socket proxy does not mount the socket read-only"
[ "$(jq -r "$proxy.ports // [] | length" <<<"$config")" = 0 ] \
  || fail "Docker socket proxy publishes a port: it must stay behind Traefik"
[ "$(jq -r "$proxy.labels[\"traefik.http.routers.docker_proxy.middlewares\"]" <<<"$config")" = docker_proxy_allow ] \
  || fail "Docker proxy router is not limited by the IP allow list"
[ "$(jq -r "$proxy.labels[\"traefik.http.middlewares.docker_proxy_allow.ipallowlist.sourcerange\"]" <<<"$config")" = 192.0.2.1/32 ] \
  || fail "Docker proxy allow list is not DOCKER_PROXY_ALLOWED_IPS"

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
traefik='.services.traefik.labels'
[ "$(jq -r "$traefik[\"traefik.http.routers.traefik.middlewares\"]" <<<"$config")" = \
  authentik@docker,traefik_strip ] \
  || fail "Traefik dashboard router is not behind forward auth (first middleware)"
[ "$(jq -r "$traefik[\"traefik.http.routers.traefik.service\"]" <<<"$config")" = api@internal ] \
  || fail "Traefik dashboard router does not serve api@internal"
# Every router of the traefik service on that host other than the HTTP
# redirect must carry the middleware: a bypass would expose the dashboard and
# the API (all routers, services and middlewares).
traefik_routers="$(jq -r "$traefik | to_entries[] | select(.key | test(\"^traefik.http.routers.[^.]+.rule$\"))
  | select(.value | contains(\"proxy.example.test\")) | .key | split(\".\")[3]" <<<"$config")"
grep -qx traefik <<<"$traefik_routers" || fail "no Traefik dashboard router on TRAEFIK_HOST_LOCAL"
while read -r router; do
  [ "$router" = traefik_http ] && continue
  jq -r "$traefik[\"traefik.http.routers.$router.middlewares\"] // \"\"" <<<"$config" \
    | grep -q '^authentik@docker' || fail "Traefik router $router bypasses forward auth"
done <<<"$traefik_routers"
[ "$(jq -r "$traefik[\"traefik.http.routers.traefik_http.middlewares\"]" <<<"$config")" = redirect-https ] \
  || fail "Traefik HTTP router does more than redirect to HTTPS"

ca_name="$(sed -n 's/^CA_CERT_NAME=//p' "$work_dir/test.env")"
ca_dir="$(sed -n 's/^MANAGEMENT_SHARE_CA_CERTIFICATES_DATA_DIR=//p' "$work_dir/test.env")"
[ -n "$ca_name" ] && [ -n "$ca_dir" ] || fail "CA_CERT_NAME or its directory is empty in .env.example"
jq -e ".services.portainer.volumes[] | select(.source == \"$ca_dir/$ca_name\"
  and .target == \"/etc/ssl/certs/$ca_name\" and .read_only == true)" <<<"$config" >/dev/null \
  || fail "Portainer does not mount the step-ca root read-only: OAuth login would fail on TLS"

echo "OK"
