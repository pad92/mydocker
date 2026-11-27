#!/usr/bin/env bash
# Static checks on the Ollama stack, as Compose renders it with .env.example
# plus test values (nothing is started):
# - the Ollama API, which has no authentication, is published on exactly one
#   port, bound to OLLAMA_BIND_ADDRESS and never to every interface;
# - Open WebUI reaches Ollama by its service name on the internal network,
#   and the legacy OLLAMA_API_* variables are gone (a host-gateway URL would
#   stop answering once the port is bound to the LAN address);
# - Ollama listens on 0.0.0.0:11434 inside the container and gets an integer
#   context length, 8192 by default and overridable;
# - the GPU comes from the device reservation alone: no `runtime: nvidia` and
#   no NVIDIA_* variable (an empty NVIDIA_VISIBLE_DEVICES hides the GPU);
# - both images are pinned to a release, and the tags are overridable;
# - each service mounts its data directory and nothing else, plus the host CA
#   bundle (read-only) for Open WebUI;
# - Open WebUI signs in through Authentik with OpenID Connect: client
#   "open-webui", discovery URL on AUTHENTIK_DOMAIN, the redirect URI that the
#   management blueprint registers, account creation and merge by e-mail, and
#   roles from the "groups" claim (open-webui-admins, open-webui-users); the
#   CA bundle is trusted by each HTTP client it uses;
# - Traefik serves Open WebUI on its host over HTTPS (websecure, stepca) and
#   redirects plain HTTP, with no other router and no middleware on the HTTPS
#   router (no forward auth: it would break API keys, and only the web UI
#   signs in through Authentik);
# - the Ollama service is untouched by the sign-in: no OAuth variable, no
#   Traefik label, still published on the bind address only.
# Rendering fails without the bind address, the Open WebUI secret, the domain,
# a data directory, the Authentik host or the OIDC client secret.
# Needs Docker Compose and jq. Usage: ./tests/test_stack.sh
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bind=192.0.2.10

fail() { echo "FAIL: $*" >&2; exit 1; }

domain=chat.example.test
sso=sso.example.test
ca=/etc/ssl/certs/ca-certificates.crt

required=(OLLAMA_BIND_ADDRESS WEBUI_SECRET_KEY OLLAMA_DOMAIN
  OLLAMA_OLLAMA_DATA_DIR OLLAMA_OPEN_WEBUI_BACKEND_DATA_DIR
  AUTHENTIK_DOMAIN OPEN_WEBUI_OIDC_CLIENT_SECRET)

test_env=(OLLAMA_BIND_ADDRESS="$bind" WEBUI_SECRET_KEY=test-secret
  OLLAMA_DOMAIN="$domain" OLLAMA_OLLAMA_DATA_DIR=/srv/test/ollama
  OLLAMA_OPEN_WEBUI_BACKEND_DATA_DIR=/srv/test/webui-backend
  AUTHENTIK_DOMAIN="$sso" OPEN_WEBUI_OIDC_CLIENT_SECRET=test-oidc-secret)

render() {
  env "${test_env[@]}" "$@" docker compose --project-directory "$stack_dir" \
    --env-file "$stack_dir/.env.example" config --format json
}

config="$(render)"
getenv() { jq -r --arg s "$1" --arg k "$2" '.services[$s].environment[$k] // "<unset>"' <<<"$config"; }
expect() {
  [ "$(getenv "$1" "$2")" = "$3" ] || fail "$1: $2 is '$(getenv "$1" "$2")', expected '$3'"
}

# Published ports: one, on the bind address only.
ports="$(jq -c '[.services[] | .ports // [] | .[]]' <<<"$config")"
[ "$(jq length <<<"$ports")" = 1 ] || fail "expected one published port, got $ports"
[ "$(jq -r '.[0].host_ip // ""' <<<"$ports")" = "$bind" ] \
  || fail "Ollama port is not bound to $bind: $ports"
[ "$(jq -r '.[0] | "\(.target)/\(.published)"' <<<"$ports")" = "11434/11434" ] \
  || fail "unexpected Ollama port mapping: $ports"

