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
# - each service mounts its data directory and nothing else;
# - Traefik serves Open WebUI on its host over HTTPS (websecure, stepca) and
#   redirects plain HTTP, with no other router.
# Rendering fails without the bind address, the Open WebUI secret, the domain
# or a data directory.
# Needs Docker Compose and jq. Usage: ./tests/test_stack.sh
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bind=192.0.2.10

fail() { echo "FAIL: $*" >&2; exit 1; }

domain=chat.example.test

required=(OLLAMA_BIND_ADDRESS WEBUI_SECRET_KEY OLLAMA_DOMAIN
  OLLAMA_OLLAMA_DATA_DIR OLLAMA_OPEN_WEBUI_BACKEND_DATA_DIR)

test_env=(OLLAMA_BIND_ADDRESS="$bind" WEBUI_SECRET_KEY=test-secret
  OLLAMA_DOMAIN="$domain" OLLAMA_OLLAMA_DATA_DIR=/srv/test/ollama
  OLLAMA_OPEN_WEBUI_BACKEND_DATA_DIR=/srv/test/webui-backend)

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

# Mounts: the data directory of each service, nothing else.
mounts() { jq -r --arg s "$1" '[.services[$s].volumes // [] | .[] | "\(.source):\(.target)"] | join(" ")' <<<"$config"; }
[ "$(mounts ollama)" = "/srv/test/ollama:/root/.ollama" ] \
  || fail "ollama: unexpected mounts: $(mounts ollama)"
[ "$(mounts open-webui)" = "/srv/test/webui-backend:/app/backend/data" ] \
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

for missing in "${required[@]}"; do
  out="$(render "$missing=" 2>&1 >/dev/null)" \
    && fail "rendering succeeds with an empty $missing"
  grep -q "Set $missing" <<<"$out" \
    || fail "rendering without $missing fails for another reason: $out"
done

echo "OK"
