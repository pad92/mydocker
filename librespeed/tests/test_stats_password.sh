#!/usr/bin/env bash
# Checks the compose file rendered with .env.example, then starts the image
# with the rendered environment (default bridge, no host port) and checks that
# /results/stats.php refuses an empty password and accepts the configured one.
# Needs Docker, Docker Compose, jq and curl. Usage: ./tests/test_stats_password.sh
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$(mktemp -d)"
container="librespeed-test-$$"
cleanup() {
  docker rm -f "$container" >/dev/null 2>&1 || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

render() {
  docker compose --project-directory "$stack_dir" --env-file "$work_dir/test.env" \
    config --format json
}

# PUID/PGID are empty in .env.example but required by the compose file.
sed -e "s/^PUID=.*/PUID=$(id -u)/" -e "s/^PGID=.*/PGID=$(id -g)/" \
  -e "s|^LIBRESPEED_DATA_DIR=.*|LIBRESPEED_DATA_DIR=$work_dir/config|" \
  -e "s/^LIBRESPEED_STATS_PASSWORD=.*/LIBRESPEED_STATS_PASSWORD=test0pass/" \
  -e "s/^CUSTOM_RESULTS=.*/CUSTOM_RESULTS=true/" \
  "$stack_dir/.env.example" > "$work_dir/test.env"
mkdir "$work_dir/config"

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

# An empty stats password must stop the deployment.
sed -i 's/^LIBRESPEED_STATS_PASSWORD=.*/LIBRESPEED_STATS_PASSWORD=/' "$work_dir/test.env"
if render >/dev/null 2>&1; then
  fail "compose accepts an empty LIBRESPEED_STATS_PASSWORD"
fi
echo "OK: static checks"

# Runtime check with the environment rendered from the compose file.
env_args=()
while IFS= read -r line; do env_args+=(-e "$line"); done < <(
  jq -r "$service.environment | to_entries[] | \"\(.key)=\(.value)\"" <<<"$config")
image="$(jq -r "$service.image" <<<"$config")"
docker run -d --name "$container" --security-opt no-new-privileges:true \
  "${env_args[@]}" -v "$work_dir/config:/config" "$image" >/dev/null
# Reach the container on the default bridge instead of publishing a host port.
ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container")"
[ -n "$ip" ] || fail "no bridge IP for $container"
base="http://$ip/results/stats.php"
for _ in $(seq 1 60); do
  curl -fs -o /dev/null "$base" && break
  sleep 2
done

# Logs in with $1 in a fresh session, prints the stats page body.
stats_after_login() {
  local jar="$work_dir/cookies"
  rm -f "$jar"
  curl -fs -c "$jar" -b "$jar" -o /dev/null "$base"
  curl -fs -c "$jar" -b "$jar" -o /dev/null --data-urlencode "password=$1" "$base?op=login"
  curl -fs -c "$jar" -b "$jar" "$base"
}

if stats_after_login "" | grep -q 'Search test results'; then
  fail "empty password opens the stats page"
fi
stats_after_login test0pass | grep -q 'Search test results' \
  || fail "configured password does not open the stats page"
echo "OK: stats page refuses an empty password and accepts the configured one"
