#!/usr/bin/env bash
# Checks the compose file rendered with .env.example, then starts the stack with
# docker compose (on a throwaway network, no host port) and checks that:
# - /results/stats.php refuses an empty password and accepts the configured one;
# - config.json enables the modern design, even over an existing classic one.
# Needs Docker, Docker Compose 2.23+, jq and curl. Usage: ./tests/test_stack.sh
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$(mktemp -d)"
project="librespeed-test-$$"

compose() {
  docker compose --project-name "$project" --project-directory "$stack_dir" \
    --env-file "$work_dir/test.env" "$@"
}
cleanup() {
  compose -f "$stack_dir/docker-compose.yml" -f "$work_dir/override.yml" \
    down --volumes >/dev/null 2>&1 || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# Renders the compose file with test.env plus the given VAR=value overrides.
render() { env "$@" docker compose --project-directory "$stack_dir" \
  --env-file "$work_dir/test.env" config --format json; }

# PUID/PGID are empty in .env.example but required by the compose file.
sed -e "s/^PUID=.*/PUID=$(id -u)/" -e "s/^PGID=.*/PGID=$(id -g)/" \
  -e "s|^LIBRESPEED_DATA_DIR=.*|LIBRESPEED_DATA_DIR=$work_dir/config|" \
  -e "s/^LIBRESPEED_STATS_PASSWORD=.*/LIBRESPEED_STATS_PASSWORD=test0pass/" \
  -e "s/^CUSTOM_RESULTS=.*/CUSTOM_RESULTS=true/" \
  "$stack_dir/.env.example" > "$work_dir/test.env"

# Static checks on the rendered compose file.
config="$(render)"
service='.services.librespeed'
[ "$(jq -r "$service.environment.PASSWORD" <<<"$config")" = test0pass ] \
  || fail "PASSWORD is not passed to the container"
[ "$(jq -r "$service.labels[\"traefik.http.routers.librespeed.entrypoints\"]" <<<"$config")" = websecure ] \
  || fail "HTTPS router is not on websecure"
[ "$(jq -r "$service.labels[\"traefik.http.routers.librespeed_http.middlewares\"]" <<<"$config")" = redirect-https ] \
  || fail "HTTP router does not redirect to HTTPS"
jq -e "$service.security_opt | index(\"no-new-privileges:true\")" <<<"$config" >/dev/null \
  || fail "no-new-privileges is missing"
for design in true false; do
  [ "$(render LIBRESPEED_NEW_DESIGN="$design" | jq -r '.configs.design_config.content | fromjson | .useNewDesign')" = "$design" ] \
    || fail "LIBRESPEED_NEW_DESIGN=$design is not rendered as valid JSON"
done
# An empty stats password must stop the deployment.
if render LIBRESPEED_STATS_PASSWORD= >/dev/null 2>&1; then
  fail "compose accepts an empty LIBRESPEED_STATS_PASSWORD"
fi
echo "OK: static checks"

# Runtime check. The data directory already holds a classic config.json, as on
# a deployment made before LIBRESPEED_NEW_DESIGN existed.
mkdir -p "$work_dir/config/www"
printf '{\n  "useNewDesign": false\n}\n' > "$work_dir/config/www/config.json"
# Own container name and network, so the test neither clashes with a running
# librespeed nor needs the external traefik_gateway network.
cat > "$work_dir/override.yml" <<EOF
services:
  librespeed:
    container_name: $project
networks:
  traefik_gateway:
    external: false
    name: $project
EOF
compose -f "$stack_dir/docker-compose.yml" -f "$work_dir/override.yml" up -d --quiet-pull >/dev/null 2>&1 \
  || fail "docker compose up failed"
ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$project")"
[ -n "$ip" ] || fail "no IP for $project"
base="http://$ip"
for _ in $(seq 1 60); do
  curl -fs -o /dev/null "$base/results/stats.php" && break
  sleep 2
done

[ "$(curl -fs "$base/config.json" | jq -r .useNewDesign)" = true ] \
  || fail "config.json does not enable the modern design"
echo "OK: config.json enables the modern design"

# Logs in with $1 in a fresh session, prints the stats page body.
stats_after_login() {
  local jar="$work_dir/cookies" stats="$base/results/stats.php"
  rm -f "$jar"
  curl -fs -c "$jar" -b "$jar" -o /dev/null "$stats"
  curl -fs -c "$jar" -b "$jar" -o /dev/null --data-urlencode "password=$1" "$stats?op=login"
  curl -fs -c "$jar" -b "$jar" "$stats"
}

if stats_after_login "" | grep -q 'Search test results'; then
  fail "empty password opens the stats page"
fi
stats_after_login test0pass | grep -q 'Search test results' \
  || fail "configured password does not open the stats page"
echo "OK: stats page refuses an empty password and accepts the configured one"
