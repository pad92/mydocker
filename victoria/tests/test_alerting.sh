#!/usr/bin/env bash
# Alerting test, on the configs as Compose renders them with .env.example.
#
# Static part:
# - vmalert -dryRun with the rendered command of vmalert-logs and
#   vmalert-metrics: every LogsQL and MetricsQL expression parses;
# - amtool check-config on the Alertmanager config;
# - vmalert-tool unittest of tests/metrics_rules_unittest.yaml on the rendered
#   metrics rules: firing and quiet cases, exact labels and annotations;
# - consistency: one Alertmanager route per alert, its repeat_interval at
#   least the lifetime of a firing alert (query window + keep_firing_for +
#   group interval: no second SMS while the same event is still firing), no
#   route without an alert, inhibit_rules naming existing alerts only, and
#   the receiver URL matches the alertmanager_webhook source of Vector, with
#   the same Basic auth (strategy basic, username and password). The
#   watchdog is the exception: no keep_firing_for, first route, its own
#   receiver (one webhook, send_resolved false) and a repeat_interval of at
#   most 5m, under the heartbeat interval of the Uptime Kuma monitor.
#
# End-to-end part, on a throwaway internal network: VictoriaLogs,
# VictoriaMetrics, vmalert-logs, vmalert-metrics, Alertmanager and Vector
# with their rendered commands and configs. Changes in the test copy only,
# all checked:
# - group intervals of the rules set to 5s (1m to 60m in production);
# - the free_mobile sink posts to VictoriaLogs instead of the Free Mobile API,
#   so the SMS body can be read back;
# - the watchdog receiver posts to VictoriaLogs instead of Uptime Kuma;
# - the scrape config keeps only the jobs of the stack, every 5s (the
#   unpoller and synology targets do not exist here).
# The SMS webhook of Vector must answer 401 without a password and with a
# wrong one; the SMS lines below prove that Alertmanager gets through.
# Proxmox records already parsed (pve_* fields, as the Vector unit tests
# produce them) go straight into VictoriaLogs: a failed vzdump job, a failed
# acmerenew task and a failed qmstart task. The test expects
# proxmox_backup_failed and proxmox_task_failed for both tasks in
# Alertmanager, then one SMS body per alertname with the test credentials
# and the context labels in its text.
# Then the watchdog: every component scraped (up == 1), the watchdog
# reaches its receiver, the metric names its rules use exist, and stopping
# Vector stops the watchdog.
# Not covered: the Proxmox parsing (proxmox_test.yaml), the metric rules on
# real data (metric names to check after deployment, see the README), the
# Free Mobile API and Uptime Kuma themselves, the free_mobile error branch of
# the watchdog (vector_component_errors_total only exists after an error).
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
vmalert_tool_image="victoriametrics/vmalert-tool:$(version VMALERT_VERSION)"
alertmanager_image="prom/alertmanager:$(version ALERTMANAGER_VERSION)"
vector_image="timberio/vector:$(version VECTOR_VERSION)-distroless-libc"
client_image="${CLIENT_IMAGE:-busybox:1.37}"
timeout_s="${ALERTING_TIMEOUT:-120}"

suffix="$$-$RANDOM"
network="victoria-alerting-test-$suffix"
logs_name="victorialogs-test-$suffix"
metrics_name="victoriametrics-test-$suffix"
vmalert_name="vmalert-logs-test-$suffix"
vmalert_metrics_name="vmalert-metrics-test-$suffix"
am_name="alertmanager-test-$suffix"
vector_name="vector-test-$suffix"
work_dir="$(mktemp -d)"

cleanup() {
  docker rm -f "$vector_name" "$vmalert_name" "$vmalert_metrics_name" "$am_name" "$metrics_name" "$logs_name" \
    >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  local name
  for name in "$vmalert_name" "$vmalert_metrics_name" "$am_name" "$vector_name"; do
    if docker inspect "$name" >/dev/null 2>&1; then
      echo "--- $name logs" >&2
      docker logs "$name" 2>&1 | tail -n 20 >&2 || true
    fi
  done
  exit 1
}

