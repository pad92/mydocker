#!/usr/bin/env bash
# Test of the Synology SNMPv3 path, on the config as Compose renders it with
# .env.example. Two parts, on a throwaway internal network:
#
# 1. The real snmp-exporter image runs with its rendered command and the
#    rendered snmp_exporter_auth file, with test values in its environment.
#    /config must show the test username (so the ${...} references reach the
#    exporter unexpanded by Compose and the exporter expands them) and must
#    not show the test passwords. A probe with the modules and auth of the
#    synology job must get past the name checks (500, as the target is
#    unreachable), while a wrong module or auth name must get 400.
# 2. VictoriaMetrics runs with its rendered command and scrape file. A busybox
#    nc server with the alias snmp-exporter logs the request line and answers
#    with a fixed metric on 9116. The test expects up{job="synology"} = 1 with
#    instance = the NAS, the fixed value stored, and a request to /snmp with
#    the NAS as target, the three modules and the synology_v3 auth.
# Changes in the test copy only, checked: scrape_interval 60s and
# scrape_timeout 30s of the synology job set to 5s.
# Not covered: SNMPv3 against the NAS (needs the NAS and the passwords, see
# the README for the check after deployment).
#
# Needs Docker, Docker Compose 2.23+ and jq; no published port, no Internet.
# Usage: ./tests/test_synology.sh
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="$stack_dir/.env.example"
version() { sed -n "s/^$1=//p" "$env_file"; }
metrics_image="victoriametrics/victoria-metrics:$(version VICTORIA_METRICS_VERSION)"
client_image="${CLIENT_IMAGE:-busybox:1.37}"
timeout_s="${SYNOLOGY_TIMEOUT:-60}"

suffix="$$-$RANDOM"
network="victoria-synology-test-$suffix"
exporter_name="snmp-exporter-test-$suffix"
metrics_name="victoriametrics-test-$suffix"
target_name="snmp-fake-test-$suffix"
work_dir="$(mktemp -d)"
test_user="test-user-$suffix"
test_auth_pass="test-auth-pass-$suffix"
test_priv_pass="test-priv-pass-$suffix"

cleanup() {
  docker rm -f "$exporter_name" "$metrics_name" "$target_name" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  for name in "$exporter_name" "$metrics_name"; do
    if docker inspect "$name" >/dev/null 2>&1; then
      echo "--- $name logs" >&2
      docker logs "$name" 2>&1 | tail -n 20 >&2 || true
    fi
  done
  exit 1
}

# --- Rendering. "compose config" escapes every literal $ as $$ again in its
# output; the gsub gives back the file the container really receives.
PUID="${PUID:-1000}" PGID="${PGID:-1000}" docker compose \
  --project-directory "$stack_dir" --env-file "$env_file" \
  config --format json > "$work_dir/compose.json"
exporter() { jq -er ".services[\"snmp-exporter\"]$1" "$work_dir/compose.json"; }
exporter_image="$(exporter .image)"
mapfile -t exporter_cmd < <(exporter '.command[]')
auth_target="$(exporter '.configs[] | select(.source == "snmp_exporter_auth") | .target')" \
  || fail "snmp-exporter does not mount snmp_exporter_auth"
jq -er '.configs.snmp_exporter_auth.content | gsub("\\$\\$"; "$")' \
  "$work_dir/compose.json" > "$work_dir/auth.yml"
# The variable names the auth file references must be the ones Compose sets.
for var in $(grep -o '\${[A-Z_]*}' "$work_dir/auth.yml" | tr -d '${}'); do
  exporter ".environment | has(\"$var\")" | grep -q true \
    || fail "auth.yml references \${$var}, not in the snmp-exporter environment"
done

mapfile -t vm_cmd < <(jq -er '.services.victoriametrics.command[]' "$work_dir/compose.json")
scrape_target="$(jq -er '.services.victoriametrics.configs[]
  | select(.source == "victoriametrics_scrape") | .target' "$work_dir/compose.json")" \
  || fail "victoriametrics does not mount victoriametrics_scrape"
jq -er '.configs.victoriametrics_scrape.content' "$work_dir/compose.json" > "$work_dir/scrape.yml"
nas="$(sed -n 's/^SYNOLOGY_SNMP_TARGET=//p' "$env_file")"
[ -n "$nas" ] || fail "SYNOLOGY_SNMP_TARGET is empty in .env.example"

# Only the synology job gets the shorter interval and timeout.
awk '/job_name: synology/ {s=1} /job_name:/ && !/synology/ {s=0}
  s && /scrape_interval: 60s/ {sub(/60s/, "5s"); n++}
  s && /scrape_timeout: 30s/ {sub(/30s/, "5s"); n++}
  {print} END {exit n != 2}' "$work_dir/scrape.yml" > "$work_dir/scrape.test.yml" \
  || fail "synology job has no scrape_interval 60s and scrape_timeout 30s"
mv "$work_dir/scrape.test.yml" "$work_dir/scrape.yml"

