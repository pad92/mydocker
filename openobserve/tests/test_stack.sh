#!/usr/bin/env bash
# Static checks on the OpenObserve Traefik routers, as Compose renders them
# with .env.example (nothing is started):
# - the HTTPS router is behind Authentik forward auth (first middleware);
# - the ingestion bypass router matches only POST on the ingestion endpoints
#   of the OpenObserve host, has no middleware and targets OpenObserve;
# - its path regex accepts the ingestion paths and rejects the UI, the query
#   API and look-alike paths (matched like Traefik: unanchored search, so the
#   ^ and $ anchors are what keeps it narrow);
# - the health check bypass router matches only GET/HEAD on /healthz of the
#   OpenObserve host, has no middleware and targets OpenObserve (Uptime Kuma
#   cannot follow a browser login);
# - every other router on the host carries the middleware, except the HTTP
#   to HTTPS redirect.
# Needs Docker Compose 2.23+, jq and python3. Usage: ./tests/test_stack.sh
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
host="$(sed -n 's/^OPENOBSERVE_DOMAIN=//p' "$stack_dir/.env.example")"

fail() { echo "FAIL: $*" >&2; exit 1; }

# PUID/PGID are empty in .env.example but required by the compose file.
config="$(PUID=1000 PGID=1000 docker compose --project-directory "$stack_dir" \
  --env-file "$stack_dir/.env.example" config --format json)"
labels='.services.openobserve.labels'
label() { jq -r "$labels[\"$1\"] // \"\"" <<<"$config"; }

label traefik.http.routers.openobserve.middlewares | grep -q '^authentik@docker' \
  || fail "OpenObserve router is not behind forward auth (first middleware)"

ingest='traefik.http.routers.openobserve_ingest'
rule="$(label "$ingest.rule")"
prefix="Host(\`$host\`) && Method(\`POST\`) && PathRegexp(\`"
case "$rule" in
  "$prefix"*'`)') ;;
  *) fail "ingest router is not limited to POST on the OpenObserve host: $rule" ;;
esac
regex="${rule#"$prefix"}"
regex="${regex%'`)'}"
# "compose config" escapes $ as $$ in its output; the container label (what
# Traefik reads) holds a single $.
regex="${regex//\$\$/\$}"
[ -z "$(label "$ingest.middlewares")" ] \
  || fail "ingest router has a middleware: senders would need a browser login"
[ "$(label "$ingest.service")" = openobserve ] \
  || fail "ingest router does not target the OpenObserve service"
[ "$(label "$ingest.entrypoints")" = websecure ] \
  || fail "ingest router is not on the HTTPS entry point"

# Go regexp (Traefik) and Python re agree on this syntax: groups, classes,
# alternation and anchors only.
python3 -I - "$regex" <<'EOF' || fail "ingest path regex is too wide or too narrow"
import re, sys
r = re.compile(sys.argv[1])
allowed = [
    "/api/default/syslog/_json",
    "/api/default/firewall/_multi",
    "/api/default/_bulk",
    "/api/default/v1/logs",
    "/api/default/v1/metrics",
    "/api/default/v1/traces",
    "/api/default/prometheus/api/v1/write",
]
denied = [
    "/", "/web/", "/web/logs", "/auth/login",
    "/api/default/_search",
    "/api/default/syslog/_search",
    "/api/default/streams",
    "/api/default/users",
    "/api/default/syslog/_json/extra",
    "/api/default/_bulk/../users",
    "/x/api/default/_bulk",
    "/api/default/a/b/_json",
    "/api/default/v1/logsx",
    "/api/default/prometheus/api/v1/query",
    "/api//_bulk",
]
bad = [p for p in allowed if not r.search(p)] + [p for p in denied if r.search(p)]
for p in bad:
    print("misclassified:", p, file=sys.stderr)
sys.exit(1 if bad else 0)
EOF

health='traefik.http.routers.openobserve_health'
[ "$(label "$health.rule")" = "Host(\`$host\`) && (Method(\`GET\`) || Method(\`HEAD\`)) && Path(\`/healthz\`)" ] \
  || fail "health router is not limited to GET/HEAD /healthz on the OpenObserve host: $(label "$health.rule")"
[ -z "$(label "$health.middlewares")" ] \
  || fail "health router has a middleware: Uptime Kuma would get a 302 to Authentik"
[ "$(label "$health.service")" = openobserve ] \
  || fail "health router does not target the OpenObserve service"
[ "$(label "$health.entrypoints")" = websecure ] \
  || fail "health router is not on the HTTPS entry point"

# Every router on the host other than the HTTP redirect and the ingest and
# health check bypasses must carry the middleware.
routers="$(jq -r "$labels | to_entries[] | select(.key | test(\"^traefik.http.routers.[^.]+.rule$\"))
  | select(.value | contains(\"$host\")) | .key | split(\".\")[3]" <<<"$config")"
[ -n "$routers" ] || fail "no router found on the OpenObserve host"
for router in $routers; do
  case "$router" in openobserve_http|openobserve_ingest|openobserve_health) continue ;; esac
  label "traefik.http.routers.$router.middlewares" | grep -q '^authentik@docker' \
    || fail "OpenObserve router $router bypasses forward auth"
done

echo "OK"