# --- Rendering: the files and commands the containers really receive.
PUID="${PUID:-1000}" PGID="${PGID:-1000}" VECTOR_WEBHOOK_PASSWORD="${VECTOR_WEBHOOK_PASSWORD:-0123456789abcdef}" docker compose \
  --project-directory "$stack_dir" --env-file "$env_file" \
  config --format json > "$work_dir/compose.json"
config() {
  jq -er --arg c "$1" '.configs[$c].content | gsub("\\$\\$"; "$")' "$work_dir/compose.json" > "$work_dir/$2"
}
config vmalert_logs_rules logs_rules.yml
config vmalert_metrics_rules metrics_rules.yml
config alertmanager_config alertmanager.yml
config vector_config vector.yaml
config victoriametrics_scrape scrape.yml
mapfile -t vmalert_logs_cmd < <(jq -er '.services["vmalert-logs"].command[]' "$work_dir/compose.json")
mapfile -t vmalert_metrics_cmd < <(jq -er '.services["vmalert-metrics"].command[]' "$work_dir/compose.json")
mapfile -t am_cmd < <(jq -er '.services.alertmanager.command[]' "$work_dir/compose.json")
mapfile -t metrics_cmd < <(jq -er '.services.victoriametrics.command[]' "$work_dir/compose.json")
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

# --- Unit: vmalert-tool replays series through the rendered metrics rules
# (production intervals): firing and quiet cases, exact labels and
# annotations. It runs before the 5s patch of the test copy below.
cp "$stack_dir/tests/metrics_rules_unittest.yaml" "$work_dir/"
chmod a+r "$work_dir/metrics_rules_unittest.yaml"
docker run --rm -v "$work_dir:/t:ro" "$vmalert_tool_image" \
  unittest --files /t/metrics_rules_unittest.yaml > "$work_dir/unittest.log" 2>&1 \
  || { cat "$work_dir/unittest.log" >&2; fail "vmalert-tool unit tests of the metrics rules"; }

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

# Event window of a rule: how long one event keeps its expression true.
# LogsQL: the first _time filter, none when a count() if (_time:...) makes
# it a presence check over a longer lookback. MetricsQL: the longest range,
# none for lag() (a presence check). Silences and states have none.
def window(rule, logs):
    expr = rule["expr"]
    if logs:
        if "if (_time:" in expr:
            return 0
        m = re.search(r"_time:([0-9]+[smhd])\b", expr)
        return seconds(m.group(1)) if m else 0
    expr = re.sub(r"lag\([^\[]*\[[^\]]*\]\)", "", expr)
    ranges = [seconds(r) for r in re.findall(r"\[([0-9]+[smhd])(?::[0-9]+[smhd])?\]", expr)]
    return max(ranges, default=0)

# Windows not written as a range: an uptime under 600s.
implicit_windows = {"proxmox_guest_restarted": 600}

# repeat_interval must outlast one event: window + keep_firing_for +
# group interval, or a single event sends a second SMS. A self-check of
# window() on known shapes, so a regex change cannot silently return 0.
for expr, logs, want in [
    ("_time:15m {a} | stats count() as n | filter n:>=1", True, 900),
    ("_time:24h {a} | stats by (h) count() if (_time:30m) as r | filter r:<1", True, 0),
    ("max by (h) (lag(m[24h])) > 600", False, 0),
    ("sum(increase(m[2h])) >= 2 and lag(m[24h]) < 60", False, 7200),
    ("m - min_over_time(m[24h]) > 0", False, 86400),
    ("m >= 0.9", False, 0),
]:
    got = window({"expr": expr}, logs)
    if got != want:
        sys.exit(f"window() self-check: {expr!r} gives {got}s, expected {want}s")

