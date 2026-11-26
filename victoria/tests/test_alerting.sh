#!/usr/bin/env bash
# Alerting test, on the configs as Compose renders them with .env.example.
#
# Static part:
# - vmalert -dryRun with the rendered command of vmalert-logs and
#   vmalert-metrics: every LogsQL and MetricsQL expression parses;
# - amtool check-config on the Alertmanager config;
# - consistency: one Alertmanager route per alert, its repeat_interval equal to
#   the keep_firing_for of the alert, no route without an alert, and the
#   receiver URL matches the alertmanager_webhook source of Vector.
#
# End-to-end part, on a throwaway internal network: VictoriaLogs,
# VictoriaMetrics, vmalert-logs, Alertmanager and Vector with their rendered
# commands and configs. Two changes in the test copy only, both checked:
# - group intervals of the log rules set to 5s (5m and 60m in production);
# - the free_mobile sink posts to VictoriaLogs instead of the Free Mobile API,
#   so the SMS body can be read back.
# Proxmox records already parsed (pve_* fields, as the Vector unit tests
# produce them) go straight into VictoriaLogs: a failed vzdump job, a failed
# acmerenew task and a failed qmstart task. The test expects
# proxmox_backup_failed, and proxmox_task_failed for qmstart only, in
# Alertmanager, then one SMS body per alert with the test credentials.
# Not covered: the Proxmox parsing (proxmox_test.yaml), the metric rules on
# real data (metric names to check after deployment, see the README), the
# Free Mobile API itself.
#
# Needs Docker, Docker Compose 2.23+, jq and python3 with PyYAML; no published
# port, no Internet. Usage: ./tests/test_alerting.sh
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="$stack_dir/.env.example"
version() { sed -n "s/^$1=//p" "$env_file"; }
logs_image="victoriametrics/victoria-logs:$(version VICTORIA_LOGS_VERSION)"
metrics_image="victoriametrics/victoria-metrics:$(version VICTORIA_METRICS_VERSION)"
vmalert_image="victoriametrics/vmalert:$(version VMALERT_VERSION)"
alertmanager_image="prom/alertmanager:$(version ALERTMANAGER_VERSION)"
vector_image="timberio/vector:$(version VECTOR_VERSION)-distroless-libc"
client_image="${CLIENT_IMAGE:-busybox:1.37}"
timeout_s="${ALERTING_TIMEOUT:-120}"

suffix="$$-$RANDOM"
network="victoria-alerting-test-$suffix"
logs_name="victorialogs-test-$suffix"
metrics_name="victoriametrics-test-$suffix"
vmalert_name="vmalert-logs-test-$suffix"
am_name="alertmanager-test-$suffix"
vector_name="vector-test-$suffix"
work_dir="$(mktemp -d)"

cleanup() {
  docker rm -f "$vector_name" "$vmalert_name" "$am_name" "$metrics_name" "$logs_name" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  local name
  for name in "$vmalert_name" "$am_name" "$vector_name"; do
    if docker inspect "$name" >/dev/null 2>&1; then
      echo "--- $name logs" >&2
      docker logs "$name" 2>&1 | tail -n 20 >&2 || true
    fi
  done
  exit 1
}

# --- Rendering: the files and commands the containers really receive.
PUID="${PUID:-1000}" PGID="${PGID:-1000}" docker compose \
  --project-directory "$stack_dir" --env-file "$env_file" \
  config --format json > "$work_dir/compose.json"
config() {
  jq -er --arg c "$1" '.configs[$c].content | gsub("\\$\\$"; "$")' "$work_dir/compose.json" > "$work_dir/$2"
}
config vmalert_logs_rules logs_rules.yml
config vmalert_metrics_rules metrics_rules.yml
config alertmanager_config alertmanager.yml
config vector_config vector.yaml
mapfile -t vmalert_logs_cmd < <(jq -er '.services["vmalert-logs"].command[]' "$work_dir/compose.json")
mapfile -t vmalert_metrics_cmd < <(jq -er '.services["vmalert-metrics"].command[]' "$work_dir/compose.json")
mapfile -t am_cmd < <(jq -er '.services.alertmanager.command[]' "$work_dir/compose.json")
chmod -R a+rX "$work_dir"

# --- Static: expressions parse with the flags of each vmalert (LogsQL needs
# -rule.defaultRuleType=vlogs, which comes from the rendered command).
dry_run() {
  local rules="$1"; shift
  docker run --rm -v "$work_dir/$rules:/etc/vmalert/rules.yml:ro" "$vmalert_image" "$@" -dryRun \
    > "$work_dir/dryrun.log" 2>&1 || { cat "$work_dir/dryrun.log" >&2; fail "vmalert -dryRun rejects $rules"; }
}
dry_run logs_rules.yml "${vmalert_logs_cmd[@]}"
dry_run metrics_rules.yml "${vmalert_metrics_cmd[@]}"

