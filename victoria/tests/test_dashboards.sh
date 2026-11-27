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
#   sixteen provisioned dashboards (services, Authentik, Proxmox, UniFi,
#   Synology, hosts, logs, Docker, DNS, firewall, HTTP, alerts, disks, stack,
#   Freebox, network), each in its folder: the overview ones (services, hosts,
#   logs, alerts, network) at the root (General), the detail ones in
#   Infrastructure, "Équipements réseau" and Applications;
# - static rules of the dashboards: every rate() of a range panel uses
#   $__rate_interval (a fixed window undersamples a long time range), and the
#   VictoriaMetrics datasource declares a timeInterval of at least the longest
#   scrape interval, so that $__rate_interval always spans 4 samples; no
#   VictoriaLogs query filters log_stream outside a stream filter {...}; every
#   recording rule a dashboard reads is defined in the vmalert-metrics rules;
# - the VictoriaLogs plugin is loaded at the version pinned in
#   GF_PLUGINS_PREINSTALL_SYNC;
# - every VictoriaLogs target of the dashboards, sent as the viewer to
#   /api/ds/query, answers 200 without error and returns data from records
#   ingested before (Proxmox, Authentik, Docker, AdGuard Home, UniFi firewall
#   and CEF, Traefik access logs, alert rule states, with the fields Vector
#   produces);
# - the HTTP dashboard returns the exact request count, 4xx and 5xx rates and
#   p95 latency of the Traefik sample, which holds WebSocket sessions
#   (status 0) and SSE requests (/user/events) lasting minutes: they count as
#   requests, and no number of the dashboard, table cells included, may
#   reach their duration;
# - every VictoriaMetrics target answers 200 without error; the targets of
#   the hosts dashboard also return data from host metrics imported before
#   (one silent host, one degraded ZFS pool), except "silent hosts" for a host
#   that still reports, which must return none; the services dashboard counts
#   exactly one silent host. vmalert does not run here: the series of the
#   host_name:metrics_age_seconds:max record is imported as vmalert would
#   write it, and the record itself is unit tested in
#   metrics_rules_unittest.yaml (test_alerting.sh). The host S.M.A.R.T. targets
#   of the disks dashboard return data from smartctl_exporter series imported
#   before. There is no Proxmox, UniFi or Synology metric in the test, so
#   their targets only have to parse;
# - the IP tables of the DNS and firewall dashboards (two per dashboard) and
#   the client table of the HTTP dashboard join
#   their IP with UnPoller client and device series imported before: each
#   such panel is Mixed, its VictoriaMetrics target is an instant table, an
#   outer join on the IP field of the logs query keeps only rows with a
#   count, and the final columns are "nom UniFi" and "MAC". The mapping
#   query returns one row per IP, and for an IP that changed hands the MAC
#   seen last. Grafana applies the join in the browser, so the test checks
#   its definition, not its result. $__range stays in the expression: the
#   Grafana backend replaces it;
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
[[ ${#mounts[@]} -eq 36 ]] || fail "expected 18 Grafana configs, got $((${#mounts[@]} / 2))"

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
    {"host_name": "test.example", "compose_project": "demo", "compose_service": "app",
     "container_name": "demo-app", "log_iostream": "stderr", "severity": "Error", "level": "error",
     "_msg": "request 42 failed"},
    {"host_name": "test.example", "compose_project": "demo", "compose_service": "old",
     "container_name": "demo-old", "log_iostream": "stderr", "severity": "error", "level": "error",
     "_msg": "worker 7 crashed", "_age": 180},
    {"host_name": "test.example", "compose_project": "demo", "compose_service": "old",
     "container_name": "demo-old", "log_iostream": "stdout", "severity": "info", "level": "info",
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
    {"host_name": "gw", "appname": "CEF", "cef_ext_unificategory": "Security",
     "cef_signature_id": "300", "cef_name": "Threat Detected and Blocked",
     "cef_ext_unifirisk": "high", "cef_ext_src": "203.0.113.9", "cef_ext_dst": "198.51.100.10", "cef_ext_dpt": "445",
     "cef_ext_msg": "ET SCAN suspicious inbound", "_msg": "0|Ubiquiti|UniFi Network|300"},
    {"host_name": "gw", "appname": "CEF", "cef_ext_unificategory": "Security",
     "cef_signature_id": "203", "cef_name": "Blocked by Firewall",
     "cef_ext_unififirewallpolicy": "Block IoT", "cef_ext_unifisrcclientalias": "camera",
     "cef_ext_unifisrcclientip": "198.51.100.30", "cef_ext_unifidstzone": "External",
     "_msg": "0|Ubiquiti|UniFi Network|203"},
]
# Traefik access logs (JSON fields prefixed with app_ by Vector). The status
# comes as "200.0" or 200 depending on the line; durations are in ns. The
# value variant filters on cloud.home.lan, nextcloud@docker, GET and
# 192.168.0.57 at once, so these lines alone carry a 2xx, a 4xx, a 5xx and
# the same path three times. A line without a host (a bare TLS probe) must be
# excluded; 172.18.0.1 is the Docker bridge, unknown to UniFi.
def http(host, service, method, client, path, status, duration, origin, size,
         proto="HTTP/2.0", tls="1.3", router=None):
    r = {"host_name": "proxy.home.lan", "app_clienthost": client,
         "app_requestmethod": method, "app_requestpath": path,
         "app_downstreamstatus": status, "app_duration": duration,
         "app_originduration": origin, "app_downstreamcontentsize": size,
         "app_servicename": service, "app_requestprotocol": proto, "app_tlsversion": tls}
    if host:
        r["app_requesthost"] = host
    if router:
        r["app_routername"] = router
    return r
traefik = [
    http("cloud.home.lan", "nextcloud@docker", "GET", "192.168.0.57", "/status.php", "200.0",
         40000000, 35000000, 512),
    http("cloud.home.lan", "nextcloud@docker", "GET", "192.168.0.57", "/status.php", 200,
         60000000, 55000000, 512),
    http("cloud.home.lan", "nextcloud@docker", "GET", "192.168.0.57", "/status.php", "503.0",
         900000000, 880000000, 128),
    http("cloud.home.lan", "nextcloud@docker", "GET", "192.168.0.57", "/missing", 404,
         5000000, 3000000, 64),
    http("grafana.home.lan", "grafana@docker", "POST", "172.18.0.1", "/api/ds/query", "200.0",
         120000000, 110000000, 2048, proto="HTTP/1.1", tls="1.2"),
    http("", "", "GET", "203.0.113.5", "/", "404.0", 1000000, 0, 19),
]
# Long-lived streams, outside the value variant: Traefik logs a WebSocket
# session with status 0 and the Forgejo SSE stream with 200, each lasting as
# long as the browser tab. Three of each, so that "Chemins les plus lents"
# (at least 3 requests) would list them if the latency filter missed them.
traefik += [http("grafana.home.lan", "grafana@docker", "GET", "192.168.0.10", "/api/live/ws",
                 status, 3600000000000, 3599000000000, 0)
            for status in ("0.0", 0, "0.0")]
traefik += [http("git.home.lan", "forgejo@docker", "GET", "192.168.0.10", "/user/events",
                 status, 600000000000, 599000000000, 4096)
            for status in ("200.0", 200, "200.0")]
# Ingestion routers: the collectors drop their own successful requests from
# the access log (myansible otel_collector), so only the 502 of a Vector
# restart remain. Counted, they would show the ingestion as 100 % 5xx: every
# panel must leave them out, so the expected values below do not move.
traefik += [http("logs.example", "vector@docker", "POST", "198.51.100.57", "/v1/logs", "502.0",
                 2000000, 200000, 11, router="vector_ingest@docker")
            for _ in range(3)]
traefik += [http("metrics.example", "victoriametrics@docker", "POST", "198.51.100.57",
                 "/opentelemetry/v1/metrics", 502, 2000000, 200000, 11,
                 router="victoriametrics_ingest@docker")]
records = [{"log_stream": "proxmox", "host_name": "pve.example", "_msg": "pve", **r} for r in proxmox]
records += [{"log_stream": "authentik", "host_name": "sso.home.lan", "_msg": "ak", **r} for r in authentik]
records += [{"log_stream": "docker", **r} for r in docker]
records += [{"log_stream": "dns_queries", "_msg": "dns", **r} for r in dns_queries]
records += [{"log_stream": "firewall", "severity": "notice", "level": "info", **r} for r in firewall]
records += [{"log_stream": "syslog", "facility": "user", **r} for r in cef]
records += [{"log_stream": "traefik", "_msg": "http", **r} for r in traefik]
# Syslog of the UniFi devices, for the Réseau dashboard: one warning from the
# switch, routine lines from an AP. Another host must stay out of both panels.
records += [{"log_stream": "syslog", "facility": "daemon", "host_name": h, "level": lvl, "_msg": msg}
            for h, lvl, msg in (("sw24poe", "warning", "port 21 link down"),
                                ("wifi-rdc.example", "info", "station associated"),
                                ("wifi-rdc.example", "info", "station left"),
                                ("other.example", "error", "not a network device"))]
# The rule states Vector polls from vmalert every minute (see alert_rules):
# the Alertes dashboard reads the last 3 minutes, so they are fresh. One rule
# per state, and one whose evaluation fails.
def rule(name, source, state, health, severity, msg, **extra):
    return {"log_stream": "alerts", "_age": 0, "_msg": msg, "alert_rule": name, "alert_group": source,
            "alert_source": source, "alert_state": state, "alert_health": health,
            "alert_severity": severity, "alert_count": int(state != "inactive"), **extra}
records += [rule("proxmox_backup_failed", "logs", "firing", "ok", "critical",
                 "Sauvegarde vzdump Proxmox en echec", alert_active_since=at(10)),
            rule("traefik_5xx_burst", "logs", "pending", "ok", "warning", "15 erreurs 5xx",
                 alert_active_since=at(1)),
            rule("oom_kill", "logs", "inactive", "ok", "critical", "Condition non remplie : OOM"),
            rule("vmalert_rule_errors", "metrics", "inactive", "err", "warning",
                 "Erreur d'evaluation : cannot parse query"),
            rule("watchdog", "metrics", "firing", "ok", "none", "Chaine d'alerte vivante")]
with open(f"{work}/records.jsonl", "w") as f:
    for i, r in enumerate(records):
        age = r.pop("_age", i % 5 + 1)
        f.write(json.dumps({"_time": at(age), **r}) + "\n")
with open(f"{work}/records.count", "w") as f:
    f.write(str(len(records)))

# Host metrics as the OpenTelemetry collector exports them, one sample a minute
# over 20 min for test.example; old.example stops 30 min ago (silent host);
# one degraded ZFS pool.
lines = []
def series(name, labels, values):
    lab = ",".join(f'{k}="{v}"' for k, v in labels.items())
    for minutes, value in values:
        ts = int((now - datetime.timedelta(minutes=minutes)).timestamp() * 1000)
        lines.append(f"{name}{{{lab}}} {value} {ts}")
recent = range(20, -1, -1)
for state, step in (("idle", 50), ("user", 10)):
    series("system_cpu_time_seconds_total", {"host_name": "test.example", "state": state},
           [(m, (20 - m) * step) for m in recent])
series("system_cpu_time_seconds_total", {"host_name": "old.example", "state": "idle"},
       [(m, (60 - m) * 50) for m in range(60, 29, -1)])
# What vmalert records from the series above (host_name:metrics_age_seconds:max,
# the age of the newest CPU sample): about 15 s for test.example, and for
# old.example the time since its last sample 30 min ago.
for minutes in recent:
    series("host_name:metrics_age_seconds:max", {"host_name": "test.example"}, [(minutes, 15)])
    series("host_name:metrics_age_seconds:max", {"host_name": "old.example"},
           [(minutes, (30 - minutes) * 60)])
series("system_memory_utilization_ratio", {"host_name": "test.example", "state": "used"},
       [(m, 0.4) for m in recent])
series("system_cpu_load_average_5m", {"host_name": "test.example"}, [(m, 0.7) for m in recent])
series("system_filesystem_utilization_ratio",
       {"host_name": "test.example", "mountpoint": "/", "type": "ext4"}, [(m, 0.55) for m in recent])
for direction in ("receive", "transmit"):
    series("system_network_io_bytes_total",
           {"host_name": "test.example", "device": "eth0", "direction": direction},
           [(m, (20 - m) * 6000) for m in recent])
    series("system_disk_io_bytes_total",
           {"host_name": "test.example", "device": "sda", "direction": direction},
           [(m, (20 - m) * 9000) for m in recent])
# Inodes, interface errors, paging and processes of the hosts "Système" row.
for state, value in (("used", 2e5), ("free", 8e5)):
    series("system_filesystem_inodes_usage",
           {"host_name": "test.example", "mountpoint": "/", "type": "ext4", "state": state},
           [(m, value) for m in recent])
for name in ("system_network_errors_total", "system_network_dropped_total"):
    series(name, {"host_name": "test.example", "device": "eth0", "direction": "receive"},
           [(m, (20 - m) * 3) for m in recent])
series("system_paging_faults_total", {"host_name": "test.example", "type": "major"},
       [(m, (20 - m) * 30) for m in recent])
series("system_paging_operations_total",
       {"host_name": "test.example", "type": "major", "direction": "page_in"},
       [(m, (20 - m) * 12) for m in recent])
for status, value in (("running", 2), ("blocked", 1)):
    series("system_processes_count", {"host_name": "test.example", "status": status},
           [(m, value) for m in recent])
series("zfs_pool_health", {"host_name": "pve.example", "pool": "rpool"}, [(m, 1) for m in recent])
series("zfs_pool_capacity_ratio", {"host_name": "pve.example", "pool": "rpool"}, [(m, 0.6) for m in recent])
# smartctl_exporter on smart-test.example: a hard disk with bad sectors, CRC and
# logged errors, and an SSD that has used 8 % of its life.
smart = {"host_name": "smart-test.example", "service_name": "smart"}
for device, model, protocol in (("sda", "WDC WD40EFRX", "ATA"), ("sdb", "Samsung SSD 870", "ATA")):
    disk = {**smart, "device": device}
    series("smartctl_device", {**disk, "model_name": model, "protocol": protocol}, [(m, 1) for m in recent])
    series("smartctl_device_capacity_bytes", disk, [(m, 4e12) for m in recent])
    series("smartctl_device_smart_status", disk, [(m, 1) for m in recent])
    series("smartctl_device_temperature", {**disk, "temperature_type": "current"}, [(m, 38) for m in recent])
    series("smartctl_device_power_on_seconds_total", disk, [(m, 9e7 + m) for m in recent])
    series("smartctl_device_power_cycle_count_total", disk, [(m, 120) for m in recent])
for name, kind, value in (("Reallocated_Sector_Ct", "raw", 8), ("Current_Pending_Sector", "raw", 2),
                          ("Offline_Uncorrectable", "raw", 1), ("UDMA_CRC_Error_Count", "raw", 3)):
    series("smartctl_device_attribute", {**smart, "device": "sda", "attribute_name": name,
                                         "attribute_value_type": kind}, [(m, value) for m in recent])
series("smartctl_device_error_log_count", {**smart, "device": "sda", "error_log_type": "summary"},
       [(m, 4) for m in recent])
series("smartctl_device_attribute", {**smart, "device": "sdb", "attribute_name": "Wear_Leveling_Count",
                                     "attribute_value_type": "value"}, [(m, 92) for m in recent])
# UnPoller clients and devices, which name the IPs of the DNS and firewall
# tables. DHCP gave 192.168.0.10 to "old-pc" until 3 h ago, then to "laptop":
# the mapping keeps one row per IP, the MAC seen last, although old-pc has the
# larger value. 192.168.0.99 is in no log.
unifi = [("unpoller_client_uptime_seconds", "192.168.0.10", "aa:bb:cc:00:00:10", "laptop", 300, recent),
         ("unpoller_client_uptime_seconds", "192.168.0.10", "aa:bb:cc:00:00:11", "old-pc", 90000,
          range(200, 179, -1)),
         ("unpoller_client_uptime_seconds", "192.168.0.57", "aa:bb:cc:00:00:57", "tv", 4000, recent),
         ("unpoller_client_uptime_seconds", "192.168.0.99", "aa:bb:cc:00:00:99", "phone", 100, recent),
         ("unpoller_device_info", "192.168.69.254", "aa:bb:cc:00:00:fe", "gateway", 1, recent)]
for name, ip, mac, label, value, minutes in unifi:
    series(name, {"ip": ip, "mac": mac, "name": label, "site_name": "default"},
           [(m, value) for m in minutes])
# Réseau dashboard: the Freebox is up, its Synology exporter answers 0, unpoller
# sees four of the five UniFi devices (wifi-etage-nuit is down) and chataigne
# sends host metrics. Exporter series carry their job label, like the scrapes.
fbx = {"job": "freebox"}
series("up", fbx, [(m, 1) for m in recent])
series("up", {"job": "synology"}, [(m, 0) for m in recent])
series("fbx_exporter_connection_state", {**fbx, "state": "up"}, [(m, 1) for m in recent])
series("fbx_exporter_connection_ftth_link", fbx, [(m, 1) for m in recent])
series("fbx_exporter_connection_rate_down", fbx, [(m, 125000) for m in recent])
series("fbx_exporter_connection_rate_up", fbx, [(m, 25000) for m in recent])
up = {"job": "unpoller", "site_name": "default"}
for device, kind in (("gw", "udm"), ("sw24poe", "usw"), ("wifi-rdc", "uap"), ("wifi-etage-vie", "uap")):
    dev = {**up, "name": device}
    series("unpoller_device_info", {**dev, "type": kind}, [(m, 1) for m in recent])
    series("unpoller_device_uptime_seconds", dev, [(m, 86400 + 60 * (20 - m)) for m in recent])
    series("unpoller_device_cpu_utilization_ratio", dev, [(m, 0.1) for m in recent])
    series("unpoller_device_memory_utilization_ratio", dev, [(m, 0.5) for m in recent])
    series("unpoller_device_temperature_celsius", dev, [(m, 45) for m in recent])
    series("unpoller_device_stations", dev, [(m, 3) for m in recent])
    series("unpoller_device_upgradable", dev, [(m, int(device == "sw24poe")) for m in recent])
series("unpoller_device_wan_status", {**up, "name": "gw", "status": "online"}, [(m, 1) for m in recent])
for direction in ("receive", "transmit"):
    series(f"unpoller_device_wan_{direction}_bytes_total", {**up, "name": "gw"},
           [(m, (20 - m) * 60000) for m in recent])
series("unpoller_site_latency_seconds", {**up, "subsystem": "www"}, [(m, 0.012) for m in recent])
series("system_memory_utilization_ratio", {"host_name": "chataigne.example", "state": "used"},
       [(m, 0.7) for m in recent])
with open(f"{work}/metrics.txt", "w") as f:
    f.write("\n".join(lines) + "\n")

# One /api/ds/query body per target and variant, variables replaced as the
# plugins do before sending a query:
# - "value": one value per variable, present in the records above;
#   VictoriaLogs turns in($v) into in("value"), Prometheus inserts the value;
# - "all": the default "All" choice; VictoriaLogs turns in($v) into in(*),
#   Prometheus inserts the allValue the variable declares (required, as
#   without it Grafana would send every value as an alternation).
# $search is a text box whose default is *. Grafana replaces $__range itself.
values = {
    "victoria-authentik": {"application": "app.home.lan", "composant": "worker"},
    "victoria-dns": {"host_name": "ns01.home.lan", "client": "192.168.0.10"},
    "victoria-docker": {"host_name": "test.example", "compose_project": "demo",
                        "container_name": "demo-old"},
    "victoria-firewall": {"host_name": "gw", "action": "drop", "ruleset": "WAN_LOCAL"},
    "victoria-logs": {"log_stream": "docker", "host_name": "test.example"},
    "victoria-hosts": {"host_name": "test.example"},
    "victoria-http": {"requesthost": "cloud.home.lan", "service": "nextcloud@docker",
                      "method": "GET", "client": "192.168.0.57"},
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

def window_of(expr, start):
    """Range window of the rate( call opening at start: the last [...] of
    its argument, as label matchers may hold [a-z] classes."""
    depth, quoted = 0, False
    for i in range(start, len(expr)):
        c = expr[i]
        if c == '"' and expr[i - 1] != "\\":
            quoted = not quoted
        elif not quoted and c == "(":
            depth += 1
        elif not quoted and c == ")":
            depth -= 1
            if depth == 0:
                found = re.search(r"\[([^\[\]]+)\]\s*$", expr[start:i])
                return found.group(1) if found else None
    return None

compose = json.load(open(f"{work}/compose.json"))
rules = compose["configs"]["vmalert_metrics_rules"]["content"]
recorded = set(re.findall(r"^\s*-\s*record:\s*(\S+)", rules, re.M))
scrape = compose["configs"]["victoriametrics_scrape"]["content"]
seconds = lambda d: int(d[:-1]) * {"s": 1, "m": 60}[d[-1]]
longest = max(seconds(d) for d in re.findall(r"scrape_interval:\s*(\d+[sm])", scrape))
datasources = open(f"{work}/configs/grafana_datasources").read()
time_interval = re.search(r"timeInterval:\s*(\d+[sm])", datasources)
assert time_interval and seconds(time_interval.group(1)) >= longest, \
    f"VictoriaMetrics datasource timeInterval {time_interval and time_interval.group(1)}, longest scrape {longest}s"

index = []
for name in ("authentik", "proxmox", "unifi", "synology", "hosts", "logs",
             "docker", "dns", "firewall", "http", "alerts", "disks", "services", "stack", "freebox",
             "network"):
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
            where = f'{dash["uid"]} / {panel["title"]}'
            if datasource == "victorialogs":
                assert "log_stream:" not in target["expr"], \
                    f"{where}: log_stream filtered as a field, not as a stream: {target['expr']}"
            else:
                for used in re.findall(r"\b[a-z_]+:[a-z_]+:[a-z_]+\b", target["expr"]):
                    assert used in recorded, f"{where}: {used} is no recording rule of vmalert-metrics"
                if not target.get("instant"):
                    for call in re.finditer(r"\b(?:i?rate)\(", target["expr"]):
                        window = window_of(target["expr"], call.end() - 1)
                        assert window == "$__rate_interval", \
                            f"{where}: rate window [{window}] in a range panel, expected [$__rate_interval]"
            for variant in ("value", "all"):
                if variant == "all" and "$" not in re.sub(r"\$__(?:rate_interval|range)\b", "", target["expr"]):
                    continue
                query = dict(target)
                query["expr"] = substitute(target["expr"], datasource, variables, variant, all_values)
                # $__range and $__rate_interval, which Grafana fills in, and a
                # regex end anchor ($ before a closing quote) are not variables.
                assert "$" not in re.sub(r'\$__(?:rate_interval|range)\b|\$(?=")', "", query["expr"]), \
                    f'{dash["uid"]} / {panel["title"]}: {query["expr"]}'
                n = len(index) + 1
                json.dump({"from": "now-24h", "to": "now", "queries": [query]},
                          open(f"{work}/bodies/q{n:03d}.json", "w"))
                index.append({"file": f"q{n:03d}", "dashboard": dash["uid"],
                              "panel": panel["title"], "refId": query.get("refId", "A"),
                              "datasource": datasource, "variant": variant,
                              "unifi_map": "unpoller_" in target["expr"]
                                           and dash["uid"] in ("victoria-dns", "victoria-firewall",
                                                           "victoria-http")})
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

# The Alertes dashboard reads the last 3 minutes: date the rule states now,
# whatever the time Grafana took to start.
fresh="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq -c --arg t "$fresh" 'if .log_stream == "alerts" then ._time = $t else . end' \
  "$work_dir/records.jsonl" > "$work_dir/records.tmp" && mv "$work_dir/records.tmp" "$work_dir/records.jsonl"
chmod a+r "$work_dir/records.jsonl"

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
import json, math, re, sys

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

expected_uids = ["victoria-alerts", "victoria-authentik", "victoria-disks", "victoria-dns", "victoria-docker",
                 "victoria-firewall", "victoria-freebox",
                 "victoria-hosts", "victoria-http", "victoria-logs", "victoria-network", "victoria-proxmox", "victoria-services",
                 "victoria-stack", "victoria-synology", "victoria-unifi"]
# Host S.M.A.R.T. panels of the disks dashboard, which must return the
# smartctl_exporter series imported before (the NAS targets only parse).
smart_panels = {("victoria-disks", title) for title in (
    "Disques des hôtes", "Température des disques des hôtes",
    "Secteurs défectueux des disques des hôtes", "Vie restante des SSD des hôtes")}
# Targets that must return nothing: test.example is not silent.
# Réseau tree, by refId of the Canvas panel: 1 up, 0 down, -1 no collection.
# wifi-etage-nuit (I) is down while unpoller answers, pads918 (K) is down by
# its exporter.
tree_panel = ("victoria-network", "Internet → Freebox → gw → sw24poe → équipements")
tree_expected = dict(zip("ABCDEFGHIJK", (1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 0)))
expected_empty = {("victoria-hosts", "Hôtes silencieux (> 10 min)", "value")}
# Host panels of the services dashboard, which read the imported record.
services_hosts = {("victoria-services", "Hôtes silencieux"), ("victoria-services", "Hôtes")}
# Exact values from the Traefik records: 4 lines match the four values (one
# 404, one 503), 11 lines have a host (the hostless 404 probe must not count,
# the 6 long-lived streams do). The p95 latency leaves out the streams: 900 ms
# is the slowest short request, in both variants.
expected_values = {("victoria-hosts", "Hôtes silencieux (> 10 min)", "all"): 1,
                   ("victoria-services", "Hôtes silencieux", "value"): 1,
                   ("victoria-network", "Synology", "value"): 0,
                   ("victoria-network", "UniFi", "value"): 4,
                   ("victoria-network", "Hôtes OpenTelemetry", "value"): 2,
                   ("victoria-http", "Requêtes", "value"): 4,
                   ("victoria-http", "Requêtes", "all"): 11,
                   ("victoria-http", "Taux de 4xx", "value"): 25,
                   ("victoria-http", "Taux de 4xx", "all"): 100 / 11,
                   ("victoria-http", "Taux de 5xx", "value"): 25,
                   ("victoria-http", "Taux de 5xx", "all"): 100 / 11,
                   ("victoria-http", "Latence p95", "value"): 900000000,
                   ("victoria-http", "Latence p95", "all"): 900000000,
                   # The global view must agree with the HTTP dashboard.
                   ("victoria-services", "Requêtes HTTP", "value"): 11,
                   ("victoria-services", "Taux de 5xx", "value"): 100 / 11,
                   ("victoria-services", "Latence HTTP p95", "value"): 900000000}
# No number returned by the HTTP dashboard may come from a stream: the
# shortest one lasts 599 s, 5.99e11 in ns and 5.99e5 in ms, while the largest
# legitimate number is the 900 ms p95 in ns.
stream_floor = 1e11
search = load("search.json")
if search is not None:
    uids = sorted(d.get("uid") for d in search)
    if uids != expected_uids:
        errors.append(f"dashboards visible to the viewer: {uids}")
    # Overview dashboards at the root, detail ones in a folder named after the
    # sub-directory of their file. Links between them use uids and tags.
    expected_folders = {
        "victoria-services": None, "victoria-hosts": None, "victoria-logs": None,
        "victoria-alerts": None, "victoria-network": None,
        "victoria-proxmox": "Infrastructure", "victoria-synology": "Infrastructure",
        "victoria-disks": "Infrastructure", "victoria-stack": "Infrastructure",
        "victoria-unifi": "Équipements réseau", "victoria-freebox": "Équipements réseau",
        "victoria-firewall": "Équipements réseau", "victoria-dns": "Équipements réseau",
        "victoria-authentik": "Applications", "victoria-docker": "Applications",
        "victoria-http": "Applications"}
    for d in search:
        folder = d.get("folderTitle") or None
        if d.get("uid") in expected_folders and folder != expected_folders[d["uid"]]:
            errors.append(f'{d["uid"]} in folder {folder!r}, expected {expected_folders[d["uid"]]!r}')

plugin = load("plugin.json")
if plugin is not None and plugin.get("info", {}).get("version") != pinned:
    errors.append(f"{plugin_id} loaded at {plugin.get('info', {}).get('version')!r}, pinned {pinned}")

def isnumber(v):
    try:
        return math.isfinite(float(v))
    except (TypeError, ValueError):
        return False

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

unifi_ips = ["192.168.0.10", "192.168.0.57", "192.168.0.99", "192.168.69.254"]

# IP tables named from UnPoller. Grafana joins in the browser, so this checks
# the chain the browser runs: A (VictoriaLogs) and B (the mapping) in a Mixed
# panel, B renamed to the IP field that A groups by, an outer join on it, rows
# without a count removed (IPs that UnPoller knows but no log mentions).
mapped = {"victoria-dns": {"Clients les plus actifs", "Clients les plus bloqués"},
          "victoria-firewall": {"Top sources bloquées", "Top destinations bloquées"},
          "victoria-http": {"Clients les plus actifs"}}
for name, uid in (("dns", "victoria-dns"), ("firewall", "victoria-firewall"),
                  ("http", "victoria-http")):
    dash = json.load(open(f"{work}/configs/grafana_dashboard_{name}"))
    found = set()
    for panel in dash["panels"]:
        refs = {t.get("refId"): t for t in panel.get("targets", [])}
        if "unpoller_" not in refs.get("B", {}).get("expr", ""):
            continue
        found.add(panel["title"])
        where = f'{uid} / {panel["title"]}'
        steps = panel.get("transformations", [])
        ids = [s["id"] for s in steps]
        try:
            j = ids.index("joinByField")
            key = steps[j]["options"]["byField"]
            org_b = next(s for s in steps[:j] if s["id"] == "organize"
                         and s.get("filter", {}).get("options") == "B")
            after = steps[j + 1] if j + 1 < len(steps) else {}
            if after.get("id") != "filterByValue":
                errors.append(f"{where}: no exclusion of rows without a count after the join")
                continue
            count = after["options"]["filters"][0]["fieldName"]
        except (ValueError, StopIteration, KeyError, IndexError) as exc:
            errors.append(f"{where}: transformation chain incomplete ({exc!r})")
            continue
        by = re.search(r"stats by \(([^)]*)\)", refs["A"]["expr"])
        checks = [
            (panel.get("datasource", {}).get("uid") == "-- Mixed --", "panel datasource is not Mixed"),
            (refs["A"]["datasource"]["uid"] == "victorialogs", "target A is not VictoriaLogs"),
            (refs["B"]["datasource"]["uid"] == "victoriametrics" and refs["B"].get("instant")
             and refs["B"].get("format") == "table", "target B is not an instant VictoriaMetrics table"),
            (steps[j]["options"].get("mode") == "outerTabular", "join is not outerTabular"),
            (org_b["options"]["renameByName"].get("ip") == key, f"B's ip is not renamed to {key}"),
            (by is not None and key in [f.strip() for f in by.group(1).split(",")],
             f"A does not group by {key}"),
            (re.search(rf"\bas {re.escape(count)}\b", refs["A"]["expr"]) is not None,
             f"A produces no field {count}"),
            (steps[j + 1]["id"] == "filterByValue" and steps[j + 1]["options"].get("type") == "exclude"
             and steps[j + 1]["options"]["filters"][0]["config"]["id"] == "isNull",
             "no exclusion of rows without a count after the join"),
            (all(s.get("filter", {}).get("options") == "A" for s in steps[:j]
                 if s["id"] in ("extractFields", "convertFieldType")),
             "a transformation of A also applies to B"),
            ({"unifi_name", "unifi_mac"} <= set(steps[-1]["options"].get("renameByName", {})),
             "MAC and name not shown"),
        ]
        errors += [f"{where}: {msg}" for ok, msg in checks if not ok]
    if found != mapped[uid]:
        errors.append(f"{uid}: tables named from UnPoller {sorted(found)}, expected {sorted(mapped[uid])}")

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
    if q["unifi_map"]:
        # One frame per IP, with its MAC and name, for the IPs UnPoller knows.
        ips = {}
        for f in result.get("frames", []):
            for field in f.get("schema", {}).get("fields", []):
                labels = field.get("labels") or {}
                if "ip" in labels:
                    ips.setdefault(labels["ip"], []).append((labels.get("mac"), labels.get("name")))
        if sorted(ips) != unifi_ips or any(len(v) != 1 or None in v[0] for v in ips.values()):
            errors.append(f"{label}: IP mapping {ips}, expected one MAC and name for each of {unifi_ips}")
        elif ips["192.168.0.10"][0] != ("aa:bb:cc:00:00:10", "laptop"):
            errors.append(f"{label}: 192.168.0.10 maps to {ips['192.168.0.10'][0]}, expected the MAC seen last")
        continue
    if (q["dashboard"], q["panel"]) == tree_panel:
        got = [float(x) for f in result.get("frames", [])
               for i, field in enumerate(f.get("schema", {}).get("fields", []))
               if field.get("type") == "number"
               for x in f.get("data", {}).get("values", [])[i] if x is not None]
        if got != [tree_expected[q["refId"]]]:
            errors.append(f"{label}: {got}, expected [{tree_expected[q['refId']]}]")
        continue
    if (q["datasource"] == "victorialogs" or q["dashboard"] in ("victoria-hosts", "victoria-network")
            or (q["dashboard"], q["panel"]) in smart_panels | services_hosts):
        found = any(has_data(f) for f in result.get("frames", []))
        key = (q["dashboard"], q["panel"], q["variant"])
        if key in expected_empty:
            if found:
                errors.append(f"{label}: data returned, expected none")
        elif not found and expected_values.get(key) != 0:
            # A value expected to be 0 is checked against expected_values below.
            errors.append(f"{label}: no data returned")
        got = [float(x) for f in result.get("frames", [])
               for i, field in enumerate(f.get("schema", {}).get("fields", []))
               if field.get("type") == "number"
               for x in f.get("data", {}).get("values", [])[i] if x is not None]
        # Table panels get their stats as strings in each row's labels.
        stats = got + [float(v) for f in result.get("frames", [])
                       for i, field in enumerate(f.get("schema", {}).get("fields", []))
                       if field.get("name") == "labels"
                       for row in f.get("data", {}).get("values", [])[i] if isinstance(row, dict)
                       for v in row.values() if isnumber(v)]
        if q["dashboard"] in ("victoria-http", "victoria-services") and any(x >= stream_floor for x in stats):
            errors.append(f"{label}: {max(stats)} counts a long-lived stream")
        if key in expected_values:
            if len(got) != 1 or abs(got[0] - expected_values[key]) > 0.01:
                errors.append(f"{label}: {got}, expected {expected_values[key]}")
        if (q["dashboard"], q["panel"]) == ("victoria-alerts", "État des règles"):
            # The firing watchdog is the healthy state: shown as "veille" (green),
            # while a real firing rule keeps "firing" (red).
            states = {}
            for f in result.get("frames", []):
                fields = f.get("schema", {}).get("fields", [])
                columns = f.get("data", {}).get("values", [])
                for r in range(len(columns[0]) if columns else 0):
                    row = {}
                    for i, field in enumerate(fields):
                        v = columns[i][r]
                        row.update(v if isinstance(v, dict) else {field.get("name"): v})
                    states[row.get("alert_rule")] = row.get("alert_state")
            want = {"watchdog": "veille", "proxmox_backup_failed": "firing"}
            if any(states.get(k) != v for k, v in want.items()):
                errors.append(f"{label}: states {states}, expected {want}")

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