errors = []
alerts = {}
lifetimes = {}
tails = {}
groups = {}
for rules in ("logs_rules.yml", "metrics_rules.yml"):
    for group in load(rules)["groups"]:
        for rule in group["rules"]:
            name = rule.get("alert")
            if name is None:
                continue
            if name in alerts:
                errors.append(f"alert {name} defined twice")
            # A restart of a datasource or of Uptime Kuma must not send an SMS.
            if name == "vmalert_rule_errors":
                # One failed evaluation per rule is a restart: two needed.
                if not re.search(r"\)\s*>=\s*([2-9]|[1-9][0-9]+)\s*$", rule["expr"]):
                    errors.append(f"alert {name}: a single failed evaluation would fire")
            if name == "alertmanager_notifications_failed":
                # A for of 10m or more, longer than the increase window, so a
                # single failure never holds the rule for the whole for.
                hold = seconds(rule.get("for", "0s"))
                windows = [seconds(w) for w in re.findall(r"increase\([^\[]*\[([0-9]+[smh])\]", rule["expr"])]
                if hold < 600 or not windows or any(w >= hold for w in windows):
                    errors.append(f"alert {name}: for {hold}s, increase windows {windows}: a transient failure would fire")
            if name == "watchdog":
                # Must stop as soon as its expression is empty.
                if "keep_firing_for" in rule or "for" in rule:
                    errors.append("watchdog has a for or keep_firing_for")
                alerts[name] = None
                continue
            if "keep_firing_for" not in rule:
                errors.append(f"alert {name} has no keep_firing_for")
                continue
            alerts[name] = seconds(rule["keep_firing_for"])
            # After recovery: firing for window + keep_firing_for, then
            # resolved at the next evaluation, up to one group interval on.
            tails[name] = (
                implicit_windows.get(name, window(rule, rules == "logs_rules.yml"))
                + alerts[name]
            )
            lifetimes[name] = tails[name] + seconds(group["interval"])
            groups[name] = (rules, group["name"])

am = load("alertmanager.yml")
routes = {}
for i, route in enumerate(am["route"].get("routes", [])):
    matchers = route.get("matchers", [])
    m = re.fullmatch(r'alertname="([a-z0-9_]+)"', matchers[0]) if len(matchers) == 1 else None
    if m is None:
        errors.append(f"route with matchers {matchers}: expected one alertname matcher")
        continue
    name = m.group(1)
    if name in routes:
        errors.append(f"two routes for {name}")
    if route.get("continue"):
        errors.append(f"route {name}: continue")
    repeat = seconds(route.get("repeat_interval", am["route"]["repeat_interval"]))
    if name == "watchdog":
        if i != 0 or route.get("receiver") != "watchdog":
            errors.append("watchdog route: not first or not on the watchdog receiver")
        if repeat > 300:
            errors.append(f"watchdog repeat_interval {repeat}s: over the 5m Kuma heartbeat")
        routes[name] = None
        continue
    if route.get("receiver", "sms") != "sms":
        errors.append(f"route {name}: receiver other than sms")
    routes[name] = repeat

for name in sorted(set(alerts) - set(routes)):
    errors.append(f"alert {name} has no route")
for name in sorted(set(routes) - set(alerts)):
    errors.append(f"route {name} has no alert")
for name in sorted(set(lifetimes) & set(routes)):
    if routes[name] < lifetimes[name]:
        errors.append(f"{name}: repeat_interval {routes[name]}s under the {lifetimes[name]}s one event keeps it firing")
for name in sorted(set(implicit_windows) - set(lifetimes)):
    errors.append(f"implicit window for {name}, which is not an alert")

receivers = {r["name"]: r for r in am["receivers"]}
hooks = receivers.get(am["route"]["receiver"], {}).get("webhook_configs", [])
source = load("vector.yaml")["sources"]["alertmanager_webhook"]
port = source["address"].rsplit(":", 1)[1]
expected = f"http://vector:{port}{source['path']}"
if [h.get("url") for h in hooks] != [expected]:
    errors.append(f"receiver webhooks {hooks}: expected one to {expected}")
elif hooks[0].get("send_resolved", True):
    errors.append("send_resolved is not false: a resolved alert would send an SMS")
# Any container on the victoria and traefik_gateway networks reaches the
# webhook: Vector requires Basic auth and Alertmanager must send the same.
auth = source.get("auth", {})
if auth.get("strategy") != "basic" or not auth.get("username") or not auth.get("password"):
    errors.append(f"alertmanager_webhook has no Basic auth: {auth.get('strategy')}")
elif hooks and hooks[0].get("http_config", {}).get("basic_auth") \
        != {"username": auth["username"], "password": auth["password"]}:
    errors.append("the sms receiver does not send the Basic auth of alertmanager_webhook")