docker run --rm --entrypoint amtool -v "$work_dir/alertmanager.yml:/am.yml:ro" \
  "$alertmanager_image" check-config /am.yml > "$work_dir/amtool.log" 2>&1 \
  || { cat "$work_dir/amtool.log" >&2; fail "amtool check-config rejects the Alertmanager config"; }

python3 -I - "$work_dir" <<'PY_EOF' || fail "alert and route consistency"
import re, sys, yaml

work = sys.argv[1]
def load(name):
    with open(f"{work}/{name}") as f:
        return yaml.safe_load(f)

def seconds(d):
    units = {"s": 1, "m": 60, "h": 3600, "d": 86400}
    parts = re.findall(r"(\d+)([smhd])", d)
    if not parts or "".join(n + u for n, u in parts) != d:
        sys.exit(f"unreadable duration {d!r}")
    return sum(int(n) * units[u] for n, u in parts)

errors = []
alerts = {}
for rules in ("logs_rules.yml", "metrics_rules.yml"):
    for group in load(rules)["groups"]:
        for rule in group["rules"]:
            name = rule.get("alert")
            if name is None:
                continue
            if name in alerts:
                errors.append(f"alert {name} defined twice")
            if "keep_firing_for" not in rule:
                errors.append(f"alert {name} has no keep_firing_for")
                continue
            alerts[name] = seconds(rule["keep_firing_for"])

am = load("alertmanager.yml")
routes = {}
for route in am["route"].get("routes", []):
    matchers = route.get("matchers", [])
    m = re.fullmatch(r'alertname="([a-z0-9_]+)"', matchers[0]) if len(matchers) == 1 else None
    if m is None:
        errors.append(f"route with matchers {matchers}: expected one alertname matcher")
        continue
    name = m.group(1)
    if name in routes:
        errors.append(f"two routes for {name}")
    if route.get("receiver", "sms") != "sms" or route.get("continue"):
        errors.append(f"route {name}: other receiver or continue")
    routes[name] = seconds(route.get("repeat_interval", am["route"]["repeat_interval"]))

for name in sorted(set(alerts) - set(routes)):
    errors.append(f"alert {name} has no route")
for name in sorted(set(routes) - set(alerts)):
    errors.append(f"route {name} has no alert")
for name in sorted(set(alerts) & set(routes)):
    if alerts[name] != routes[name]:
        errors.append(f"{name}: keep_firing_for {alerts[name]}s, repeat_interval {routes[name]}s")

receivers = {r["name"]: r for r in am["receivers"]}
hooks = receivers.get(am["route"]["receiver"], {}).get("webhook_configs", [])
source = load("vector.yaml")["sources"]["alertmanager_webhook"]
port = source["address"].rsplit(":", 1)[1]
expected = f"http://vector:{port}{source['path']}"
if [h.get("url") for h in hooks] != [expected]:
    errors.append(f"receiver webhooks {hooks}: expected one to {expected}")
elif hooks[0].get("send_resolved", True):
    errors.append("send_resolved is not false: a resolved alert would send an SMS")

if errors:
    sys.exit("\n".join(errors))
print(f"{len(alerts)} alerts, one route each")
PY_EOF

# --- Test copy: short group intervals, SMS sink to VictoriaLogs. Each change
# is checked, so a renamed field cannot leave the test on the production value.
python3 -I - "$work_dir" <<'PY_EOF' || fail "patching the test copy"
import sys, yaml

work = sys.argv[1]
path = f"{work}/logs_rules.yml"
with open(path) as f:
    rules = yaml.safe_load(f)
for group in rules["groups"]:
    group["interval"] = "5s"
with open(path, "w") as f:
    yaml.safe_dump(rules, f, sort_keys=False, allow_unicode=True)

path = f"{work}/vector.yaml"
with open(path) as f:
    vector = yaml.safe_load(f)
sink = vector["sinks"]["free_mobile"]
if sink["uri"] != "https://smsapi.free-mobile.fr/sendmsg":
    sys.exit(f"free_mobile uri is {sink['uri']}")
# The SMS body {user, pass, msg} as one record: msg is the message, user the
# stream, so the test can find it.
sink["uri"] = "http://victorialogs:9428/insert/jsonline?_msg_field=msg&_stream_fields=user"
with open(path, "w") as f:
    yaml.safe_dump(vector, f, sort_keys=False, allow_unicode=True)
PY_EOF
grep -q 'smsapi.free-mobile.fr' "$work_dir/vector.yaml" && fail "the SMS sink still points to Free Mobile"
[[ "$(grep -c 'interval: 5s' "$work_dir/logs_rules.yml")" -eq "$(grep -c '^- name:\|^  - name:' "$work_dir/logs_rules.yml")" ]] \
  || fail "group intervals not patched"
chmod -R a+rX "$work_dir"

# --- End to end.
docker network create --internal "$network" >/dev/null
docker run -d --name "$logs_name" --network "$network" --network-alias victorialogs \
  --tmpfs /data "$logs_image" -storageDataPath=/data -httpListenAddr=:9428 >/dev/null
docker run -d --name "$metrics_name" --network "$network" --network-alias victoriametrics \
  --tmpfs /data "$metrics_image" -storageDataPath=/data -httpListenAddr=:8428 >/dev/null
