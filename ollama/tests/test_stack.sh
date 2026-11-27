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
# - the GPU stays visible when the NVIDIA_* variables are left empty.
# Rendering fails without the bind address, the Open WebUI secret, the domain
# or a data directory.
# Needs Docker Compose and jq. Usage: ./tests/test_stack.sh
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bind=192.0.2.10

fail() { echo "FAIL: $*" >&2; exit 1; }

required=(OLLAMA_BIND_ADDRESS WEBUI_SECRET_KEY OLLAMA_DOMAIN
  OLLAMA_MODELS_DATA_DIR OLLAMA_OLLAMA_DATA_DIR
  OLLAMA_OPEN_WEBUI_DATA_DIR OLLAMA_OPEN_WEBUI_BACKEND_DATA_DIR)

test_env=(OLLAMA_BIND_ADDRESS="$bind" WEBUI_SECRET_KEY=test-secret
  OLLAMA_DOMAIN=chat.example.test
  OLLAMA_MODELS_DATA_DIR=/srv/test/models OLLAMA_OLLAMA_DATA_DIR=/srv/test/ollama
  OLLAMA_OPEN_WEBUI_DATA_DIR=/srv/test/webui
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
expect ollama NVIDIA_VISIBLE_DEVICES all
[ "$(getenv ollama OLLAMA_KEEP_ALIVE)" != "" ] || fail "ollama: OLLAMA_KEEP_ALIVE is empty"

overridden="$(render OLLAMA_CONTEXT_LENGTH=16384 \
  | jq -r '.services.ollama.environment.OLLAMA_CONTEXT_LENGTH')"
[ "$overridden" = 16384 ] || fail "OLLAMA_CONTEXT_LENGTH override ignored: $overridden"

for missing in "${required[@]}"; do
  out="$(render "$missing=" 2>&1 >/dev/null)" \
    && fail "rendering succeeds with an empty $missing"
  grep -q "Set $missing" <<<"$out" \
    || fail "rendering without $missing fails for another reason: $out"
done

echo "OK"
