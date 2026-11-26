#!/usr/bin/env bash
# Grafana test, on the configs and environment as Compose renders them with
# .env.example.
#
# On a throwaway internal network: VictoriaLogs, VictoriaMetrics and Grafana
# with the rendered environment, provisioning files and dashboards. Checks:
# - without the X-authentik-username header the API answers 401 (no anonymous
#   access), Basic auth and POST /login with the default admin/admin are
#   refused;
# - with the header a new user is created with the Viewer role and sees both
#   provisioned dashboards;
# - the VictoriaLogs plugin is loaded at the version pinned in
#   GF_PLUGINS_PREINSTALL_SYNC;
# - every VictoriaLogs target of both dashboards, sent as the viewer to
#   /api/ds/query, answers 200 without error and returns data from parsed
#   Proxmox and Authentik records ingested before;
# - every VictoriaMetrics target answers 200 without error (the expression
#   parses; there is no Proxmox metric in the test, so no data is expected).
# Template variables are replaced by one value present in the test data, as
# Grafana does before sending a query; the "All" choice is not tested.
#
# One change in the test only: Grafana cannot download the plugin on an
# internal network, so GF_PLUGINS_PREINSTALL_DISABLED=true and the plugin
# comes read-only from GRAFANA_PLUGIN_DIR, a directory holding
# victoriametrics-logs-datasource/ at the pinned version (for example the
# plugins/ directory of a Grafana that installed it once). The test refuses
# another version.
# Not covered: the rendering in a browser, the Authentik outpost in front of
# Grafana, the real Proxmox metric names (see the README).
#
# Needs Docker, Docker Compose 2.23+, jq and python3; no published port, no
# Internet. Usage: GRAFANA_PLUGIN_DIR=/path/to/plugins ./tests/test_dashboards.sh
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="$stack_dir/.env.example"
version() { sed -n "s/^$1=//p" "$env_file"; }
logs_image="victoriametrics/victoria-logs:$(version VICTORIA_LOGS_VERSION)"
metrics_image="victoriametrics/victoria-metrics:$(version VICTORIA_METRICS_VERSION)"
grafana_image="grafana/grafana:$(version GRAFANA_VERSION)"
client_image="${CLIENT_IMAGE:-busybox:1.37}"
plugin_id="victoriametrics-logs-datasource"
viewer="test-viewer"

[[ -n "${GRAFANA_PLUGIN_DIR:-}" ]] || { echo "FAIL: set GRAFANA_PLUGIN_DIR (see the header of this script)" >&2; exit 1; }
plugin_dir="$(cd "$GRAFANA_PLUGIN_DIR" && pwd)"

suffix="$$-$RANDOM"
network="victoria-dashboards-test-$suffix"
logs_name="victorialogs-test-$suffix"
metrics_name="victoriametrics-test-$suffix"
grafana_name="grafana-test-$suffix"
work_dir="$(mktemp -d)"

cleanup() {
  docker rm -f "$grafana_name" "$metrics_name" "$logs_name" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  if docker inspect "$grafana_name" >/dev/null 2>&1; then
    echo "--- $grafana_name logs" >&2
    docker logs "$grafana_name" 2>&1 | tail -n 20 >&2 || true
  fi
  exit 1
}

# --- Rendering: the environment and files the Grafana container receives.
PUID="${PUID:-1000}" PGID="${PGID:-1000}" docker compose \
  --project-directory "$stack_dir" --env-file "$env_file" \
  config --format json > "$work_dir/compose.json"
jq -e '.services.grafana' "$work_dir/compose.json" >/dev/null || fail "no grafana service"
jq -r '.services.grafana.environment | to_entries[] | "\(.key)=\(.value)"' \
  "$work_dir/compose.json" > "$work_dir/grafana.env"
echo "GF_PLUGINS_PREINSTALL_DISABLED=true" >> "$work_dir/grafana.env"
grafana_user="$(jq -r '.services.grafana.user // empty' "$work_dir/compose.json")"

