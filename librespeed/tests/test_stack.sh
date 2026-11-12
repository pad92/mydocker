#!/usr/bin/env bash
# Checks the compose file rendered with .env.example, then starts the stack with
# docker compose (on a throwaway network, no host port) and checks that:
# - /results/stats.php refuses an empty password and accepts the configured one;
# - config.json enables the modern design, even over an existing classic one;
# - server-list.json holds only this server by default, and its URLs answer;
#   LIBRESPEED_SERVER_LIST=custom keeps an edited file, =public restores the
#   image's list;
# - a classic index.html left by an older image is replaced by the design
#   switcher once, and kept as index.html.old.
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
[ "$(jq -r "$service.environment.SERVER_LIST" <<<"$config")" = local ] \
  || fail "SERVER_LIST does not default to local"
[ "$(render LIBRESPEED_SERVER_LIST=custom | jq -r "$service.environment.SERVER_LIST")" = custom ] \
  || fail "LIBRESPEED_SERVER_LIST is not passed to the container"
# An empty stats password must stop the deployment.
if render LIBRESPEED_STATS_PASSWORD= >/dev/null 2>&1; then
  fail "compose accepts an empty LIBRESPEED_STATS_PASSWORD"
fi
echo "OK: static checks"

# Runtime check. The data directory already holds a classic config.json, a
# public server list and a classic index.html, as on a deployment made with an
# older image.
mkdir -p "$work_dir/config/www"
printf '{\n  "useNewDesign": false\n}\n' > "$work_dir/config/www/config.json"
printf '[{"name":"London","server":"//lon.example/backend"}]\n' > "$work_dir/config/www/server-list.json"
old_page='<html><body>classic page</body></html>'
printf '%s\n' "$old_page" > "$work_dir/config/www/index.html"
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
# Creates or recreates the container, with the environment given as VAR=value.
start() {
  env "$@" docker compose --project-name "$project" --project-directory "$stack_dir" \
    --env-file "$work_dir/test.env" -f "$stack_dir/docker-compose.yml" \
    -f "$work_dir/override.yml" up -d --quiet-pull >/dev/null 2>&1 \
    || fail "docker compose up failed ($*)"
  ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$project")"
  [ -n "$ip" ] || fail "no IP for $project"
  base="http://$ip"
}
start
wait_ready() {
  for _ in $(seq 1 60); do
    curl -fs -o /dev/null "$base/results/stats.php" && return 0
    sleep 2
  done
  fail "librespeed did not answer"
}
wait_ready

# Checks that / serves the switcher and index.html.old holds the classic page.
check_index() {
  curl -fs "$base/" | grep -q design-switch.js \
    || fail "index.html does not load design-switch.js ($1)"
  [ "$(cat "$work_dir/config/www/index.html.old")" = "$old_page" ] \
    || fail "index.html.old does not hold the classic page ($1)"
}
check_index "first start"
# A second start must leave both files alone.
docker restart "$project" >/dev/null
sleep 5
wait_ready
check_index "after restart"
echo "OK: classic index.html replaced once by the design switcher"

[ "$(curl -fs "$base/config.json" | jq -r .useNewDesign)" = true ] \
  || fail "config.json does not enable the modern design"
echo "OK: config.json enables the modern design"

list="$(curl -fs "$base/server-list.json")"
[ "$(jq length <<<"$list")" = 1 ] || fail "server-list.json does not hold a single server"
[ "$(jq -r '.[0].server' <<<"$list")" = / ] || fail "the local server is not the page's own origin"
# Builds each URL as speedtest.js does (server + dlURL...), relative to the page.
for key in dlURL ulURL pingURL getIpURL; do
  url="$base$(jq -r ".[0].server + .[0].$key" <<<"$list")"
  curl -fs -o /dev/null "$url" || fail "$key of the local server does not answer: $url"
done
echo "OK: server-list.json holds only the local server, and its URLs answer"

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

# custom keeps a hand-edited list; public restores the image's list.
edited='[{"name":"Edited","server":"/","id":7}]'
printf '%s\n' "$edited" > "$work_dir/config/www/server-list.json"
start LIBRESPEED_SERVER_LIST=custom
wait_ready
[ "$(curl -fs "$base/server-list.json" | jq -c .)" = "$edited" ] \
  || fail "LIBRESPEED_SERVER_LIST=custom does not keep the edited list"
start LIBRESPEED_SERVER_LIST=public
wait_ready
[ "$(curl -fs "$base/server-list.json" | jq length)" -gt 1 ] \
  || fail "LIBRESPEED_SERVER_LIST=public does not restore the public list"
echo "OK: LIBRESPEED_SERVER_LIST=custom keeps the file, =public restores the image's list"
