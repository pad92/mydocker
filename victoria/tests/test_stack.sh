#!/usr/bin/env bash
# Static checks on the exposure of the victoria stack, as Compose renders it
# with .env.example (nothing is started):
# - the UI routers of the logs, metrics and Grafana hosts are behind
#   Authentik forward auth (first middleware, so they fail closed);
# - the two ingestion bypass routers match only POST on their one OTLP path,
#   carry the victoria-ingest-auth@file Basic auth and nothing else, and
#   target the right service (logs to vector, metrics to victoriametrics);
# - the health check bypass routers match only GET/HEAD /health and target
#   the database of their host;
# - every other router on the three hosts, in any service, carries the forward
#   auth middleware, except the HTTP to HTTPS redirects;
# - Grafana trusts only the X-authentik-username header (auth proxy) and has
#   no other way in: login form, basic auth and anonymous access are off;
# - vmalert-logs, vmalert-metrics and alertmanager have no Traefik label and
#   no port; the two vmalert join only the victoria network, which is
#   internal; alertmanager joins victoria and the alertmanager network (its
#   route out to the Uptime Kuma push URL, which only it joins) and gets the
#   host CA bundle read-only; the watchdog URL has no value in .env.example
#   beyond the CHANGE_ME placeholder;
# - unpoller has no Traefik label and no port, runs as 65534, verifies TLS
#   with the host CA bundle, has InfluxDB and DPI off and no password in
#   .env.example; it alone joins the unpoller network (the route out);
# - snmp-exporter has no Traefik label and no port, runs as 65534, joins only
#   the snmp network (its route out, which only it joins) and victoria, and
#   polls the NAS with SNMPv3 authPriv (SHA, AES); its passwords are empty in
#   .env.example and reach the auth file as ${...} references that the
#   exporter expands, never as values written into the compose file;
# - victoriametrics loads the scrape config that targets unpoller:9130,
#   sends the synology job to snmp-exporter:9116, and scrapes every component
#   of the stack (vector on its prometheus_exporter sink, 9598);
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
grafana_host="$(env_value VICTORIA_GRAFANA_DOMAIN)"
[ -n "$logs_host" ] && [ -n "$metrics_host" ] && [ -n "$grafana_host" ] \
  || { echo "FAIL: domains missing in .env.example" >&2; exit 1; }

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

for ui in victorialogs victoriametrics victoria_grafana; do
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

[ "$(label traefik.http.routers.victoria_grafana.rule)" = "Host(\`$grafana_host\`)" ] \
  || fail "victoria_grafana rule is other than the Grafana host"
[ "$(owner traefik.http.routers.victoria_grafana.rule)" = grafana ] \
  || fail "victoria_grafana is not defined on the grafana container"
[ "$(label traefik.http.routers.victoria_grafana.entrypoints)" = websecure ] \
  || fail "victoria_grafana is not on the HTTPS entry point"

# Every router on the three hosts, whatever the service, other than the HTTP
# redirects and the bypasses checked above, must carry forward auth.
routers="$(awk -F'\t' -v l="$logs_host" -v m="$metrics_host" -v g="$grafana_host" '
  $2 ~ /^traefik\.http\.routers\.[^.]+\.rule$/ && (index($3, l) || index($3, m) || index($3, g)) {
    split($2, p, "."); print p[4] }' <<<"$all_labels")"
[ "$(wc -w <<<"$routers")" -ge 10 ] || fail "fewer routers than expected on the three hosts: $routers"
for router in $routers; do
  case "$router" in
    victorialogs_http|victoriametrics_http|victoria_grafana_http)
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

# Grafana auth proxy: the header set by the Authentik outpost is the only way
# in. Any other enabled login would be reachable through the forward auth.
grafana_env() { jq -r --arg k "$1" '.services.grafana.environment[$k] // ""' <<<"$config"; }
[ "$(grafana_env GF_AUTH_PROXY_ENABLED)" = true ] || fail "Grafana auth proxy is off"
[ "$(grafana_env GF_AUTH_PROXY_HEADER_NAME)" = X-authentik-username ] \
  || fail "Grafana trusts another header: $(grafana_env GF_AUTH_PROXY_HEADER_NAME)"
[ "$(grafana_env GF_AUTH_DISABLE_LOGIN_FORM)" = true ] || fail "Grafana login form is on"
# DISABLE_LOGIN also disables auth.proxy: Grafana 13.2 answers 500 to every
# proxied request (seen by test_dashboards.sh).
[ "$(grafana_env GF_AUTH_DISABLE_LOGIN)" != true ] \
  || fail "GF_AUTH_DISABLE_LOGIN=true breaks the Grafana auth proxy"