watchdog_hooks = receivers.get("watchdog", {}).get("webhook_configs", [])
if len(watchdog_hooks) != 1 or "/api/push/" not in watchdog_hooks[0].get("url", ""):
    errors.append(f"watchdog receiver {watchdog_hooks}: expected one Uptime Kuma push URL")
elif watchdog_hooks[0].get("send_resolved", True):
    errors.append("watchdog send_resolved is not false: a resolved watchdog would count as a push")

# Inhibitions: every alert name they match must exist, or a renamed rule
# leaves the inhibition silently dead. Only alertname matchers, so a
# matcher on another label cannot widen one to every alert.
for i, rule in enumerate(am.get("inhibit_rules", [])):
    for side in ("source_matchers", "target_matchers"):
        matchers = rule.get(side, [])
        m = re.fullmatch(r'alertname(=~?)"([a-z0-9_|]+)"', matchers[0]) if len(matchers) == 1 else None
        if m is None:
            errors.append(f"inhibit_rules[{i}] {side} {matchers}: expected one alertname matcher")
            continue
        for name in m.group(2).split("|"):
            if name not in alerts or name == "watchdog":
                errors.append(f"inhibit_rules[{i}] {side}: no alert {name}")

# Inhibition timing: an inhibition ends when its source resolves. If a
# target outlives its source after a shared recovery, the target sends
# its SMS for a cause already over. The source must stay firing at least
# as long as the target: window + keep_firing_for for both when one
# group evaluates them at the same instant, plus the interval of the
# target group otherwise (no credit for the interval of the source).
# Accepted overlaps, each with its reason:
inhibit_overlap_ok = {
    # Usage between 0.9 and 0.95 once the critical alert resolves is a
    # real high alert, and its 720m keep_firing_for is a hysteresis. It
    # fired before the critical one in the usual climb, so Alertmanager
    # holds it as notified and sends nothing new when the inhibition
    # ends. Covering 721m would hold the critical alert, and push its
    # reminders, to twelve hours.
    ("filesystem_usage_critical", "filesystem_usage_high"),
}
for i, rule in enumerate(am.get("inhibit_rules", [])):
    sides = []
    for side in ("source_matchers", "target_matchers"):
        m = re.fullmatch(r'alertname=~?"([a-z0-9_|]+)"', rule.get(side, [""])[0])
        sides.append([n for n in m.group(1).split("|") if n in tails] if m else [])
    for source in sides[0]:
        for target in sides[1]:
            if (source, target) in inhibit_overlap_ok:
                continue
            need = tails[target] if groups[source] == groups[target] else lifetimes[target]
            if tails[source] < need:
                errors.append(
                    f"inhibit_rules[{i}]: {source} resolves {tails[source]}s after a"
                    f" recovery, {target} can fire for {need}s: its SMS"
                    f" would leave once the inhibition ends")
for pair in sorted(inhibit_overlap_ok):
    if not any(re.search(rf'"(.*\|)?{pair[0]}(\|.*)?"', r.get("source_matchers", [""])[0])
               and re.search(rf'"(.*\|)?{pair[1]}(\|.*)?"', r.get("target_matchers", [""])[0])
               for r in am.get("inhibit_rules", [])):
        errors.append(f"inhibit_overlap_ok {pair}: no such inhibition")

if errors:
    sys.exit("\n".join(errors))
print(f"{len(alerts)} alerts, one route each, {len(am.get('inhibit_rules', []))} inhibitions")
PY_EOF

# --- Test copy: short group intervals, SMS sink to VictoriaLogs. Each change
# is checked, so a renamed field cannot leave the test on the production value.
python3 -I - "$work_dir" <<'PY_EOF' || fail "patching the test copy"
import sys, yaml

work = sys.argv[1]
def load(name):
    with open(f"{work}/{name}") as f:
        return yaml.safe_load(f)
def dump(name, data):
    with open(f"{work}/{name}", "w") as f:
        yaml.safe_dump(data, f, sort_keys=False, allow_unicode=True)

for name in ("logs_rules.yml", "metrics_rules.yml"):
    rules = load(name)
    for group in rules["groups"]:
        group["interval"] = "5s"
    dump(name, rules)

