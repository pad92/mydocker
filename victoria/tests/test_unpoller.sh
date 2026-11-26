#!/usr/bin/env bash
# Scrape test for unpoller, on the config as Compose renders it with
# .env.example. VictoriaMetrics runs with its rendered command and the rendered
# victoriametrics_scrape file, on a throwaway internal network. A busybox HTTP
# server with the alias unpoller stands in for unpoller and serves a fixed
# metric on 9130. The test expects up{job="unpoller"} = 1 and the fixed value
# in VictoriaMetrics, which proves that VictoriaMetrics accepts the scrape
# config and that the job name, host and port match.
# One change in the test copy only, checked: scrape_interval 60s set to 5s.
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
client_image="${CLIENT_IMAGE:-busybox:1.37}"
timeout_s="${UNPOLLER_TIMEOUT:-60}"

suffix="$$-$RANDOM"
network="victoria-unpoller-test-$suffix"
metrics_name="victoriametrics-test-$suffix"
target_name="unpoller-test-$suffix"
work_dir="$(mktemp -d)"

cleanup() {
  docker rm -f "$metrics_name" "$target_name" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  if docker inspect "$metrics_name" >/dev/null 2>&1; then
    echo "--- $metrics_name logs" >&2
    docker logs "$metrics_name" 2>&1 | tail -n 20 >&2 || true
  fi
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

grep -q 'scrape_interval: 60s' "$work_dir/scrape.yml" || fail "scrape_interval is not 60s"
sed -i 's/scrape_interval: 60s/scrape_interval: 5s/' "$work_dir/scrape.yml"
grep -q 'scrape_interval: 5s' "$work_dir/scrape.yml" || fail "scrape_interval not patched"

mkdir "$work_dir/www"
printf '# TYPE unpoller_test_value gauge\nunpoller_test_value{site="test"} 4242\n' \
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

echo "OK"