# Fake exporter: logs the request line, answers with a fixed metric.
mkdir "$work_dir/fake"
cat > "$work_dir/fake/handler.sh" <<'EOF'
#!/bin/sh
read -r line
printf '%s\n' "$line" >> /tmp/requests
while read -r header; do
  [ -z "$(printf '%s' "$header" | tr -d '\r')" ] && break
done
body='# TYPE snmp_test_value gauge
snmp_test_value 4242
'
printf 'HTTP/1.0 200 OK\r\nContent-Type: text/plain\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' \
  "${#body}" "$body"
EOF
chmod -R a+rX "$work_dir"
chmod a+x "$work_dir/fake/handler.sh"

docker network create --internal "$network" >/dev/null
client() { docker run --rm --network "$network" "$client_image" "$@"; }

# --- Part 1: the real exporter.
docker run -d --name "$exporter_name" --network "$network" --network-alias snmp-exporter-real \
  --user 65534:65534 \
  -e SNMP_USER="$test_user" -e SNMP_AUTH_PASS="$test_auth_pass" -e SNMP_PRIV_PASS="$test_priv_pass" \
  -v "$work_dir/auth.yml:$auth_target:ro" \
  "$exporter_image" "${exporter_cmd[@]}" >/dev/null

config=""
for _ in $(seq 1 "$timeout_s"); do
  docker inspect -f '{{.State.Running}}' "$exporter_name" 2>/dev/null | grep -q true \
    || fail "snmp-exporter stopped (config refused?)"
  config="$(client wget -qO- http://snmp-exporter-real:9116/config 2>/dev/null || true)"
  [ -n "$config" ] && break
  sleep 1
done
[ -n "$config" ] || fail "snmp-exporter /config did not answer"
grep -q "username: $test_user\$" <<<"$config" \
  || fail "/config has no 'username: $test_user' (env not expanded?)"
if grep -qe "$test_auth_pass" -e "$test_priv_pass" <<<"$config"; then
  fail "/config shows a password in clear"
fi

params="$(jq -er '.configs.victoriametrics_scrape.content' "$work_dir/compose.json" \
  | awk '/job_name: synology/ {s=1} s && /module:/ {gsub(/.*\[|\].*| /, ""); m=$0}
         s && /auth:/ {gsub(/.*\[|\].*| /, ""); a=$0} END {print "module=" m "&auth=" a}')"
# The exporter checks module and auth names first (400 when unknown), then
# polls the target. 192.0.2.1 is unreachable from the internal network, so a
# known module and auth give 500 at once. Busybox wget shows the status line
# only, not the body.
probe() {
  client wget -S -T 30 --header 'X-Prometheus-Scrape-Timeout-Seconds: 5' -O- \
    "http://snmp-exporter-real:9116/snmp?target=192.0.2.1&$1" 2>&1 \
    | sed -n 's/^ *HTTP\/1\.1 \([0-9]*\).*/\1/p' | head -n 1 || true
}
status="$(probe "module=no_such_module&auth=synology_v3")"
[ "$status" = 400 ] || fail "probe with a wrong module got '$status', expected 400"
status="$(probe "module=system&auth=no_such_auth")"
[ "$status" = 400 ] || fail "probe with a wrong auth got '$status', expected 400"
status="$(probe "$params")"
[ "$status" = 500 ] || fail "probe with $params got '$status', expected 500 (names known, NAS unreachable)"

# --- Part 2: VictoriaMetrics against the fake exporter.
docker run -d --name "$target_name" --network "$network" --network-alias snmp-exporter \
  -v "$work_dir/fake:/srv:ro" "$client_image" nc -lk -p 9116 -e /srv/handler.sh >/dev/null
docker run -d --name "$metrics_name" --network "$network" --network-alias victoriametrics \
  --tmpfs /data -v "$work_dir/scrape.yml:$scrape_target:ro" \
  "$metrics_image" "${vm_cmd[@]}" >/dev/null

query() {
  client wget -qO- "http://victoriametrics:8428/api/v1/query?query=$1" 2>/dev/null \
    | jq -r '.data.result[0].value[1] // empty'
}
up="" value=""
for _ in $(seq 1 "$timeout_s"); do
  docker inspect -f '{{.State.Running}}' "$metrics_name" 2>/dev/null | grep -q true \
    || fail "victoriametrics stopped (scrape config refused?)"
  up="$(query "up%7Bjob%3D%22synology%22%2Cinstance%3D%22$nas%22%7D" || true)"
  value="$(query 'snmp_test_value%7Bjob%3D%22synology%22%7D' || true)"
  [ "$up" = 1 ] && [ "$value" = 4242 ] && break
  sleep 1
done
[ "$up" = 1 ] || fail "up{job=\"synology\",instance=\"$nas\"} is '$up', expected 1"
[ "$value" = 4242 ] || fail "snmp_test_value is '$value', expected 4242"

request="$(docker exec "$target_name" head -n 1 /tmp/requests)"
case "$request" in
  "GET /snmp?"*) ;;
  *) fail "request is not GET /snmp?...: $request" ;;
esac
for param in "target=$nas" module=system module=if_mib module=synology auth=synology_v3; do
  grep -Eq "[?&]$param(&| )" <<<"$request" || fail "request has no $param: $request"
done

echo "OK"