# Only the jobs of the stack: every other target is missing on this network.
stack_jobs = {"victoriametrics", "victorialogs", "vmalert-logs", "vmalert-metrics", "alertmanager", "vector"}
scrape = load("scrape.yml")
scrape["scrape_configs"] = [j for j in scrape["scrape_configs"] if j["job_name"] in stack_jobs]
if {j["job_name"] for j in scrape["scrape_configs"]} != stack_jobs:
    sys.exit(f"stack jobs in the scrape config: {[j['job_name'] for j in scrape['scrape_configs']]}")
for job in scrape["scrape_configs"]:
    job["scrape_interval"] = "5s"
dump("scrape.yml", scrape)

# The watchdog body as one record: status is the message, receiver the stream.
am = load("alertmanager.yml")
hooks = [r for r in am["receivers"] if r["name"] == "watchdog"][0]["webhook_configs"]
if "/api/push/" not in hooks[0]["url"]:
    sys.exit(f"watchdog url is {hooks[0]['url']}")
hooks[0]["url"] = "http://victorialogs:9428/insert/jsonline?_msg_field=status&_stream_fields=receiver"
# An alert that joins its group late is sent after group_interval: 5s here.
if am["route"].get("group_interval") != "5m":
    sys.exit(f"route group_interval is {am['route'].get('group_interval')}")
am["route"]["group_interval"] = "5s"
dump("alertmanager.yml", am)

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
for rules in logs_rules.yml metrics_rules.yml; do
  [[ "$(grep -c 'interval: 5s' "$work_dir/$rules")" -eq "$(grep -c '^- name:\|^  - name:' "$work_dir/$rules")" ]] \
    || fail "group intervals not patched in $rules"
done
grep -q '/api/push/' "$work_dir/alertmanager.yml" && fail "the watchdog still points to Uptime Kuma"
chmod -R a+rX "$work_dir"

# --- End to end.
docker network create --internal "$network" >/dev/null
docker run -d --name "$logs_name" --network "$network" --network-alias victorialogs \
  --tmpfs /data "$logs_image" -storageDataPath=/data -httpListenAddr=:9428 >/dev/null
docker run -d --name "$metrics_name" --network "$network" --network-alias victoriametrics \
  --tmpfs /data -v "$work_dir/scrape.yml:/etc/victoria/scrape.yml:ro" \
  "$metrics_image" "${metrics_cmd[@]}" >/dev/null
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
    && client nc -z vector 8080 2>/dev/null \
    && client nc -z vector 9598 2>/dev/null; then
    ready=1
    break
  fi
  sleep 1
done
[[ -n "$ready" ]] || fail "victorialogs, victoriametrics, alertmanager or vector did not start"

# The SMS webhook refuses a request without auth or with a wrong password
# (401 before the body is read); the SMS checks below prove that the
# credentials Alertmanager sends are accepted.
for url in http://vector:8080/alertmanager http://alertmanager:wrong@vector:8080/alertmanager; do
  out="$(client wget -q -O /dev/null --header 'Content-Type: application/json' \
    --post-data '{"alerts":[]}' "$url" 2>&1 || true)"
  grep -q ' 401 ' <<<"$out" || fail "the SMS webhook did not answer 401 to a request with no or a wrong password: $out"
done

# Records one minute old: inside the 15 minute windows whatever the
# evaluation delay of vmalert. The Authentik event has no client IP and the
# UniFi one no source: their SMS must leave out the missing label.
# Inserted with the _msg_field of vector's VictoriaLogs sink, so a journald
# body_message lands in _msg as in production, and _msg as the last choice
# for the records written here with _msg already.
msg_field="$(jq -r '.configs.vector_config.content' "$work_dir/compose.json" \
  | grep -o 'jsonline?_stream_fields=log_stream[^"]*' | grep -o '_msg_field=[^&]*')" \
  || fail "no _msg_field in the VictoriaLogs sink of vector"
