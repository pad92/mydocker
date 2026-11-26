#!/usr/bin/env bash
# Scrape test for unpoller, on the config as Compose renders it with
# .env.example. VictoriaMetrics runs with its rendered command and the rendered
# victoriametrics_scrape file, on a throwaway internal network. A busybox HTTP
# server with the alias unpoller stands in for unpoller and serves a fixed
# metric on 9130. The test expects up{job="unpoller"} = 1 and the fixed value
# in VictoriaMetrics, which proves that VictoriaMetrics accepts the scrape
# config and that the job name, host and port match.
#
# Then the alert unpoller_no_unifi_data: vmalert runs with its rendered command
# and the rendered vmalert_metrics_rules. While the stand-in serves
# unpoller_device_info, the rule must stay inactive for 3 evaluations. Once it
# serves only go_* metrics (what unpoller exports when it cannot log in to
# UniFi, up staying at 1), the alert must turn pending, with for: 10m as
# rendered, job="unpoller" and severity warning. Alertmanager is not started:
# a pending alert is not sent.
# Changes in the test copy only, checked: scrape_interval 60s and the interval
# of the unifi_metrics group (1m) set to 5s.
# Not covered: unpoller itself and the UniFi API (needs the gateway and the
# account, see the README for the check after deployment).
#
# Needs Docker, Docker Compose 2.23+ and jq; no published port, no Internet.
# Usage: ./tests/test_unpoller.sh
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="$stack_dir/.env.example"
version() { sed -n "s/^$1=//p" "$env_file"; }
metrics_image="victoriametrics/victoria-metrics:$(version VICTORIA_METRICS_VERSION)"
vmalert_image="victoriametrics/vmalert:$(version VMALERT_VERSION)"
client_image="${CLIENT_IMAGE:-busybox:1.37}"
timeout_s="${UNPOLLER_TIMEOUT:-60}"

suffix="$$-$RANDOM"
network="victoria-unpoller-test-$suffix"
metrics_name="victoriametrics-test-$suffix"
target_name="unpoller-test-$suffix"
vmalert_name="vmalert-metrics-test-$suffix"
work_dir="$(mktemp -d)"

cleanup() {
  docker rm -f "$vmalert_name" "$metrics_name" "$target_name" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  for name in "$metrics_name" "$vmalert_name"; do
    if docker inspect "$name" >/dev/null 2>&1; then
      echo "--- $name logs" >&2
      docker logs "$name" 2>&1 | tail -n 20 >&2 || true
    fi
  done
  exit 1
}

# --- Rendering: the command and scrape file VictoriaMetrics really receives.
PUID="${PUID:-1000}" PGID="${PGID:-1000}" docker compose \
  --project-directory "$stack_dir" --env-file "$env_file" \
  config --format json > "$work_dir/compose.json"
mapfile -t vm_cmd < <(jq -er '.services.victoriametrics.command[]' "$work_dir/compose.json")
scrape_target="$(jq -er '.services.victoriametrics.configs[]
  | select(.source == "victoriametrics_scrape") | .target' "$work_dir/compose.json")" \
  || fail "victoriametrics does not mount victoriametrics_scrape"
jq -er '.configs.victoriametrics_scrape.content' "$work_dir/compose.json" > "$work_dir/scrape.yml"
mapfile -t vmalert_cmd < <(jq -er '.services["vmalert-metrics"].command[]' "$work_dir/compose.json")
rules_target="$(jq -er '.services["vmalert-metrics"].configs[]
  | select(.source == "vmalert_metrics_rules") | .target' "$work_dir/compose.json")" \
  || fail "vmalert-metrics does not mount vmalert_metrics_rules"
# compose config writes a literal $ as $$; the container gets $.
jq -er '.configs.vmalert_metrics_rules.content | gsub("\\$\\$"; "$")' \
  "$work_dir/compose.json" > "$work_dir/rules.yml"

grep -q 'scrape_interval: 60s' "$work_dir/scrape.yml" || fail "scrape_interval is not 60s"
sed -i 's/scrape_interval: 60s/scrape_interval: 5s/' "$work_dir/scrape.yml"
grep -q 'scrape_interval: 5s' "$work_dir/scrape.yml" || fail "scrape_interval not patched"
grep -A1 -- '- name: unifi_metrics' "$work_dir/rules.yml" | grep -q 'interval: 1m' \
  || fail "group unifi_metrics missing or its interval is not 1m"
sed -i '/- name: unifi_metrics/{n;s/interval: 1m/interval: 5s/}' "$work_dir/rules.yml"
grep -A1 -- '- name: unifi_metrics' "$work_dir/rules.yml" | grep -q 'interval: 5s' \
  || fail "unifi_metrics interval not patched"

mkdir "$work_dir/www"
# unpoller logged in to UniFi: a device, and the fixed value.
printf '%s\n' '# TYPE unpoller_test_value gauge' 'unpoller_test_value{site="test"} 4242' \
  '# TYPE unpoller_device_info gauge' \
  'unpoller_device_info{site_name="test",name="gw",type="udm"} 1' \
  > "$work_dir/www/metrics"
