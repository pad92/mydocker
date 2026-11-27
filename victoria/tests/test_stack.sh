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
# - the MCP bypass router matches only POST, GET and DELETE /mcp on the
#   Grafana host, has no middleware and targets grafana-mcp on 8000; the
#   server is read-only (--disable-write), accepts only the Grafana host,
#   no browser origin, reaches Grafana on the internal network, has no port,
#   joins traefik_gateway and victoria only, refuses to start with an empty
#   or short token, and its two tokens are empty in .env.example;
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
# - freebox-exporter has no Traefik label, no port and no volume, runs as
#   65534 with an image pinned by tag and digest, joins only the freebox
#   network (its route out, which only it joins) and victoria, keeps its
#   token on a tmpfs, and its token is empty in .env.example; victoriametrics scrapes it on 9102;
# - nvidia-gpu-exporter shares the host PID namespace, so it has no Traefik
#   label, port or volume, joins only victoria, runs as 65534 with a
#   read-only root, no capability and no-new-privileges, gets the nvidia
#   device with the utility capability only, and its image is pinned by
#   digest; victoriametrics scrapes it on 9835, and the two recording rules
#   that name the containers of GPU processes are in the vmalert configs;
# - victoriametrics loads the scrape config that targets unpoller:9130,
#   sends the synology job to snmp-exporter:9116, and scrapes every component
#   of the stack (vector on its prometheus_exporter sink, 9598);
# - no service publishes a host port except vector, which publishes only the
#   UDP syslog port: 9428, 8428 and 4318 have no authentication of their own;
# - the victoria-ingest-auth middleware exists in the Traefik file provider
#   template (management stack) as Basic auth that drops the Authorization
#   header before the backend;
# - retention defaults (logs 30d, metrics 1y), mem_limit of the two databases
#   (1g), of the two vmalert and of alertmanager (128m), their healthchecks
#   and the depends_on conditions (vmalert waits for a healthy
#   victoriametrics and alertmanager);
# - the vector scrape job drops vector_*_bucket, and no other config (rules,
#   dashboards) reads those buckets;
# - the SMS webhook: VECTOR_WEBHOOK_PASSWORD is empty in .env.example, the
#   render fails without it, and the Basic auth that the sms receiver sends
#   equals the one the alertmanager_webhook source of Vector requires.
# Needs Docker Compose 2.23+, jq and python3.11+ with PyYAML.
# Usage: ./tests/test_stack.sh
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
config="$(PUID=1000 PGID=1000 VECTOR_WEBHOOK_PASSWORD=0123456789abcdef docker compose --project-directory "$stack_dir" \
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

# MCP server: POST/GET/DELETE /mcp only, no forward auth (the bearer token of
# mcp-grafana is the barrier), port 8000 of the grafana-mcp container.
check_bypass victoria_grafana_mcp \
  "Host(\`$grafana_host\`) && (Method(\`POST\`) || Method(\`GET\`) || Method(\`DELETE\`)) && Path(\`/mcp\`)" \
  "" victoria_grafana_mcp grafana-mcp
[ "$(label traefik.http.services.victoria_grafana_mcp.loadbalancer.server.port)" = 8000 ] \
  || fail "victoria_grafana_mcp does not target port 8000"
[ "$(owner traefik.http.services.victoria_grafana_mcp.loadbalancer.server.port)" = grafana-mcp ] \
  || fail "the victoria_grafana_mcp service is not defined on the grafana-mcp container"
# Read-only, Host limited to the Grafana domain, Grafana reached on the
# internal network, no port, and a start that refuses an empty or short token
# (mcp-grafana serves without authentication when its token is empty).
mcp_cmd="$(jq -r '.services."grafana-mcp".command | join("\n")' <<<"$config")"
mcp_env() { jq -r --arg k "$1" '.services."grafana-mcp".environment[$k] // ""' <<<"$config"; }
grep -q -- '--disable-write' <<<"$mcp_cmd" || fail "grafana-mcp is not read-only (--disable-write)"
# docker compose config keeps the $$ escape of the compose file.
grep -q -- '--allowed-hosts "$${MCP_ALLOWED_HOST}"' <<<"$mcp_cmd" \
  || fail "grafana-mcp does not limit the Host header to MCP_ALLOWED_HOST"
