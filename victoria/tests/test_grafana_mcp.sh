#!/usr/bin/env bash
# Run test for grafana-mcp, on the config as Compose renders it with
# .env.example. The real image runs with its rendered entrypoint, command and
# environment on a throwaway internal network; only the two tokens are set to
# test values. A Python client on the same network sends the requests that
# Traefik would forward, with the Grafana host as Host header.
#
# Start check (mcp-grafana serves without any client authentication when its
# server token is empty): with an empty server token, a 31 character one, or
# an empty service account token, the container must stay up, log why, and
# leave port 8000 closed.
#
# With valid tokens: POST /mcp without a bearer token or with a wrong one
# must get 401, the right one 200 on initialize; another Host or any Origin
# header must get 403; tools/list must hold the read tools and none of the
# write tools that --disable-write removes.
# Not covered: Grafana itself (no Grafana runs, so no tool is called), the
# Traefik router (see test_stack.sh) and the service account permissions.
#
# Needs Docker, Docker Compose 2.23+ and jq; no published port, no Internet.
# Usage: ./tests/test_grafana_mcp.sh
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="$stack_dir/.env.example"
client_image="${CLIENT_IMAGE:-python:3.14-alpine}"

suffix="$$-$RANDOM"
network="victoria-mcp-test-$suffix"
mcp_name="grafana-mcp-test-$suffix"
work_dir="$(mktemp -d)"
server_token="test-server-token-$(printf '%040d' 0)"

cleanup() {
  docker rm -f "$mcp_name" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  docker logs "$mcp_name" 2>&1 | tail -n 20 >&2 || true
  exit 1
}

# --- Rendering: what the grafana-mcp container really receives.
config="$(PUID="${PUID:-1000}" PGID="${PGID:-1000}" docker compose \
  --project-directory "$stack_dir" --env-file "$env_file" config --format json)"
service="$(jq -c '.services."grafana-mcp"' <<<"$config")"
image="$(jq -r '.image' <<<"$service")"
grafana_host="$(jq -r '.environment.MCP_ALLOWED_HOST' <<<"$service")"
mapfile -t entrypoint < <(jq -r '.entrypoint[]' <<<"$service")
# docker compose config keeps the $$ escape; the container gets a single $.
script="$(jq -r '.command[0]' <<<"$service" | sed 's/\$\$/$/g')"
jq -r '.environment | to_entries[]
  | select(.key != "GRAFANA_SERVICE_ACCOUNT_TOKEN" and .key != "MCP_GRAFANA_SERVER_TOKEN")
  | "\(.key)=\(.value)"' <<<"$service" >"$work_dir/env"

docker network create --internal "$network" >/dev/null

# start_mcp <server token> <service account token>
start_mcp() {
  docker rm -f "$mcp_name" >/dev/null 2>&1 || true
  docker run -d --name "$mcp_name" --network "$network" --network-alias grafana-mcp \
    --env-file "$work_dir/env" -e "MCP_GRAFANA_SERVER_TOKEN=$1" \
    -e "GRAFANA_SERVICE_ACCOUNT_TOKEN=$2" \
    --entrypoint "${entrypoint[0]}" "$image" "${entrypoint[@]:1}" "$script" >/dev/null
}

# client <python>: runs the code with the helpers below on the test network.
client() {
  docker run --rm -i --network "$network" -e "TOKEN=$server_token" \
    -e "HOST=$grafana_host" "$client_image" python - <<EOF
import json, os, socket, sys, time, urllib.error, urllib.request

def post(body, token=None, host=None, origin=None):
    req = urllib.request.Request("http://grafana-mcp:8000/mcp", method="POST",
                                 data=json.dumps(body).encode())
    req.add_header("Host", host or os.environ["HOST"])
    req.add_header("Content-Type", "application/json")
    req.add_header("Accept", "application/json, text/event-stream")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    if origin:
        req.add_header("Origin", origin)
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as err:
        return err.code, err.read()

def wait_open(seconds):
    deadline = time.time() + seconds
    while time.time() < deadline:
        try:
            socket.create_connection(("grafana-mcp", 8000), timeout=1).close()
            return True
        except OSError:
            time.sleep(0.5)
    return False

def check(cond, msg):
    if not cond:
        print(msg, file=sys.stderr)
        sys.exit(1)

$1
EOF
}

# --- Start check: no listener without both tokens.
for case in "empty server token||sa-token" \
            "31 character server token|$(printf '%031d' 0)|sa-token" \
            "empty service account token|$server_token|"; do
  IFS='|' read -r what token sa <<<"$case"
  start_mcp "$token" "$sa"
  client 'check(not wait_open(5), "port 8000 is open")' \
    || fail "$what: mcp-grafana started (it would serve without authentication)"
  [ "$(docker inspect -f '{{.State.Running}}' "$mcp_name")" = true ] \
    || fail "$what: the container exited instead of waiting (restart loop)"
  docker logs "$mcp_name" 2>&1 | grep -q 'is missing, see the README' \
    || fail "$what: the container does not log why it waits"
done

# --- Valid tokens: authentication, Host and Origin checks, read-only tools.
start_mcp "$server_token" sa-token
client '
check(wait_open(20), "port 8000 is not open")
init = {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2025-06-18", "capabilities": {},
    "clientInfo": {"name": "test", "version": "1"}}}
status, _ = post(init)
check(status == 401, f"no bearer token: HTTP {status}, expected 401")
status, _ = post(init, token="wrong-" + os.environ["TOKEN"])
check(status == 401, f"wrong bearer token: HTTP {status}, expected 401")
status, body = post(init, token=os.environ["TOKEN"])
check(status == 200 and b"\"result\"" in body, f"right bearer token: HTTP {status} {body[:200]}")
status, _ = post(init, token=os.environ["TOKEN"], host="other.example.com")
check(status == 403, f"other Host: HTTP {status}, expected 403")
status, _ = post(init, token=os.environ["TOKEN"], origin="https://" + os.environ["HOST"])
check(status == 403, f"Origin header: HTTP {status}, expected 403")
status, body = post({"jsonrpc": "2.0", "id": 2, "method": "tools/list"}, token=os.environ["TOKEN"])
check(status == 200, f"tools/list: HTTP {status}")
tools = {t["name"] for t in json.loads(body)["result"]["tools"]}
check({"search_dashboards", "get_dashboard_by_uid"} <= tools, f"read tools missing: {sorted(tools)}")
write = {"update_dashboard", "create_datasource", "update_datasource", "install_plugin",
         "alerting_rules_write", "create_folder", "create_annotation", "delete_snapshot"}
check(not (write & tools), f"write tools exposed: {sorted(write & tools)}")
' || fail "grafana-mcp with valid tokens"

echo OK