record_time="$(date -u -d '-1 min' +%Y-%m-%dT%H:%M:%SZ)"
# Traefik: 5 errors in each of three 5-minute buckets. containerd: one
# container in a loop with Docker logs (its name), one without (its short
# id), and a GitLab runner helper that must not fire.
shim_a="$(printf 'a%.0s' {1..64})"
shim_b="$(printf 'b%.0s' {1..64})"
shim_r="$(printf 'c%.0s' {1..64})"
jq -cn --arg t "$record_time" --arg a "$shim_a" --arg b "$shim_b" --arg r "$shim_r" '
  {_time: $t, _msg: "vzdump job failed", log_stream: "proxmox", pve_backup_event: "job_failed"},
  {_time: $t, _msg: "acmerenew failed", log_stream: "proxmox", pve_task_failed: "true", pve_task_type: "acmerenew",
    pve_task_status: "Failed to initialize HTTP daemon"},
  {_time: $t, _msg: "qmstart failed", log_stream: "proxmox", pve_task_failed: "true", pve_task_type: "qmstart",
    pve_vmid: "101", pve_task_status: "start failed"},
  {_time: $t, log_stream: "journald", host_name: "pve.test", body_syslog_identifier: "kernel",
    body_message: "INFO: task kworker/0:1:123 blocked for more than 122 seconds."},
  {_time: $t, log_stream: "journald", host_name: "pve.test", body_syslog_identifier: "kernel",
    body_message: "Memory cgroup out of memory: Killed process 4242 (java) total-vm:1024kB, anon-rss:512kB"},
  ([$a, $b, $r][] as $id | range(5) | {_time: $t, log_stream: "journald", host_name: "docker.test",
    body_syslog_identifier: "containerd",
    body_message: "level=info msg=\"connecting to shim \($id)\" namespace=moby protocol=ttrpc version=3"}),
  {_time: $t, log_stream: "docker", host_name: "docker.test", container_id: $a, container_name: "app",
    body: "panic: config missing"},
  {_time: $t, log_stream: "docker", host_name: "docker.test", container_id: $r,
    container_name: "runner-x-project-1-concurrent-0-abc-predefined", body: "step"},
  (0, 5, 10 | . as $m | range(5) | {_time: ($t | fromdateiso8601 - $m * 60 | todateiso8601),
    log_stream: "traefik", app_servicename: "app@docker", app_downstreamstatus: "502", body: "GET /"}),
  {_time: $t, _msg: "suspicious request", log_stream: "authentik", ak_kind: "event", ak_action: "suspicious_request",
    ak_user: "akadmin"},
  {_time: $t, _msg: "CEF:0|Ubiquiti|UniFi Network|9.0|1|Threat detected|7|", log_stream: "syslog", appname: "CEF",
    cef_name: "Threat detected"}
' > "$work_dir/records.jsonl"
chmod a+r "$work_dir/records.jsonl"
docker run --rm --network "$network" -v "$work_dir/records.jsonl:/records.jsonl:ro" "$client_image" \
  wget -q -O /dev/null --header 'Content-Type: application/stream+json' --post-file /records.jsonl \
  'http://victorialogs:9428/insert/jsonline?_stream_fields=log_stream&'"$msg_field" || fail "ingestion refused"

logsql() {
  client wget -q -O - "http://victorialogs:9428/select/logsql/query?query=$(jq -rn --arg q "$1" '$q | @uri')"
}
stored=""
for _ in $(seq 1 15); do
  stored="$(logsql 'log_stream:in(proxmox, journald, authentik, syslog, docker, traefik)' | wc -l)"
  [[ "$stored" -eq 39 ]] && break
  sleep 1
done
[[ "$stored" -eq 39 ]] || fail "expected 39 records in VictoriaLogs, got $stored"

# vmalert last: its first evaluation finds the records.
docker run -d --name "$vmalert_name" --network "$network" --network-alias vmalert-logs \
  -v "$work_dir/logs_rules.yml:/etc/vmalert/rules.yml:ro" \
  "$vmalert_image" "${vmalert_logs_cmd[@]}" >/dev/null

deadline=$((SECONDS + timeout_s))
alerts=""
until [[ $SECONDS -ge $deadline ]]; do
  alerts="$(client wget -q -O - http://alertmanager:9093/api/v2/alerts 2>/dev/null || true)"
  if jq -e '[.[].labels.alertname] | index("proxmox_backup_failed") and index("proxmox_task_failed")
    and index("authentik_sensitive_event") and index("unifi_ips_event") and index("kernel_critical") and index("oom_kill")
    and index("container_restart_loop") and index("traefik_5xx_burst")' \
    <<<"${alerts:-[]}" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