for k in GF_AUTH_BASIC_ENABLED GF_AUTH_ANONYMOUS_ENABLED GF_AUTH_PROXY_ENABLE_LOGIN_TOKEN; do
  [ "$(grafana_env "$k")" = false ] || fail "Grafana $k is not false"
done

# Alerting services: reachable from the victoria network only.
for s in vmalert-logs vmalert-metrics; do
  jq -e --arg s "$s" '.services[$s] | ((.labels // {}) | length) == 0
    and ((.ports // []) | length) == 0 and ((.expose // []) | length) == 0
    and (.networks | keys) == ["victoria"]' <<<"$config" >/dev/null \
    || fail "$s has labels, ports or a network other than victoria"
done
jq -e '.networks.victoria.internal == true' <<<"$config" >/dev/null \
  || fail "the victoria network is not internal"
# alertmanager: same, plus the alertmanager network, which only it joins, as
# the route out to the Uptime Kuma push URL (watchdog receiver).
jq -e '.services.alertmanager | ((.labels // {}) | length) == 0
  and ((.ports // []) | length) == 0 and ((.expose // []) | length) == 0
  and (.networks | keys) == ["alertmanager", "victoria"]' <<<"$config" >/dev/null \
  || fail "alertmanager has labels, ports or unexpected networks"
on_am_net="$(jq -c '[.services | to_entries[]
  | select((.value.networks // {}) | has("alertmanager")) | .key]' <<<"$config")"
[ "$on_am_net" = '["alertmanager"]' ] || fail "services on the alertmanager network: $on_am_net"
jq -e '.networks.alertmanager["internal"] != true' <<<"$config" >/dev/null \
  || fail "the alertmanager network is internal: the watchdog cannot reach Uptime Kuma"
jq -e '.services.alertmanager.volumes | any(.type == "bind"
  and .source == "/etc/ssl/certs/ca-certificates.crt"
  and .target == "/etc/ssl/certs/ca-certificates.crt" and .read_only == true)' \
  <<<"$config" >/dev/null || fail "alertmanager does not get the host CA bundle read-only"
# The push token belongs in the environment of the stack only.
grep -qx 'ALERTMANAGER_WATCHDOG_URL=https://uptime.example.com/api/push/CHANGE_ME?status=up&msg=OK' \
  "$stack_dir/.env.example" || fail "ALERTMANAGER_WATCHDOG_URL in .env.example is not the placeholder"

# unpoller: no Traefik label, no port, the victoria network for the scrape and
# the unpoller network, which only it joins, for the route to the gateway.
jq -e '.services.unpoller | ((.labels // {}) | length) == 0
  and ((.ports // []) | length) == 0 and ((.expose // []) | length) == 0
  and (.networks | keys) == ["unpoller", "victoria"]' <<<"$config" >/dev/null \
  || fail "unpoller has labels, ports or unexpected networks"
on_unpoller_net="$(jq -c '[.services | to_entries[]
  | select((.value.networks // {}) | has("unpoller")) | .key]' <<<"$config")"
[ "$on_unpoller_net" = '["unpoller"]' ] \
  || fail "services on the unpoller network: $on_unpoller_net"
jq -e '.networks.unpoller.internal != true' <<<"$config" >/dev/null \
  || fail "the unpoller network is internal: unpoller cannot reach the gateway"
[ "$(jq -r '.services.unpoller.user' <<<"$config")" = "65534:65534" ] \
  || fail "unpoller does not run as 65534:65534"
# The image config has verify_ssl = false and InfluxDB on.
unpoller_env() { jq -r --arg k "$1" '.services.unpoller.environment[$k] // "unset"' <<<"$config"; }
[ "$(unpoller_env UP_UNIFI_DEFAULT_VERIFY_SSL)" = true ] || fail "unpoller does not verify TLS"
[ "$(unpoller_env UP_INFLUXDB_DISABLE)" = true ] || fail "unpoller InfluxDB output is on"
[ "$(unpoller_env UP_UNIFI_DEFAULT_SAVE_DPI)" = false ] || fail "unpoller DPI collection is on"
[ "$(unpoller_env UP_PROMETHEUS_HTTP_LISTEN)" = "0.0.0.0:9130" ] \
  || fail "unpoller does not listen on 9130"
# The password belongs in the environment of the stack only.
[ "$(unpoller_env UP_UNIFI_DEFAULT_PASS)" = "" ] \
  || fail "UNPOLLER_PASS has a value in .env.example or the compose file"
jq -e '.services.unpoller.volumes | any(.type == "bind"
  and .source == "/etc/ssl/certs/ca-certificates.crt"
  and .target == "/etc/ssl/certs/ca-certificates.crt" and .read_only == true)' \
  <<<"$config" >/dev/null || fail "unpoller does not get the host CA bundle read-only"

# snmp-exporter: same isolation as unpoller, on the snmp network.
jq -e '.services["snmp-exporter"] | ((.labels // {}) | length) == 0
  and ((.ports // []) | length) == 0 and ((.expose // []) | length) == 0
  and (.networks | keys) == ["snmp", "victoria"]' <<<"$config" >/dev/null \
  || fail "snmp-exporter has labels, ports or unexpected networks"
on_snmp_net="$(jq -c '[.services | to_entries[]
  | select((.value.networks // {}) | has("snmp")) | .key]' <<<"$config")"
[ "$on_snmp_net" = '["snmp-exporter"]' ] || fail "services on the snmp network: $on_snmp_net"
jq -e '.networks.snmp.internal != true' <<<"$config" >/dev/null \
  || fail "the snmp network is internal: snmp-exporter cannot reach the NAS"
[ "$(jq -r '.services["snmp-exporter"].user' <<<"$config")" = "65534:65534" ] \
  || fail "snmp-exporter does not run as 65534:65534"
snmp_env() { jq -r --arg k "$1" '.services["snmp-exporter"].environment[$k] // "unset"' <<<"$config"; }
for k in SNMP_AUTH_PASS SNMP_PRIV_PASS; do
  [ "$(snmp_env "$k")" = "" ] || fail "$k has a value in .env.example or the compose file"
done
jq -e '.services["snmp-exporter"].command | index("--config.expand-environment-variables")' \
  <<<"$config" >/dev/null || fail "snmp-exporter does not expand the \${...} references"
# "compose config" prints a literal $ as $$; gsub gives the mounted file.
auth_yml="$(jq -r '.configs.snmp_exporter_auth.content | gsub("\\$\\$"; "$")' <<<"$config")"
for line in 'version: 3' 'security_level: authPriv' 'auth_protocol: SHA' 'priv_protocol: AES' \
  'username: ${SNMP_USER}' 'password: ${SNMP_AUTH_PASS}' 'priv_password: ${SNMP_PRIV_PASS}'; do
  grep -qxF "    $line" <<<"$auth_yml" || fail "snmp_exporter_auth has no '$line'"
done

# victoriametrics scrapes unpoller with the victoriametrics_scrape config
# (test_unpoller.sh checks that VictoriaMetrics accepts it and scrapes).
jq -e '.services.victoriametrics | (.command | index("-promscrape.config=/etc/victoria/scrape.yml"))
  and (.configs | any(.source == "victoriametrics_scrape" and .target == "/etc/victoria/scrape.yml"))' \
  <<<"$config" >/dev/null || fail "victoriametrics does not load victoriametrics_scrape"
jq -e '.configs.victoriametrics_scrape.content | test("targets: \\[\"unpoller:9130\"\\]")' \
  <<<"$config" >/dev/null || fail "victoriametrics_scrape does not target unpoller:9130"
jq -e '.configs.victoriametrics_scrape.content
  | test("- job_name: synology\n(.*\n)*? *metrics_path: /snmp\n(.*\n)*? *replacement: snmp-exporter:9116\n")' \
  <<<"$config" >/dev/null || fail "the synology job does not go to snmp-exporter:9116/snmp"
# Self-scrape: one job per component, as the victoria_stack rules expect.
for target in victoriametrics:8428 victorialogs:9428 vmalert-logs:8880 vmalert-metrics:8880 \
  alertmanager:9093 vector:9598; do
  job="${target%%:*}"
  jq -e --arg j "$job" --arg t "$target" '.configs.victoriametrics_scrape.content
    | test("- job_name: \($j)\n(.*\n)*? *- targets: \\[\"\($t)\"\\]\n")' \
    <<<"$config" >/dev/null || fail "victoriametrics_scrape has no job $job on $target"
done
jq -e '.configs.vector_config.content
  | test("prometheus:\n *type: prometheus_exporter\n *inputs:\n *- vector_metrics\n *address: 0.0.0.0:9598\n")' \
  <<<"$config" >/dev/null || fail "vector does not export its internal metrics on 9598"

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