chmod -R a+rX "$work_dir"

# --- Containers. The data path of the rendered command goes to a tmpfs.
docker network create --internal "$network" >/dev/null
docker run -d --name "$target_name" --network "$network" --network-alias unpoller \
  -v "$work_dir/www:/www:ro" "$client_image" httpd -f -p 9130 -h /www >/dev/null
docker run -d --name "$metrics_name" --network "$network" --network-alias victoriametrics \
  --tmpfs /data -v "$work_dir/scrape.yml:$scrape_target:ro" \
  "$metrics_image" "${vm_cmd[@]}" >/dev/null

client() { docker run --rm --network "$network" "$client_image" "$@"; }
query() {
  client wget -qO- "http://victoriametrics:8428/api/v1/query?query=$1" 2>/dev/null \
    | jq -r '.data.result[0].value[1] // empty'
}

up="" value=""
for _ in $(seq 1 "$timeout_s"); do
  docker inspect -f '{{.State.Running}}' "$metrics_name" 2>/dev/null | grep -q true \
    || fail "victoriametrics stopped (scrape config refused?)"
  up="$(query 'up%7Bjob%3D%22unpoller%22%2Cinstance%3D%22unpoller%3A9130%22%7D' || true)"
  value="$(query 'unpoller_test_value%7Bjob%3D%22unpoller%22%7D' || true)"
  [ "$up" = 1 ] && [ "$value" = 4242 ] && break
  sleep 1
done
[ "$up" = 1 ] || fail "up{job=\"unpoller\",instance=\"unpoller:9130\"} is '$up', expected 1"
[ "$value" = 4242 ] || fail "unpoller_test_value is '$value', expected 4242"

# --- Alert. vmalert gets the rendered command; alertmanager does not exist on
# this network, which only matters for a firing alert.
docker run -d --name "$vmalert_name" --network "$network" \
  -v "$work_dir/rules.yml:$rules_target:ro" \
  "$vmalert_image" "${vmalert_cmd[@]}" >/dev/null

# state and lastEvaluation of the rule, empty if vmalert does not have it.
rule_state() {
  client wget -qO- "http://$vmalert_name:8880/api/v1/rules" 2>/dev/null \
    | jq -r '.data.groups[] | select(.name == "unifi_metrics") | .rules[]
        | select(.name == "unpoller_no_unifi_data")
        | "\(.state) \(.lastEvaluation) \(.duration)"' || true
}

# Phase 1, data present: 3 evaluations in a row inactive. The first ones may
# be pending, while vmalert evaluates before the first samples (eval delay).
inactive=0 last="" state=""
for _ in $(seq 1 "$((timeout_s * 2))"); do
  docker inspect -f '{{.State.Running}}' "$vmalert_name" 2>/dev/null | grep -q true \
    || fail "vmalert stopped (rules refused?)"
  read -r state eval_at duration <<< "$(rule_state)" || true
  if [ -n "${eval_at:-}" ] && [ "$eval_at" != "$last" ]; then
    last="$eval_at"
    if [ "$state" = inactive ]; then inactive=$((inactive + 1)); else inactive=0; fi
    [ "$inactive" -ge 3 ] && break
  fi
  sleep 1
done
[ "$inactive" -ge 3 ] \
  || fail "with unpoller_device_info served, rule state is '$state' ($inactive inactive evaluations), expected inactive"
[ "$duration" = 600 ] || fail "rule for is '$duration' s, expected 600 (10m)"

# Phase 2, unpoller without UniFi data: only go_* metrics, up stays 1.
printf '%s\n' '# TYPE go_goroutines gauge' 'go_goroutines 12' > "$work_dir/www/metrics.new"
chmod a+r "$work_dir/www/metrics.new"
mv "$work_dir/www/metrics.new" "$work_dir/www/metrics"

alert=""
for _ in $(seq 1 "$((timeout_s * 2))"); do
  alert="$(client wget -qO- "http://$vmalert_name:8880/api/v1/alerts" 2>/dev/null \
    | jq -c '.data.alerts[] | select(.name == "unpoller_no_unifi_data")
        | {state, job: .labels.job, severity: .labels.severity}' || true)"
  [ -n "$alert" ] && break
  sleep 1
done
[ -n "$alert" ] || fail "no unpoller_no_unifi_data alert with only go_* metrics served"
[ "$alert" = '{"state":"pending","job":"unpoller","severity":"warning"}' ] \
  || fail "alert is $alert, expected pending, job unpoller, severity warning"
up="$(query 'up%7Bjob%3D%22unpoller%22%2Cinstance%3D%22unpoller%3A9130%22%7D' || true)"
[ "$up" = 1 ] || fail "up is '$up' in phase 2, expected 1 (the case the alert is for)"

echo "OK"