mounts=()
mkdir -p "$work_dir/configs"
while IFS=$'\t' read -r source target; do
  jq -er --arg c "$source" '.configs[$c].content | gsub("\\$\\$"; "$")' \
    "$work_dir/compose.json" > "$work_dir/configs/$source"
  mounts+=(-v "$work_dir/configs/$source:$target:ro")
done < <(jq -r '.services.grafana.configs[] | [.source, .target] | @tsv' "$work_dir/compose.json")
[[ ${#mounts[@]} -eq 8 ]] || fail "expected 4 Grafana configs, got $((${#mounts[@]} / 2))"

pinned="$(jq -r '.services.grafana.environment.GF_PLUGINS_PREINSTALL_SYNC' "$work_dir/compose.json")"
[[ "$pinned" == "$plugin_id@"* ]] || fail "GF_PLUGINS_PREINSTALL_SYNC is '$pinned', expected $plugin_id@<version>"
pinned_version="${pinned#"$plugin_id@"}"
local_version="$(jq -r '.info.version' "$plugin_dir/$plugin_id/plugin.json" 2>/dev/null)" \
  || fail "no $plugin_id/plugin.json in $plugin_dir"
[[ "$local_version" == "$pinned_version" ]] \
  || fail "plugin in GRAFANA_PLUGIN_DIR is $local_version, the stack pins $pinned_version"

# --- Test data and query bodies.
mkdir -p "$work_dir/out" "$work_dir/bodies"
python3 -I - "$work_dir" <<'PY'
import datetime, json, os, sys

work = sys.argv[1]
now = datetime.datetime.now(datetime.timezone.utc)

def at(minutes):
    return (now - datetime.timedelta(minutes=minutes)).strftime("%Y-%m-%dT%H:%M:%SZ")

# Records as Vector stores them after parsing (fields from proxmox_test.yaml
# and authentik_test.yaml), a few minutes old.
proxmox = [
    {"pve_kind": "task", "pve_task_event": "start", "pve_task_type": "vzdump",
     "pve_level": "info", "pve_component": "pvedaemon"},
    {"pve_kind": "task", "pve_task_event": "end", "pve_task_type": "qmstart",
     "pve_task_failed": "true", "pve_task_status": "error", "pve_vmid": "101",
     "pve_user": "root@pam", "pve_level": "error", "pve_component": "pvedaemon"},
    {"pve_kind": "backup", "pve_backup_event": "vm_ok", "pve_vmid": "101",
     "pve_duration_s": "42", "pve_level": "info"},
    {"pve_kind": "backup", "pve_backup_event": "vm_failed", "pve_vmid": "102",
     "pve_level": "error"},
    {"pve_kind": "auth", "pve_auth_result": "failure", "pve_user": "root@pam",
     "pve_client_ip": "10.0.0.9", "pve_level": "warning", "pve_component": "pvedaemon"},
]
authentik = [
    {"ak_kind": "forward_auth", "ak_app_host": "app.home.lan", "app_status": "200",
     "ak_runtime_ms": "13", "ak_level": "info", "ak_component": "server"},
    {"ak_kind": "log", "ak_level": "error", "ak_component": "worker", "app_event": "boom"},
    {"ak_kind": "event", "ak_action": "login", "ak_user": "alice",
     "ak_client_ip": "10.0.0.2", "ak_level": "info", "ak_component": "events"},
    {"ak_kind": "event", "ak_action": "login_failed", "ak_user": "bob",
     "ak_client_ip": "10.0.0.3", "ak_level": "warning", "ak_component": "events"},
]
records = [{"log_stream": "proxmox", "_msg": "pve", **r} for r in proxmox]
records += [{"log_stream": "authentik", "_msg": "ak", **r} for r in authentik]
with open(f"{work}/records.jsonl", "w") as f:
    for i, r in enumerate(records):
        f.write(json.dumps({"_time": at(i % 5 + 1), **r}) + "\n")
with open(f"{work}/records.count", "w") as f:
    f.write(str(len(records)))

# One /api/ds/query body per target, variables replaced by a value present in
# the records above.
values = {"application": "app.home.lan", "composant": "worker"}
index = []
for name in ("grafana_dashboard_authentik", "grafana_dashboard_proxmox"):
    dash = json.load(open(f"{work}/configs/{name}"))
    for panel in dash["panels"]:
        for target in panel.get("targets", []):
            query = dict(target)
            expr = query["expr"]
            for var, value in values.items():
                expr = expr.replace(f"${var}", json.dumps(value))
            assert "$" not in expr, f'{dash["uid"]} / {panel["title"]}: {expr}'
            query["expr"] = expr
            n = len(index) + 1
            json.dump({"from": "now-24h", "to": "now", "queries": [query]},
                      open(f"{work}/bodies/q{n:03d}.json", "w"))
            index.append({"file": f"q{n:03d}", "dashboard": dash["uid"],
                          "panel": panel["title"], "refId": query.get("refId", "A"),
                          "datasource": query["datasource"]["uid"]})
json.dump(index, open(f"{work}/bodies/index.json", "w"))
PY
chmod -R a+rX "$work_dir"
chmod a+rwx "$work_dir/out"

# --- Containers.
docker network create --internal "$network" >/dev/null
docker run -d --name "$logs_name" --network "$network" --network-alias victorialogs \
  --tmpfs /data "$logs_image" -storageDataPath=/data -httpListenAddr=:9428 >/dev/null
docker run -d --name "$metrics_name" --network "$network" --network-alias victoriametrics \
  --tmpfs /data "$metrics_image" -storageDataPath=/data -httpListenAddr=:8428 >/dev/null
docker run -d --name "$grafana_name" --network "$network" --network-alias grafana \
  ${grafana_user:+--user "$grafana_user"} --env-file "$work_dir/grafana.env" \
  --tmpfs /var/lib/grafana:mode=1777 \
  -v "$plugin_dir:/var/lib/grafana/plugins:ro" "${mounts[@]}" "$grafana_image" >/dev/null

client() {
  docker run --rm --network "$network" --user "$(id -u):$(id -g)" \
    -v "$work_dir:/w" "$client_image" "$@"
}

ready=""
for _ in $(seq 1 90); do
  if client wget -q -O /dev/null http://victorialogs:9428/health 2>/dev/null \
    && client wget -q -O /dev/null http://victoriametrics:8428/health 2>/dev/null \
    && client wget -q -O /dev/null http://grafana:3000/api/health 2>/dev/null; then
    ready=1
    break
  fi
  sleep 1
done
[[ -n "$ready" ]] || fail "victorialogs, victoriametrics or grafana did not start"

client wget -q -O /dev/null --header 'Content-Type: application/stream+json' \
  --post-file /w/records.jsonl 'http://victorialogs:9428/insert/jsonline?_stream_fields=log_stream' \
  || fail "ingestion refused"
expected="$(cat "$work_dir/records.count")"
stored=""
for _ in $(seq 1 30); do
  stored="$(client wget -q -O - 'http://victorialogs:9428/select/logsql/query?query=*' 2>/dev/null | grep -c . || true)"
  [[ "$stored" == "$expected" ]] && break
  sleep 1
done
[[ "$stored" == "$expected" ]] || fail "$stored records stored, expected $expected"

# --- Requests, all from the client container; responses checked below.
cat > "$work_dir/requests.sh" <<'SH'
set -u
g=http://grafana:3000
h="X-authentik-username: $1"
wget -S -O /dev/null "$g/api/search" > /w/out/anonymous.txt 2>&1
wget -S -O /dev/null --header 'Authorization: Basic YWRtaW46YWRtaW4=' "$g/api/user" > /w/out/basic.txt 2>&1
wget -S -O /dev/null --header 'Content-Type: application/json' \
  --post-data '{"user":"admin","password":"admin"}' "$g/login" > /w/out/login.txt 2>&1
wget -q -O /w/out/user.json --header "$h" "$g/api/user"
wget -q -O /w/out/orgs.json --header "$h" "$g/api/user/orgs"
wget -q -O /w/out/search.json --header "$h" "$g/api/search?type=dash-db"
wget -q -O /w/out/plugin.json --header "$h" "$g/api/plugins/$2/settings"
for body in /w/bodies/q*.json; do
  name="$(basename "$body" .json)"
  wget -q -O "/w/out/$name.json" --header "$h" --header 'Content-Type: application/json' \
    --post-file "$body" "$g/api/ds/query" 2> "/w/out/$name.err" || true
done
SH
client sh /w/requests.sh "$viewer" "$plugin_id" || true

python3 -I - "$work_dir" "$viewer" "$plugin_id" "$pinned_version" <<'PY' || fail "see above"
import json, sys

work, viewer, plugin_id, pinned = sys.argv[1:]
out = f"{work}/out"
errors = []

def load(name):
    try:
        return json.load(open(f"{out}/{name}"))
    except (OSError, ValueError) as exc:
        errors.append(f"{name}: unreadable response ({exc})")
        return None

anonymous = open(f"{out}/anonymous.txt").read()
if " 401 " not in anonymous:
    errors.append(f"request without header not refused with 401: {anonymous.strip()[:200]}")
# The default admin/admin account exists; no password path may reach it.
basic = open(f"{out}/basic.txt").read()
if " 401 " not in basic:
    errors.append(f"Basic auth admin/admin not refused with 401: {basic.strip()[:200]}")
login = open(f"{out}/login.txt").read()
if " 400 " not in login and " 401 " not in login:
    errors.append(f"POST /login admin/admin not refused: {login.strip()[:200]}")

user = load("user.json")
if user is not None and user.get("login") != viewer:
    errors.append(f"proxy user is {user.get('login')!r}, expected {viewer!r}")
orgs = load("orgs.json")
if orgs is not None and [o.get("role") for o in orgs] != ["Viewer"]:
    errors.append(f"new user roles {orgs}, expected one org with Viewer")

search = load("search.json")
if search is not None:
    uids = sorted(d.get("uid") for d in search)
    if uids != ["victoria-authentik", "victoria-proxmox"]:
        errors.append(f"dashboards visible to the viewer: {uids}")

plugin = load("plugin.json")
if plugin is not None and plugin.get("info", {}).get("version") != pinned:
    errors.append(f"{plugin_id} loaded at {plugin.get('info', {}).get('version')!r}, pinned {pinned}")

index = json.load(open(f"{work}/bodies/index.json"))
counts = {}
for q in index:
    label = f'{q["dashboard"]} / {q["panel"]} ({q["datasource"]})'
    counts[q["datasource"]] = counts.get(q["datasource"], 0) + 1
    body = load(f'{q["file"]}.json')
    if body is None:
        errors.append(f"{label}: {open(f'{out}/{q['file']}.err').read().strip()}")
        continue
    result = body.get("results", {}).get(q["refId"], {})
    if result.get("status") != 200 or result.get("error"):
        errors.append(f"{label}: status {result.get('status')}, error {result.get('error')!r}")
        continue
    if q["datasource"] == "victorialogs":
        rows = [len(f["data"]["values"][0]) for f in result.get("frames", [])
                if f.get("data", {}).get("values")]
        if not any(rows):
            errors.append(f"{label}: no data returned")

if counts.get("victorialogs", 0) == 0:
    errors.append("no VictoriaLogs target found in the dashboards")

for e in errors:
    print(f"  {e}", file=sys.stderr)
if errors:
    sys.exit(1)
print(f"{len(index)} targets queried: " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items())))
PY

echo "OK: Grafana refuses requests without the Authentik header, signs users up as Viewer, loads the pinned plugin and answers every dashboard target"