[ "$(mcp_env MCP_ALLOWED_HOST)" = "$grafana_host" ] \
  || fail "grafana-mcp allows the host '$(mcp_env MCP_ALLOWED_HOST)', expected $grafana_host"
grep -q -- '--allowed-origins' <<<"$mcp_cmd" && fail "grafana-mcp allows browser origins"
grep -q '"$${#MCP_GRAFANA_SERVER_TOKEN}" -lt 32' <<<"$mcp_cmd" \
  || fail "grafana-mcp starts without checking the length of its server token"
[ "$(jq -r '.services."grafana-mcp".entrypoint | join(" ")' <<<"$config")" = "/bin/sh -c" ] \
  || fail "grafana-mcp does not start through the token check"
[ "$(mcp_env GRAFANA_URL)" = "http://grafana:3000" ] \
  || fail "grafana-mcp does not reach Grafana on the internal network"
jq -e '.services."grafana-mcp" | (.ports // []) == []
  and (.networks | keys) == ["traefik_gateway", "victoria"]' <<<"$config" >/dev/null \
  || fail "grafana-mcp publishes a port or joins unexpected networks"
for secret in GRAFANA_MCP_SA_TOKEN GRAFANA_MCP_SERVER_TOKEN; do
  grep -q "^$secret=$" "$stack_dir/.env.example" || fail "$secret has a value in .env.example"
