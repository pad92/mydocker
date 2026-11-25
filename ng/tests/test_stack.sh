#!/usr/bin/env bash
# Static checks on the NG Traefik routers, as Compose renders them with
# .env.example (nothing is started). For each *arr app:
# - the HTTPS router is behind Authentik forward auth (first middleware);
# - the API bypass router has no middleware, targets the app and has a longer
#   rule than the protected router (Traefik's default priority is the rule
#   length, so the bypass wins only on the paths it matches);
# - its path regex accepts the API paths and rejects the UI and look-alike
#   paths such as /radarr/apix (matched like Traefik: unanchored search, so
#   the ^ anchor and the (/|$) segment end are what keep it narrow).
# Needs Docker Compose 2.23+, jq and python3. Usage: ./tests/test_stack.sh
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
host=media.home.test

fail() { echo "FAIL: $*" >&2; exit 1; }

config="$(TRAEFIK_FQDN="$host" SEERR_DOMAIN=req.home.test DOCKER_CONFIG_PATH=/srv/ng \
  NFS_SERVER_IP=192.0.2.10 NFS_CLIENT_IP=192.0.2.20 MEDIA_BASE_PATH=/volume1/medias \
  MUSIC_PATH=/volume1/music DOWNLOAD_PATH=/volume1/downloads BACKUPS_PATH=/volume1/backups \
  SABNZBD_DOWNLOAD_PATH=/srv/incomplete TORRENTS_PATH=/srv/torrents SERIES_LOCAL_PATH=/srv/series \
  docker compose --project-directory "$stack_dir" \
  --env-file "$stack_dir/.env.example" config --format json)"

# Paths each app must serve without forward auth, then paths that must stay
# behind it. Query strings are not part of the path Traefik matches.
check_app() {
  local app="$1" allowed="$2" denied="$3"
  local labels=".services.$app.labels"
  label() { jq -r "$labels[\"$1\"] // \"\"" <<<"$config"; }

  label "traefik.http.routers.$app.middlewares" | grep -q '^authentik@docker' \
    || fail "$app router is not behind forward auth (first middleware)"

  local api="traefik.http.routers.${app}_api"
  [ -z "$(label "$api.middlewares")" ] \
    || fail "${app}_api router has a middleware: API clients would need a login"
  [ "$(label "$api.service")" = "$app" ] \
    || fail "${app}_api router does not target the $app service"
  [ "$(label "$api.entrypoints")" = websecure ] \
    || fail "${app}_api router is not on the HTTPS entry point"

  local rule main_rule prefix regex
  rule="$(label "$api.rule")"
  main_rule="$(label "traefik.http.routers.$app.rule")"
  [ "${#rule}" -gt "${#main_rule}" ] \
    || fail "${app}_api rule is not longer than the protected rule: it would not win"
  prefix="Host(\`$host\`) && PathRegexp(\`"
  case "$rule" in
    "$prefix"*'`)') ;;
    *) fail "${app}_api router is not a single PathRegexp on the NG host: $rule" ;;
  esac
  regex="${rule#"$prefix"}"
  regex="${regex%'`)'}"
  # "compose config" escapes $ as $$; the container label holds a single $.
  regex="${regex//\$\$/\$}"

  # Go regexp (Traefik) and Python re agree on this syntax.
  python3 -I - "$regex" "$allowed" "$denied" <<'EOF' \
    || fail "${app}_api path regex is too wide or too narrow"
import re, sys
r = re.compile(sys.argv[1])
allowed, denied = sys.argv[2].split(), sys.argv[3].split()
bad = [p for p in allowed if not r.search(p)] + [p for p in denied if r.search(p)]
for p in bad:
    print("misclassified:", p, file=sys.stderr)
sys.exit(1 if bad else 0)
EOF
}

for app in radarr sonarr lidarr; do
  check_app "$app" \
    "/$app/api /$app/api/ /$app/api/v3/movie /$app/feed/v3/calendar/$app.ics" \
    "/$app /$app/ /$app/apix /$app/api.php /$app/feedx /$app/settings /$app/x/api /api/$app"
done
for app in bazarr sabnzbd; do
  check_app "$app" \
    "/$app/api /$app/api/ /$app/api/system/status" \
    "/$app /$app/ /$app/apix /$app/api_key /$app/feed /$app/config /$app/x/api"
done
check_app prowlarr \
  "/prowlarr/api /prowlarr/api/v1/indexer /prowlarr/1/api /prowlarr/12/download" \
  "/prowlarr /prowlarr/ /prowlarr/apix /prowlarr/1/apix /prowlarr/1/downloadx /prowlarr/a/api /prowlarr/1/settings /prowlarr/feed"

echo "OK"