docker run -d --name "$am_name" --network "$network" --network-alias alertmanager \
  --tmpfs /alertmanager -v "$work_dir/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro" \
  "$alertmanager_image" "${am_cmd[@]}" >/dev/null
docker run -d --name "$vector_name" --network "$network" --network-alias vector \
  --tmpfs /var/lib/vector -v "$work_dir/vector.yaml:/etc/vector/vector.yaml:ro" \
  -e FREE_MOBILE_USER=test-user -e FREE_MOBILE_PASS=test-pass "$vector_image" >/dev/null

client() {
  docker run --rm --network "$network" "$client_image" "$@"
}

ready=""
for _ in $(seq 1 30); do
  if client wget -q -O /dev/null http://victorialogs:9428/health 2>/dev/null \
    && client wget -q -O /dev/null http://victoriametrics:8428/health 2>/dev/null \
    && client wget -q -O /dev/null http://alertmanager:9093/-/ready 2>/dev/null \
    && client nc -z vector 8080 2>/dev/null; then
    ready=1
    break
  fi
  sleep 1
done
[[ -n "$ready" ]] || fail "victorialogs, victoriametrics, alertmanager or vector did not start"

# Records one minute old: inside the 15 minute windows whatever the
# evaluation delay of vmalert.
record_time="$(date -u -d '-1 min' +%Y-%m-%dT%H:%M:%SZ)"
jq -cn --arg t "$record_time" '
  {_time: $t, _msg: "vzdump job failed", log_stream: "proxmox", pve_backup_event: "job_failed"},
  {_time: $t, _msg: "acmerenew failed", log_stream: "proxmox", pve_task_failed: "true", pve_task_type: "acmerenew"},
  {_time: $t, _msg: "qmstart failed", log_stream: "proxmox", pve_task_failed: "true", pve_task_type: "qmstart"}
' > "$work_dir/records.jsonl"
chmod a+r "$work_dir/records.jsonl"
docker run --rm --network "$network" -v "$work_dir/records.jsonl:/records.jsonl:ro" "$client_image" \
  wget -q -O /dev/null --header 'Content-Type: application/stream+json' --post-file /records.jsonl \
  'http://victorialogs:9428/insert/jsonline?_stream_fields=log_stream' || fail "ingestion refused"

logsql() {
  client wget -q -O - "http://victorialogs:9428/select/logsql/query?query=$(jq -rn --arg q "$1" '$q | @uri')"
}
stored=""
for _ in $(seq 1 15); do
  stored="$(logsql '{log_stream="proxmox"}' | wc -l)"
  [[ "$stored" -eq 3 ]] && break
  sleep 1
done
[[ "$stored" -eq 3 ]] || fail "expected 3 Proxmox records in VictoriaLogs, got $stored"

# vmalert last: its first evaluation finds the records.
docker run -d --name "$vmalert_name" --network "$network" \
  -v "$work_dir/logs_rules.yml:/etc/vmalert/rules.yml:ro" \
  "$vmalert_image" "${vmalert_logs_cmd[@]}" >/dev/null

deadline=$((SECONDS + timeout_s))
alerts=""
until [[ $SECONDS -ge $deadline ]]; do
  alerts="$(client wget -q -O - http://alertmanager:9093/api/v2/alerts 2>/dev/null || true)"
  if jq -e '[.[].labels.alertname] | index("proxmox_backup_failed") and index("proxmox_task_failed")' \
    <<<"${alerts:-[]}" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
jq -e '[.[] | select(.labels.alertname == "proxmox_backup_failed")] | length == 1' <<<"${alerts:-[]}" >/dev/null \
  || fail "proxmox_backup_failed not in Alertmanager: $alerts"
task_types="$(jq -c '[.[] | select(.labels.alertname == "proxmox_task_failed") | .labels.pve_task_type] | sort' <<<"$alerts")"
[[ "$task_types" == '["qmstart"]' ]] || fail "proxmox_task_failed for $task_types, expected [\"qmstart\"] (acmerenew left out)"

# One SMS per alertname (group_by), after group_wait.
sms=""
until [[ $SECONDS -ge $deadline ]]; do
  sms="$(logsql '{user="test-user"}' 2>/dev/null || true)"
  [[ -n "$sms" && "$(wc -l <<<"$sms")" -ge 2 ]] && break
  sleep 2
done
[[ -n "$sms" ]] || fail "no SMS body reached the sink"
jq -e -s 'all(.[]; .pass == "test-pass")' <<<"$sms" >/dev/null || fail "SMS without the test credentials: $sms"
messages="$(jq -c -s '[.[]._msg] | sort' <<<"$sms")"
expected='["1 sauvegardes vzdump Proxmox en echec en 15 minutes","Tache Proxmox qmstart en erreur (1 en 15 minutes)"]'
[[ "$messages" == "$expected" ]] || fail "SMS texts: expected $expected, got $messages"

echo "OK: rules parse, routes match the alerts, a Proxmox failure reaches the SMS sink"