expect open-webui OLLAMA_BASE_URL http://ollama:11434
expect open-webui WEBUI_SECRET_KEY test-secret
legacy="$(jq -r '.services["open-webui"].environment | keys[] | select(startswith("OLLAMA_API_"))' <<<"$config")"
[ -z "$legacy" ] || fail "open-webui: legacy variables still set: $legacy"

# Sign-in through Authentik (OpenID Connect).
expect open-webui WEBUI_URL "https://$domain"
expect open-webui OAUTH_PROVIDER_NAME Authentik
expect open-webui OAUTH_CLIENT_ID open-webui
expect open-webui OAUTH_CLIENT_SECRET test-oidc-secret
expect open-webui OPENID_PROVIDER_URL \
  "https://$sso/application/o/open-webui/.well-known/openid-configuration"
# Must match the redirect URI of the management blueprint, built from
# OLLAMA_HOST_LOCAL there.
expect open-webui OPENID_REDIRECT_URI "https://$domain/oauth/oidc/login/callback"
expect open-webui ENABLE_OAUTH_SIGNUP true
expect open-webui OAUTH_MERGE_ACCOUNTS_BY_EMAIL true
expect open-webui ENABLE_OAUTH_ROLE_MANAGEMENT true
expect open-webui OAUTH_ROLES_CLAIM groups
expect open-webui OAUTH_ALLOWED_ROLES open-webui-users
expect open-webui OAUTH_ADMIN_ROLES open-webui-admins
for v in SSL_CERT_FILE AIOHTTP_CLIENT_SSL_CERT_FILE REQUESTS_CA_BUNDLE; do
  expect open-webui "$v" "$ca"
done
# Not set: the OAuth settings would otherwise be saved in the database and
# win over the Compose file after the first start.
expect open-webui ENABLE_OAUTH_PERSISTENT_CONFIG "<unset>"
oauth_on_ollama="$(jq -r '.services.ollama.environment // {} | keys[]
  | select(test("OAUTH|OPENID|WEBUI"))' <<<"$config")"
[ -z "$oauth_on_ollama" ] || fail "ollama: sign-in variables set: $oauth_on_ollama"
[ "$(jq -r '.services.ollama.labels // {} | length' <<<"$config")" = 0 ] \
  || fail "ollama: has labels, the API must not go through Traefik"

expect ollama OLLAMA_HOST 0.0.0.0:11434
expect ollama OLLAMA_CONTEXT_LENGTH 8192
[ "$(getenv ollama OLLAMA_KEEP_ALIVE)" != "" ] || fail "ollama: OLLAMA_KEEP_ALIVE is empty"

overridden="$(render OLLAMA_CONTEXT_LENGTH=16384 \
  | jq -r '.services.ollama.environment.OLLAMA_CONTEXT_LENGTH')"
[ "$overridden" = 16384 ] || fail "OLLAMA_CONTEXT_LENGTH override ignored: $overridden"

# GPU: the device reservation only.
[ "$(jq -r '.services.ollama.runtime // "<unset>"' <<<"$config")" = "<unset>" ] \
  || fail "ollama: runtime is set, the device reservation is enough"
[ "$(jq -c '[.services.ollama.deploy.resources.reservations.devices[]
    | select(.driver == "nvidia" and (.capabilities | index("gpu")))] | length' \
    <<<"$config")" = 1 ] || fail "ollama: no NVIDIA GPU reservation"
nvidia="$(jq -r '.services | to_entries[] | .key as $s | .value.environment // {}
  | keys[] | select(startswith("NVIDIA_")) | "\($s):\(.)"' <<<"$config")"
[ -z "$nvidia" ] || fail "NVIDIA_* variables set, the image provides them: $nvidia"

# Images: pinned by default, overridable.
image() { jq -r --arg s "$2" '.services[$s].image' <<<"$1"; }
for s in ollama open-webui; do
  img="$(image "$config" "$s")"
  case "$img" in
    *:latest|*:main|*:dev|*:ollama|*:cuda) fail "$s: floating tag in $img" ;;
    *:v[0-9]*.[0-9]*.[0-9]*|*:[0-9]*.[0-9]*.[0-9]*) ;;
    *) fail "$s: image not pinned to a release: $img" ;;
  esac