jq -e '[.[] | select(.labels.alertname == "proxmox_backup_failed")] | length == 1' <<<"${alerts:-[]}" >/dev/null \
  || fail "proxmox_backup_failed not in Alertmanager: $alerts"
task_types="$(jq -c '[.[] | select(.labels.alertname == "proxmox_task_failed") | .labels.pve_task_type] | sort' <<<"$alerts")"
[[ "$task_types" == '["acmerenew","qmstart"]' ]] \
  || fail "proxmox_task_failed for $task_types, expected [\"acmerenew\",\"qmstart\"]"
loops="$(jq -c '[.[] | select(.labels.alertname == "container_restart_loop") | .labels.container_id[0:4]] | sort' <<<"$alerts")"
[[ "$loops" == '["aaaa","bbbb"]' ]] || fail "container_restart_loop for $loops, expected [\"aaaa\",\"bbbb\"]"

# One SMS per alertname (group_by), after group_wait, one line per alert. A
# task alert that joins its group late comes in a second SMS: compare the
# distinct lines of all the SMS bodies, sorted.
expected='["1 erreurs noyau critiques sur pve.test en 15 minutes","1 evenements IPS UniFi (Threat detected) en 15 minutes","15 erreurs 5xx de app@docker en 30 minutes","Conteneur app redemarre en boucle sur docker.test (5 demarrages en 15 minutes)","Conteneur bbbbbbbbbbbb redemarre en boucle sur docker.test (5 demarrages en 15 minutes)","Evenement Authentik sensible suspicious_request (1 en 5 minutes) pour akadmin","Processus java tue par manque de memoire sur pve.test (1 en 15 minutes)","Sauvegarde vzdump Proxmox en echec (job_failed, 1 en 15 minutes)","Tache Proxmox acmerenew en erreur (1 en 24 heures) : Failed to initialize HTTP daemon","Tache Proxmox qmstart VM 101 en erreur (1 en 24 heures) : start failed"]'
sms=""
messages=""
until [[ $SECONDS -ge $deadline ]]; do
  sms="$(logsql '{user="test-user"}' 2>/dev/null || true)"
  messages="$(jq -c -s '[.[]._msg | split("\n")[]] | unique' <<<"$sms" 2>/dev/null || true)"
  [[ "$messages" == "$expected" ]] && break
  sleep 2
done
[[ -n "$sms" ]] || fail "no SMS body reached the sink"
jq -e -s 'all(.[]; .pass == "test-pass")' <<<"$sms" >/dev/null || fail "SMS without the test credentials: $sms"
[[ "$messages" == "$expected" ]] || fail "SMS texts: expected $expected, got $messages"

# --- Watchdog. vmalert-metrics starts now, so the SMS above came from the
# log rules alone.
docker run -d --name "$vmalert_metrics_name" --network "$network" --network-alias vmalert-metrics \
  -v "$work_dir/metrics_rules.yml:/etc/vmalert/rules.yml:ro" \
  "$vmalert_image" "${vmalert_metrics_cmd[@]}" >/dev/null

promql() {
  client wget -q -O - "http://victoriametrics:8428/api/v1/query?query=$(jq -rn --arg q "$1" '$q | @uri')"
}
deadline=$((SECONDS + timeout_s))
jobs=""
until [[ $SECONDS -ge $deadline ]]; do
  jobs="$(promql 'up == 1' 2>/dev/null | jq -c '[.data.result[].metric.job] | sort' 2>/dev/null || true)"
  [[ "$jobs" == '["alertmanager","vector","victorialogs","victoriametrics","vmalert-logs","vmalert-metrics"]' ]] && break
  sleep 2
done
[[ "$jobs" == '["alertmanager","vector","victorialogs","victoriametrics","vmalert-logs","vmalert-metrics"]' ]] \
  || fail "jobs up: $jobs, expected the six components of the stack"