done

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
    vector_ingest|victoriametrics_ingest|victorialogs_health|victoriametrics_health|victoria_grafana_mcp) continue ;;
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
  jq -e --arg s "$s" '.services[$s] | ((.labels // {}) | del(.["mydocker.config-hash"]) | length) == 0
    and ((.ports // []) | length) == 0 and ((.expose // []) | length) == 0
    and (.networks | keys) == ["victoria"]' <<<"$config" >/dev/null \
    || fail "$s has labels, ports or a network other than victoria"
done
jq -e '.networks.victoria.internal == true' <<<"$config" >/dev/null \
  || fail "the victoria network is not internal"
# alertmanager: same, plus the alertmanager network, which only it joins, as
# the route out to the Uptime Kuma push URL (watchdog receiver).
jq -e '.services.alertmanager | ((.labels // {}) | del(.["mydocker.config-hash"]) | length) == 0
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
jq -e '.services.unpoller | ((.labels // {}) | del(.["mydocker.config-hash"]) | length) == 0
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
jq -e '.services["snmp-exporter"] | ((.labels // {}) | del(.["mydocker.config-hash"]) | length) == 0
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

# freebox-exporter: same isolation, on the freebox network. The app token
# comes from the environment only and is written to a tmpfs, never to a
# host directory; the image tag is pinned.
jq -e '.services["freebox-exporter"] | ((.labels // {}) | del(.["mydocker.config-hash"]) | length) == 0
  and ((.ports // []) | length) == 0 and ((.expose // []) | length) == 0
  and (.networks | keys) == ["freebox", "victoria"]
  and ((.volumes // []) | length) == 0
  and (.tmpfs | any(startswith("/data:")))' <<<"$config" >/dev/null \
  || fail "freebox-exporter has labels, ports, volumes or unexpected networks"
on_freebox_net="$(jq -c '[.services | to_entries[]
  | select((.value.networks // {}) | has("freebox")) | .key]' <<<"$config")"
[ "$on_freebox_net" = '["freebox-exporter"]' ] \
  || fail "services on the freebox network: $on_freebox_net"
jq -e '.networks.freebox["internal"] != true' <<<"$config" >/dev/null \
  || fail "the freebox network is internal: freebox-exporter cannot reach the box"
[ "$(jq -r '.services["freebox-exporter"].user' <<<"$config")" = "65534:65534" ] \
  || fail "freebox-exporter does not run as 65534:65534"
[ "$(jq -r '.services["freebox-exporter"].environment.FREEBOX_APP_TOKEN // "unset"' <<<"$config")" = "" ] \
  || fail "FREEBOX_APP_TOKEN has a value in .env.example or the compose file"
jq -r '.services["freebox-exporter"].image' <<<"$config" \
  | grep -qE '^ghcr\.io/shackerd/freebox-exporter-rs:v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?@sha256:[0-9a-f]{64}$' \
  || fail "freebox-exporter image is not pinned to a version tag and digest"
jq -e '.configs.freebox_exporter_config.content | test("data_directory = \"/data\"\n")' \
  <<<"$config" >/dev/null || fail "freebox_exporter_config does not keep its data on /data"
jq -e '.configs.victoriametrics_scrape.content
  | test("- job_name: freebox\n(.*\n)*? *- targets: \\[\"freebox-exporter:9102\"\\]\n")' \
  <<<"$config" >/dev/null || fail "victoriametrics_scrape has no freebox job on freebox-exporter:9102"

# nvidia-gpu-exporter: pid: host (it maps the PIDs of the GPU to their
# cgroup), so everything else is locked down: no label, port or volume,
# victoria network only (internal, no route out), 65534, read-only root,
# no capability, no privilege gain, and the nvidia device with the utility
# capability only (NVML, no compute). The image is pinned by digest.
jq -e '.services["nvidia-gpu-exporter"] | ((.labels // {}) | del(.["mydocker.config-hash"]) | length) == 0
  and ((.ports // []) | length) == 0 and ((.expose // []) | length) == 0
  and ((.volumes // []) | length) == 0
  and (.networks | keys) == ["victoria"]
  and .pid == "host" and .user == "65534:65534" and .read_only == true
  and (.cap_drop | index("ALL")) and (.security_opt | index("no-new-privileges:true"))' \
  <<<"$config" >/dev/null \
  || fail "nvidia-gpu-exporter is not isolated (labels, ports, volumes, networks, user, read_only, caps)"
jq -e '.services["nvidia-gpu-exporter"].deploy.resources.reservations.devices
  | length == 1 and .[0].driver == "nvidia" and .[0].capabilities == ["utility"]' \
  <<<"$config" >/dev/null || fail "nvidia-gpu-exporter gets more than the nvidia utility capability"
jq -r '.services["nvidia-gpu-exporter"].image' <<<"$config" \
  | grep -qE '^utkuozdemir/nvidia_gpu_exporter:[0-9]+\.[0-9]+\.[0-9]+-nvml@sha256:[0-9a-f]{64}$' \
  || fail "nvidia-gpu-exporter image is not the NVML build pinned by digest"
for flag in --collect.compute-apps --collect.compute-apps-identity; do
  jq -e --arg f "$flag" '.services["nvidia-gpu-exporter"].command | index($f)' <<<"$config" >/dev/null \
    || fail "nvidia-gpu-exporter runs without $flag"
done
jq -e '.configs.victoriametrics_scrape.content
  | test("- job_name: nvidia-gpu\n(.*\n)*? *- targets: \\[\"nvidia-gpu-exporter:9835\"\\]\n")' \
  <<<"$config" >/dev/null || fail "victoriametrics_scrape has no nvidia-gpu job on nvidia-gpu-exporter:9835"
# The container name of a GPU process: vmalert-logs records the
# container_id -> container_name pairs, vmalert-metrics joins them
# (metrics_rules_unittest.yaml checks the join itself).
jq -e '.configs.vmalert_logs_rules.content | test("- record: docker_container_info\n")' \
  <<<"$config" >/dev/null || fail "vmalert_logs_rules does not record docker_container_info"
jq -e '.configs.vmalert_metrics_rules.content
  | test("- record: container:nvidia_smi_compute_app_used_memory_bytes\n")' \
  <<<"$config" >/dev/null || fail "vmalert_metrics_rules does not record the VRAM per container"

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

# Retention: 1 year of metrics and 30 days of logs by default (the compose
# defaults, not only the values of .env.example).
grep -qF -- '-retentionPeriod=${VICTORIA_METRICS_RETENTION:-1y}' "$stack_dir/docker-compose.yml" \
  || fail "the default metrics retention is not 1y"
grep -qF -- '-retentionPeriod=${VICTORIA_LOGS_RETENTION:-30d}' "$stack_dir/docker-compose.yml" \
  || fail "the default logs retention is not 30d"

# Memory limits (bytes, as compose config renders them) and health checks.
for pair in victorialogs:1073741824 victoriametrics:1073741824 vmalert-logs:134217728 \
  vmalert-metrics:134217728 alertmanager:134217728; do
  s="${pair%%:*}"
  [ "$(jq -r --arg s "$s" '.services[$s].mem_limit // ""' <<<"$config")" = "${pair#*:}" ] \
    || fail "$s mem_limit is not ${pair#*:} bytes"
done
for pair in victoriametrics=http://127.0.0.1:8428/health vmalert-logs=http://127.0.0.1:8880/health \
  vmalert-metrics=http://127.0.0.1:8880/health alertmanager=http://127.0.0.1:9093/-/healthy; do
  s="${pair%%=*}"
  jq -e --arg s "$s" --arg u "${pair#*=}" '.services[$s].healthcheck.test
    == ["CMD", "wget", "-q", "-O", "/dev/null", $u]' <<<"$config" >/dev/null \
    || fail "$s has no wget health check on ${pair#*=}"
done
# vmalert starts only once its datasource and its notifier answer; victorialogs
# has no health check (no shell, no wget in its image), so started is the most.
jq -e '.services["vmalert-logs"].depends_on | (.victorialogs.condition == "service_started")
  and (.victoriametrics.condition == "service_healthy")
  and (.alertmanager.condition == "service_healthy")' <<<"$config" >/dev/null \
  || fail "vmalert-logs depends_on conditions are not the expected ones"
jq -e '.services["vmalert-metrics"].depends_on | (.victoriametrics.condition == "service_healthy")
  and (.alertmanager.condition == "service_healthy")' <<<"$config" >/dev/null \
  || fail "vmalert-metrics depends_on conditions are not the expected ones"

# Vector histograms: the vector job drops the buckets, so no dashboard or rule
# may use them (they would be empty).
jq -e '.configs.victoriametrics_scrape.content
  | test("- job_name: vector\n(.*\n)*? *metric_relabel_configs:\n *- source_labels: \\[__name__\\]\n *regex: \"vector_\\.\\*_bucket\"\n *action: drop\n")' \
  <<<"$config" >/dev/null || fail "the vector job does not drop the vector_.*_bucket series"
bucket_users="$(jq -r '.configs | to_entries[] | select(.key != "victoriametrics_scrape")
  | select(.value.content // "" | test("vector_[a-z_]+_bucket|histogram_quantile\\([^)]*vector_"))
  | .key' <<<"$config")"
[ -z "$bucket_users" ] || fail "configs use the dropped vector buckets: $bucket_users"

# SMS webhook: Alertmanager sends the Basic auth that the vector source
# requires, with the same password; it has no value in .env.example and
# Compose refuses to render the stack without it.
grep -q '^VECTOR_WEBHOOK_PASSWORD=$' "$stack_dir/.env.example" \
  || fail "VECTOR_WEBHOOK_PASSWORD has a value in .env.example"
if PUID=1000 PGID=1000 VECTOR_WEBHOOK_PASSWORD= docker compose --project-directory "$stack_dir" \
  --env-file "$stack_dir/.env.example" config -q 2>/dev/null; then
  fail "Compose renders the stack with an empty VECTOR_WEBHOOK_PASSWORD"
fi
webhook_check="$(cat <<'PY'
import json, sys, yaml
c = json.load(sys.stdin)["configs"]
am = yaml.safe_load(c["alertmanager_config"]["content"])
vec = yaml.safe_load(c["vector_config"]["content"])
hooks = [w for r in am["receivers"] for w in r.get("webhook_configs", [])
         if w["url"] == "http://vector:8080/alertmanager"]
src = vec["sources"]["alertmanager_webhook"]["auth"]
ok = len(hooks) == 1 and src.get("strategy") == "basic" and src.get("password") \
    and hooks[0].get("http_config", {}).get("basic_auth") \
        == {"username": src.get("username"), "password": src["password"]}
sys.exit(0 if ok else 1)
PY
)"
python3 -I -c "$webhook_check" <<<"$config" \
  || fail "the SMS webhook auth of alertmanager and vector differ or are missing"

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
