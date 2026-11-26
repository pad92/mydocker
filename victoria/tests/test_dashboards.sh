#!/usr/bin/env bash
# Grafana test, on the configs and environment as Compose renders them with
# .env.example.
#
# On a throwaway internal network: VictoriaLogs, VictoriaMetrics and Grafana
# with the rendered environment, provisioning files and dashboards. Checks:
# - without the X-authentik-username header the API answers 401 (no anonymous
#   access), Basic auth and POST /login with the default admin/admin are
#   refused;
# - with the header a new user is created with the Viewer role and sees the
#   nine provisioned dashboards (Authentik, Proxmox, UniFi, Synology, hosts,
#   logs, Docker, DNS, firewall);
# - the VictoriaLogs plugin is loaded at the version pinned in
#   GF_PLUGINS_PREINSTALL_SYNC;
# - every VictoriaLogs target of the dashboards, sent as the viewer to
#   /api/ds/query, answers 200 without error and returns data from records
#   ingested before (Proxmox, Authentik, Docker, AdGuard Home, UniFi firewall
#   and CEF, with the fields Vector produces);
# - every VictoriaMetrics target answers 200 without error; the targets of
#   the hosts dashboard also return data from host metrics imported before
#   (one silent host, one degraded ZFS pool), except "silent hosts" for a host
#   that still reports, which must return none. There is no Proxmox, UniFi or
#   Synology metric in the test, so their targets only have to parse;
# - every dashboard contributes at least one target.
# Each target using a variable is sent twice, as Grafana sends it: once with
# one value present in the test data, once with the default "All" choice
# (in(*) for VictoriaLogs, .* for the hosts dashboard). The search box keeps
# its default, *.
#
# One change in the test only: Grafana cannot download the plugin on an
# internal network, so GF_PLUGINS_PREINSTALL_DISABLED=true and the plugin
# comes read-only from GRAFANA_PLUGIN_DIR, a directory holding
# victoriametrics-logs-datasource/ at the pinned version (for example the
# plugins/ directory of a Grafana that installed it once). The test refuses
# another version.
# Not covered: the rendering in a browser, the Authentik outpost in front of
# Grafana, the real Proxmox, UniFi and Synology metric names (see the README).
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
[[ ${#mounts[@]} -eq 22 ]] || fail "expected 11 Grafana configs, got $((${#mounts[@]} / 2))"

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
import datetime, json, os, re, sys

work = sys.argv[1]
now = datetime.datetime.now(datetime.timezone.utc)

def at(minutes):
    return (now - datetime.timedelta(minutes=minutes)).strftime("%Y-%m-%dT%H:%M:%SZ")

# Records as Vector stores them after parsing (fields from the *_test.yaml
# files and from live records), a few minutes old unless "_age" says otherwise.
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
# demo-old logged 3 h ago only: it feeds "Conteneurs sans log depuis 1 h".
docker = [
    {"host_name": "test.home.lan", "compose_project": "demo", "compose_service": "app",
     "container_name": "demo-app", "log_iostream": "stderr", "severity": "Error",
     "_msg": "request 42 failed"},
    {"host_name": "test.home.lan", "compose_project": "demo", "compose_service": "old",
     "container_name": "demo-old", "log_iostream": "stderr", "severity": "error",
     "_msg": "worker 7 crashed", "_age": 180},
    {"host_name": "test.home.lan", "compose_project": "demo", "compose_service": "old",
     "container_name": "demo-old", "log_iostream": "stdout", "severity": "info",
     "_msg": "worker started", "_age": 181},
]
# AdGuard Home query log: reason 3 blocked, 9 rewrite, 1 allowlist; cached
# answers keep the upstream of the first one, as live records do.
def dns(host, ip, qh, qt="A", cached=False, upstream="192.168.69.2:5335",
        elapsed="25000000", filtered=False, reason=None):
    r = {"host_name": host, "body_ip": ip, "body_qh": qh, "body_qt": qt,
         "body_cached": "true" if cached else "false", "body_upstream": upstream,
         "body_elapsed": elapsed, "body_qc": "IN"}
    if filtered:
        r["body_result_isfiltered"] = "true"
    if reason:
        r["body_result_reason"] = reason
    return r
dns_queries = [
    dns("ns01.home.lan", "192.168.0.10", "slow.example.com", elapsed="80000000"),
    dns("ns01.home.lan", "192.168.0.10", "slow.example.com", elapsed="90000000"),
    dns("ns01.home.lan", "192.168.0.10", "slow.example.com", elapsed="95000000"),
    dns("ns01.home.lan", "192.168.0.10", "slow.example.com", qt="AAAA", cached=True, elapsed="40000"),
    dns("ns01.home.lan", "192.168.0.10", "ads.example.net", upstream="", elapsed="30000",
        filtered=True, reason="3.0"),
    dns("ns01.home.lan", "192.168.0.10", "nas.home.lan", upstream="", elapsed="20000",
        reason="9.0"),
    dns("ns01.home.lan", "192.168.0.10", "allowed.example.org", elapsed="15000000",
        reason="1.0"),
    dns("ns02.home.lan", "192.168.0.20", "www.example.com", elapsed="12000000"),
]
# UniFi gateway firewall (fields of parse_firewall); WAN_LOCAL is a drop from
# the Internet, LAN_WAN a reject from a LAN client.
def fw(action, ruleset, rule_id, descr, src, dst, iface_in, iface_out, proto, dpt):
    return {"host_name": "gw", "appname": "gw", "fw_action": action,
            "fw_ruleset": ruleset, "fw_rule": f"{ruleset}-{action[0].upper()}-{rule_id}",
            "fw_rule_id": rule_id, "fw_descr": descr, "fw_src": src, "fw_dst": dst,
            "fw_in": iface_in, "fw_out": iface_out, "fw_proto": proto, "fw_dpt": dpt,
            "_msg": f"[{ruleset}] DESCR={descr}"}
firewall = [
    fw("drop", "WAN_LOCAL", "3000", "drop-wan", "203.0.113.7", "192.168.69.254",
       "eth6", "", "TCP", "22"),
    fw("drop", "WAN_LOCAL", "3000", "drop-wan", "203.0.113.8", "192.168.69.254",
       "eth6", "", "TCP", "3389"),
    fw("reject", "LAN_WAN", "40001", "block-dns", "192.168.0.57", "8.8.8.8",
       "br0", "eth6", "UDP", "53"),
]
# UniFi CEF events: an IPS threat, and a firewall block (signature 203).
cef = [
    {"host_name": "gw", "appname": "CEF", "UNIFIcategory": "Security",
     "cef_signature_id": "300", "cef_name": "Threat Detected and Blocked",
     "UNIFIrisk": "high", "src": "203.0.113.9", "dst": "192.168.0.10", "dpt": "445",
     "msg": "ET SCAN suspicious inbound", "_msg": "0|Ubiquiti|UniFi Network|300"},
    {"host_name": "gw", "appname": "CEF", "UNIFIcategory": "Security",
     "cef_signature_id": "203", "cef_name": "Blocked by Firewall",
     "UNIFIfirewallPolicy": "Block IoT", "UNIFIsrcClientAlias": "camera",
     "UNIFIsrcClientIp": "192.168.0.30", "UNIFIdstZone": "External",
     "_msg": "0|Ubiquiti|UniFi Network|203"},
]
records = [{"log_stream": "proxmox", "host_name": "pve.home.lan", "_msg": "pve", **r} for r in proxmox]
records += [{"log_stream": "authentik", "host_name": "sso.home.lan", "_msg": "ak", **r} for r in authentik]
records += [{"log_stream": "docker", **r} for r in docker]
records += [{"log_stream": "dns_queries", "_msg": "dns", **r} for r in dns_queries]
records += [{"log_stream": "firewall", "severity": "notice", **r} for r in firewall]
records += [{"log_stream": "syslog", "facility": "user", **r} for r in cef]
with open(f"{work}/records.jsonl", "w") as f:
    for i, r in enumerate(records):
        age = r.pop("_age", i % 5 + 1)
        f.write(json.dumps({"_time": at(age), **r}) + "\n")
with open(f"{work}/records.count", "w") as f:
    f.write(str(len(records)))

# Host metrics as the OpenTelemetry collector exports them, one sample a minute
# over 20 min for test.home.lan; old.home.lan stops 30 min ago (silent host);
# one degraded ZFS pool.
lines = []
def series(name, labels, values):
    lab = ",".join(f'{k}="{v}"' for k, v in labels.items())
    for minutes, value in values:
        ts = int((now - datetime.timedelta(minutes=minutes)).timestamp() * 1000)
        lines.append(f"{name}{{{lab}}} {value} {ts}")
recent = range(20, -1, -1)
for state, step in (("idle", 50), ("user", 10)):
    series("system_cpu_time_seconds_total", {"host_name": "test.home.lan", "state": state},
           [(m, (20 - m) * step) for m in recent])
series("system_cpu_time_seconds_total", {"host_name": "old.home.lan", "state": "idle"},
       [(m, (60 - m) * 50) for m in range(60, 29, -1)])
series("system_memory_utilization_ratio", {"host_name": "test.home.lan", "state": "used"},
       [(m, 0.4) for m in recent])
series("system_cpu_load_average_5m", {"host_name": "test.home.lan"}, [(m, 0.7) for m in recent])
series("system_filesystem_utilization_ratio",
       {"host_name": "test.home.lan", "mountpoint": "/", "type": "ext4"}, [(m, 0.55) for m in recent])
for direction in ("receive", "transmit"):
    series("system_network_io_bytes_total",
           {"host_name": "test.home.lan", "device": "eth0", "direction": direction},
           [(m, (20 - m) * 6000) for m in recent])
    series("system_disk_io_bytes_total",
           {"host_name": "test.home.lan", "device": "sda", "direction": direction},
           [(m, (20 - m) * 9000) for m in recent])
series("zfs_pool_health", {"host_name": "pve.home.lan", "pool": "rpool"}, [(m, 1) for m in recent])
series("zfs_pool_capacity_ratio", {"host_name": "pve.home.lan", "pool": "rpool"}, [(m, 0.6) for m in recent])
with open(f"{work}/metrics.txt", "w") as f:
    f.write("\n".join(lines) + "\n")

# One /api/ds/query body per target and variant, variables replaced as the
# plugins do before sending a query:
# - "value": one value per variable, present in the records above;
#   VictoriaLogs turns in($v) into in("value"), Prometheus inserts the value;
# - "all": the default "All" choice; VictoriaLogs turns in($v) into in(*),
#   Prometheus inserts the allValue the variable declares (required, as
#   without it Grafana would send every value as an alternation).
# $search is a text box whose default is *.
values = {
    "victoria-authentik": {"application": "app.home.lan", "composant": "worker"},
    "victoria-dns": {"host_name": "ns01.home.lan", "client": "192.168.0.10"},
    "victoria-docker": {"host_name": "test.home.lan", "compose_project": "demo",
                        "container_name": "demo-old"},
    "victoria-firewall": {"host_name": "gw", "action": "drop", "ruleset": "WAN_LOCAL"},
    "victoria-logs": {"log_stream": "docker", "host_name": "test.home.lan"},
    "victoria-hosts": {"host_name": "test.home.lan"},
}

def substitute(expr, datasource, variables, variant, all_values):
    for var, value in variables.items():
        if datasource == "victorialogs":
            expr = expr.replace(f"in(${var})", "in(*)" if variant == "all"
                                else f"in({json.dumps(value)})")
        else:
            expr = expr.replace(f"${var}", all_values[var] if variant == "all"
                                else value.replace(".", "\\\\."))
    return expr.replace("$search", "*")

index = []
for name in ("authentik", "proxmox", "unifi", "synology", "hosts", "logs",
             "docker", "dns", "firewall"):
    dash = json.load(open(f"{work}/configs/grafana_dashboard_{name}"))
    declared = {v["name"] for v in dash.get("templating", {}).get("list", [])}
    all_values = {v["name"]: v.get("allValue") for v in dash.get("templating", {}).get("list", [])
                  if v.get("includeAll") and v.get("datasource", {}).get("type") == "prometheus"}
    assert all(all_values.values()), f'{dash["uid"]}: Prometheus variable without allValue'
    variables = values.get(dash["uid"], {})
    missing = declared - set(variables) - {"search"}
    assert not missing, f'{dash["uid"]}: no test value for {sorted(missing)}'
    for panel in dash["panels"]:
        for target in panel.get("targets", []):
            datasource = target["datasource"]["uid"]
            for variant in ("value", "all"):
                if variant == "all" and "$" not in target["expr"]:
                    continue
                query = dict(target)
                query["expr"] = substitute(target["expr"], datasource, variables, variant, all_values)
                assert "$" not in query["expr"], f'{dash["uid"]} / {panel["title"]}: {query["expr"]}'
                n = len(index) + 1
                json.dump({"from": "now-24h", "to": "now", "queries": [query]},
                          open(f"{work}/bodies/q{n:03d}.json", "w"))
                index.append({"file": f"q{n:03d}", "dashboard": dash["uid"],
                              "panel": panel["title"], "refId": query.get("refId", "A"),
                              "datasource": datasource, "variant": variant})
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

client wget -q -O /dev/null --post-file /w/metrics.txt 'http://victoriametrics:8428/api/v1/import/prometheus' \
  || fail "metric import refused"
client wget -q -O /dev/null 'http://victoriametrics:8428/internal/force_flush' || fail "force_flush refused"
expected_series="$(awk '{print $1}' "$work_dir/metrics.txt" | sort -u | wc -l)"
(( expected_series > 0 )) || fail "no metric series generated"
# /api/v1/series/count may count a series once per day index, so count the
# distinct series that /api/v1/series returns instead.
series_url="http://victoriametrics:8428/api/v1/series?match%5B%5D=%7B__name__%21%3D%22%22%7D&start=$(( $(date +%s) - 7200 ))"
series=""
for _ in $(seq 1 30); do
  series="$(client wget -q -O - "$series_url" 2>/dev/null \
    | python3 -c 'import json,sys; print(len({json.dumps(m, sort_keys=True) for m in json.load(sys.stdin)["data"]}))' 2>/dev/null || true)"
  [[ "$series" == "$expected_series" ]] && break
  sleep 1
done
[[ "$series" == "$expected_series" ]] \
  || fail "VictoriaMetrics holds ${series:-no} distinct series, expected $expected_series"

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

expected_uids = ["victoria-authentik", "victoria-dns", "victoria-docker", "victoria-firewall",
                 "victoria-hosts", "victoria-logs", "victoria-proxmox", "victoria-synology",
                 "victoria-unifi"]
# Targets that must return nothing: test.home.lan is not silent.
expected_empty = {("victoria-hosts", "Hôtes silencieux (> 10 min)", "value")}
search = load("search.json")
if search is not None:
    uids = sorted(d.get("uid") for d in search)
    if uids != expected_uids:
        errors.append(f"dashboards visible to the viewer: {uids}")

plugin = load("plugin.json")
if plugin is not None and plugin.get("info", {}).get("version") != pinned:
    errors.append(f"{plugin_id} loaded at {plugin.get('info', {}).get('version')!r}, pinned {pinned}")

def has_data(frame):
    """A frame holds data when it has rows and, if it has numeric fields, at
    least one non-zero value: `stats count()` without `by` answers one row
    with 0 when the filter matches nothing."""
    values = frame.get("data", {}).get("values") or []
    if not values or not any(len(v) for v in values):
        return False
    fields = frame.get("schema", {}).get("fields", [])
    numeric = [i for i, f in enumerate(fields)
               if f.get("type") == "number" and i < len(values)]
    if not numeric:
        return True
    return any(x not in (None, 0) for i in numeric for x in values[i])

index = json.load(open(f"{work}/bodies/index.json"))
counts = {}
for q in index:
    label = f'{q["dashboard"]} / {q["panel"]} ({q["datasource"]}, {q["variant"]})'
    counts[q["datasource"]] = counts.get(q["datasource"], 0) + 1
    body = load(f'{q["file"]}.json')
    if body is None:
        errors.append(f"{label}: {open(f'{out}/{q['file']}.err').read().strip()}")
        continue
    result = body.get("results", {}).get(q["refId"], {})
    if result.get("status") != 200 or result.get("error"):
        errors.append(f"{label}: status {result.get('status')}, error {result.get('error')!r}")
        continue
    if q["datasource"] == "victorialogs" or q["dashboard"] == "victoria-hosts":
        found = any(has_data(f) for f in result.get("frames", []))
        if (q["dashboard"], q["panel"], q["variant"]) in expected_empty:
            if found:
                errors.append(f"{label}: data returned, expected none")
        elif not found:
            errors.append(f"{label}: no data returned")

seen = sorted({q["dashboard"] for q in index})
if seen != expected_uids:
    errors.append(f"dashboards with targets: {seen}")
if counts.get("victorialogs", 0) == 0:
    errors.append("no VictoriaLogs target found in the dashboards")

for e in errors:
    print(f"  {e}", file=sys.stderr)
if errors:
    sys.exit(1)
print(f"{len(index)} queries sent: " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items())))
PY

echo "OK: Grafana refuses requests without the Authentik header, signs users up as Viewer, loads the pinned plugin and answers every dashboard target"