done
# From 0.30.0 Ollama needs NVIDIA driver 570 and silently runs on the CPU
# with the host driver 550: the default must stay on the last tag tested on
# the GPU until the driver is upgraded (see README, GPU and versions).
[ "$(image "$config" ollama)" = docker.io/ollama/ollama:0.24.0 ] \
  || fail "ollama: default image is $(image "$config" ollama), expected the 0.24.0 tested on driver 550"
pinned="$(render OLLAMA_VERSION=9.9.9 OPEN_WEBUI_VERSION=v9.9.9)"
[ "$(image "$pinned" ollama)" = docker.io/ollama/ollama:9.9.9 ] \
  || fail "OLLAMA_VERSION override ignored: $(image "$pinned" ollama)"
[ "$(image "$pinned" open-webui)" = ghcr.io/open-webui/open-webui:v9.9.9 ] \
  || fail "OPEN_WEBUI_VERSION override ignored: $(image "$pinned" open-webui)"

# Mounts: the data directory of each service, plus the CA bundle (read-only)
# for Open WebUI.
mounts() { jq -r --arg s "$1" '[.services[$s].volumes // [] | .[] | "\(.source):\(.target):\(.read_only // false)"] | join(" ")' <<<"$config"; }
[ "$(mounts ollama)" = "/srv/test/ollama:/root/.ollama:false" ] \
  || fail "ollama: unexpected mounts: $(mounts ollama)"
[ "$(mounts open-webui)" = "/srv/test/webui-backend:/app/backend/data:false $ca:$ca:true" ] \
  || fail "open-webui: unexpected mounts: $(mounts open-webui)"
[ "$(jq -r '.services["open-webui"].environment.MODEL_DOWNLOAD_DIR // "<unset>"' <<<"$config")" = "<unset>" ] \
  || fail "open-webui: MODEL_DOWNLOAD_DIR is set, Open WebUI does not read it"

# Traefik: HTTPS router on the host, HTTP redirect, no other router.
label() { jq -r --arg k "$1" '.services["open-webui"].labels[$k] // "<unset>"' <<<"$config"; }
expect_label() {
  [ "$(label "$1")" = "$2" ] || fail "label $1 is '$(label "$1")', expected '$2'"
}
r=traefik.http.routers
expect_label traefik.enable true
expect_label traefik.docker.network traefik_gateway
expect_label traefik.http.services.open-webui.loadbalancer.server.port 8080
expect_label "$r.open-webui.rule" "Host(\`$domain\`)"
expect_label "$r.open-webui.entrypoints" websecure
expect_label "$r.open-webui.tls" true
expect_label "$r.open-webui.tls.certresolver" stepca
expect_label "$r.open-webui_http.rule" "Host(\`$domain\`)"
expect_label "$r.open-webui_http.entrypoints" web
expect_label "$r.open-webui_http.middlewares" redirect-https
expect_label traefik.http.middlewares.redirect-https.redirectscheme.scheme https
routers="$(jq -r '[.services[] | .labels // {} | keys[]
  | select(startswith("traefik.http.routers.")) | split(".")[3]] | unique | join(" ")' <<<"$config")"
[ "$routers" = "open-webui open-webui_http" ] || fail "unexpected routers: $routers"
# No forward auth: Open WebUI signs in through OIDC itself.
expect_label "$r.open-webui.middlewares" "<unset>"
fwd="$(jq -r '[.services[] | .labels // {} | to_entries[]
  | select(.value | test("authentik|forwardauth"; "i")) | .key] | join(" ")' <<<"$config")"
[ -z "$fwd" ] || fail "forward auth configured: $fwd"

for missing in "${required[@]}"; do
  out="$(render "$missing=" 2>&1 >/dev/null)" \
    && fail "rendering succeeds with an empty $missing"
  grep -q "Set $missing" <<<"$out" \
    || fail "rendering without $missing fails for another reason: $out"
done

echo "OK"
