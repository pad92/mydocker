#!/usr/bin/env bash
# Static checks on the exposure of the victoria stack, as Compose renders it
# with .env.example (nothing is started):
# - the UI routers of the logs and metrics hosts are behind Authentik forward
#   auth (first middleware, so they fail closed);
# - the two ingestion bypass routers match only POST on their one OTLP path,
#   carry the victoria-ingest-auth@file Basic auth and nothing else, and
#   target the right service (logs to vector, metrics to victoriametrics);
# - the health check bypass routers match only GET/HEAD /health and target
#   the database of their host;
# - every other router on the two hosts, in any service, carries the forward
#   auth middleware, except the HTTP to HTTPS redirects;
# - no service publishes a host port except vector, which publishes only the
#   UDP syslog port: 9428, 8428 and 4318 have no authentication of their own;
# - the victoria-ingest-auth middleware exists in the Traefik file provider
#   template (management stack) as Basic auth that drops the Authorization
#   header before the backend.
# Needs Docker Compose 2.23+, jq and python3.11+. Usage: ./tests/test_stack.sh
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_value() { sed -n "s/^$1=//p" "$stack_dir/.env.example"; }
logs_host="$(env_value VICTORIA_LOGS_DOMAIN)"
metrics_host="$(env_value VICTORIA_METRICS_DOMAIN)"
[ -n "$logs_host" ] && [ -n "$metrics_host" ] || { echo "FAIL: domains missing in .env.example" >&2; exit 1; }

fail() { echo "FAIL: $*" >&2; exit 1; }

# PUID/PGID are empty in .env.example but required by the compose file.
config="$(PUID=1000 PGID=1000 docker compose --project-directory "$stack_dir" \
  --env-file "$stack_dir/.env.example" config --format json)"
# Router labels of every service, as "service<TAB>key<TAB>value".
all_labels="$(jq -r '.services | to_entries[] | .key as $s
  | (.value.labels // {}) | to_entries[] | [$s, .key, .value] | @tsv' <<<"$config")"
# Value of a label, wherever it is defined (router names are unique).
label() { awk -F'\t' -v k="$1" '$2 == k { print $3 }' <<<"$all_labels"; }
# Service that carries a label.
owner() { awk -F'\t' -v k="$1" '$2 == k { print $1 }' <<<"$all_labels"; }

for ui in victorialogs victoriametrics; do
  label "traefik.http.routers.$ui.middlewares" | grep -q '^authentik@docker' \
    || fail "$ui UI router is not behind forward auth (first middleware)"
done

# check_bypass <router> <rule> <middlewares> <service> <container>
check_bypass() {
  local r="traefik.http.routers.$1"
  [ "$(label "$r.rule")" = "$2" ] \
    || fail "$1 rule is wider or other than expected: $(label "$r.rule")"
  [ "$(label "$r.middlewares")" = "$3" ] \
    || fail "$1 middlewares are '$(label "$r.middlewares")', expected '$3'"
  [ "$(label "$r.service")" = "$4" ] || fail "$1 does not target the $4 service"
  [ "$(owner "$r.rule")" = "$5" ] || fail "$1 is not defined on the $5 container"
  [ "$(label "$r.entrypoints")" = websecure ] || fail "$1 is not on the HTTPS entry point"
}
check_bypass vector_ingest \
  "Host(\`$logs_host\`) && Method(\`POST\`) && Path(\`/v1/logs\`)" \
  victoria-ingest-auth@file vector vector
check_bypass victoriametrics_ingest \
  "Host(\`$metrics_host\`) && Method(\`POST\`) && Path(\`/opentelemetry/v1/metrics\`)" \
  victoria-ingest-auth@file victoriametrics victoriametrics
check_bypass victorialogs_health \
  "Host(\`$logs_host\`) && (Method(\`GET\`) || Method(\`HEAD\`)) && Path(\`/health\`)" \
  "" victorialogs victorialogs
check_bypass victoriametrics_health \
  "Host(\`$metrics_host\`) && (Method(\`GET\`) || Method(\`HEAD\`)) && Path(\`/health\`)" \
  "" victoriametrics victoriametrics

# Every router on the two hosts, whatever the service, other than the HTTP
# redirects and the bypasses checked above, must carry forward auth.
routers="$(awk -F'\t' -v l="$logs_host" -v m="$metrics_host" '
  $2 ~ /^traefik\.http\.routers\.[^.]+\.rule$/ && (index($3, l) || index($3, m)) {
    split($2, p, "."); print p[4] }' <<<"$all_labels")"
[ "$(wc -w <<<"$routers")" -ge 8 ] || fail "fewer routers than expected on the two hosts: $routers"
for router in $routers; do
  case "$router" in
    victorialogs_http|victoriametrics_http)
      [ "$(label "traefik.http.routers.$router.entrypoints")" = web ] \
        || fail "$router is not limited to the HTTP entry point"
      [ "$(label "traefik.http.routers.$router.middlewares")" = redirect-https ] \
        || fail "$router does not only redirect to HTTPS"
      continue ;;
    vector_ingest|victoriametrics_ingest|victorialogs_health|victoriametrics_health) continue ;;
  esac
  label "traefik.http.routers.$router.middlewares" | grep -q '^authentik@docker' \
    || fail "router $router bypasses forward auth"
done

# Published ports: only vector, only the syslog port, only UDP.
ports="$(jq -c '[.services | to_entries[] | select(.value.ports) | .key as $s
  | .value.ports[] | {s: $s, target, protocol, published}]' <<<"$config")"
[ "$ports" = "[{\"s\":\"vector\",\"target\":5514,\"protocol\":\"udp\",\"published\":\"$(env_value VECTOR_SYSLOG_PORT)\"}]" ] \
  || fail "unexpected published ports: $ports"

python3 -I - "$stack_dir/../management/traefik_dynamic.toml.example" <<'EOF' \
  || fail "victoria-ingest-auth is missing or not a header-removing Basic auth in traefik_dynamic.toml.example"
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    mw = tomllib.load(f)["http"]["middlewares"].get("victoria-ingest-auth", {})
ba = mw.get("basicAuth", {})
ok = set(mw) == {"basicAuth"} and ba.get("removeHeader") is True and bool(ba.get("users"))
sys.exit(0 if ok else 1)
EOF

echo "OK"