# The metric names and labels the victoria_stack rules use. The error
# counters are created at zero for every receiver and rule.
for q in 'alertmanager_notifications_failed_total{integration="webhook",receiver_name="watchdog"}' \
  'vmalert_alerting_rules_errors_total{job="vmalert-metrics",group="victoria_stack",alertname="watchdog"}' \
  'vmalert_alerting_rules_errors_total{job="vmalert-logs",alertname="proxmox_backup_failed"}' \
  'vmalert_alerts_send_errors_total{job="vmalert-logs"}' \
  'vmalert_alerts_send_errors_total{job="vmalert-metrics"}' \
  'vector_component_sent_events_total{component_id="free_mobile"}'; do
  found=""
  until [[ $SECONDS -ge $deadline ]]; do
    found="$(promql "$q" 2>/dev/null | jq '.data.result | length' 2>/dev/null || true)"
    [[ "${found:-0}" -ge 1 ]] && break
    sleep 2
  done
  [[ "${found:-0}" -ge 1 ]] || fail "no series for $q"
done

pushes=""
until [[ $SECONDS -ge $deadline ]]; do
  pushes="$(logsql '{receiver="watchdog"}' 2>/dev/null || true)"
  [[ -n "$pushes" ]] && break
  sleep 2
done
[[ -n "$pushes" ]] || fail "the watchdog did not reach its receiver"
jq -e -s 'all(.[]; ._msg == "firing")' <<<"$pushes" >/dev/null || fail "watchdog pushes not firing: $pushes"

# The Alertes dashboard: Vector polls both vmalert and writes one record per
# rule to log_stream "alerts", with the reason of its state as the message.
states=""
until [[ $SECONDS -ge $deadline ]]; do
  states="$(logsql '{log_stream="alerts"} | last 1 by (_time) partition by (alert_source, alert_rule)' 2>/dev/null || true)"
  jq -e -s '(map(select(.alert_rule == "proxmox_backup_failed" and .alert_state == "firing")) | length == 1)
    and (map(select(.alert_rule == "watchdog" and .alert_state == "firing" and .alert_source == "metrics")) | length == 1)' \
    <<<"${states:-}" >/dev/null 2>&1 && break
  sleep 2
done
jq -e -s 'map(select(.alert_rule == "proxmox_backup_failed"))[0]
  | .alert_source == "logs" and (._msg | startswith("Sauvegarde vzdump Proxmox en echec")) and .alert_active_since != null' \
  <<<"${states:-}" >/dev/null 2>&1 || fail "no firing proxmox_backup_failed record with its reason in the alerts stream: $states"
jq -e -s 'map(select(.alert_rule == "watchdog" and .alert_state == "firing" and .alert_source == "metrics")) | length == 1' \
  <<<"${states:-}" >/dev/null 2>&1 || fail "no firing watchdog record in the alerts stream: $states"
jq -e -s 'map(select(.alert_state == "inactive" and (._msg | startswith("Condition non remplie : ")))) | length >= 1' \
  <<<"$states" >/dev/null || fail "no inactive rule with its condition in the alerts stream"
rules="$(jq -s 'length' <<<"$states")"
expected_rules="$(cat "$work_dir/logs_rules.yml" "$work_dir/metrics_rules.yml" | grep -c '^ *- alert:')"
[[ "$rules" -eq "$expected_rules" ]] || fail "the alerts stream holds $rules rules, expected $expected_rules"

# Vector down: up{job="vector"} drops to 0 and the watchdog resolves.
docker stop "$vector_name" >/dev/null
deadline=$((SECONDS + timeout_s))
active=1
until [[ $SECONDS -ge $deadline ]]; do
  alerts="$(client wget -q -O - http://alertmanager:9093/api/v2/alerts 2>/dev/null || true)"
  if jq -e '[.[].labels.alertname] | index("watchdog") == null' <<<"${alerts:-[]}" >/dev/null 2>&1; then
    active=""
    break
  fi
  sleep 2
done
[[ -z "$active" ]] || fail "the watchdog still fires with Vector stopped"
pushes_after="$(logsql '{receiver="watchdog"}' 2>/dev/null || true)"
jq -e -s 'all(.[]; ._msg == "firing")' <<<"$pushes_after" >/dev/null \
  || fail "a resolved watchdog reached the receiver: $pushes_after"

echo "OK: rules parse, routes match the alerts, a Proxmox failure reaches the SMS sink, the Alertes dashboard records give each rule its reason, the watchdog stops with Vector"
