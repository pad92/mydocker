#!/usr/bin/env bash
# Static checks on the todo stack, as Compose renders it with .env.example plus
# test values (nothing is started):
# - Donetick signs in through the "donetick" Authentik application: client id
#   of the management blueprint, Authentik's authorize/token/userinfo
#   endpoints, and a redirect URI that is exactly one of those the provider
#   accepts (https://<TODO_DOMAIN>/auth/oauth2);
# - the scopes are a comma-separated list without spaces (Donetick splits on
#   "," and has no default scopes);
# - password login and circle roles are left alone: no DT_DISABLE_PASSWORD_AUTH,
#   no DT_OAUTH2_ADMIN_GROUPS / DT_OAUTH2_MANAGER_GROUPS;
# - the host CA bundle is mounted read-only where Go looks for it, so the token
#   and userinfo calls trust Authentik's internal-CA certificate;
# - the SQLite file is /donetick-data/donetick.db even when a DT_SQLITE_PATH
#   stack variable is set, and its directory is a volume in the container
#   (else Donetick crash-loops on SQLite error 14, or writes the database
#   outside any volume).
# Rendering fails without the client secret, the Authentik domain, the todo
# domain or the data directory, and the Traefik routers are not behind forward auth (the mobile app
# and the external API call Donetick directly).
# Needs Docker Compose and jq. Usage: ./tests/test_stack.sh
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
domain=todo.example.test
idp=auth.example.test
ca=/etc/ssl/certs/ca-certificates.crt

fail() { echo "FAIL: $*" >&2; exit 1; }

compose() {
  TODO_DOMAIN="$domain" AUTHENTIK_DOMAIN="$idp" DONETICK_OIDC_CLIENT_SECRET=test-secret \
    TODO_DONETICK_DATA_DIR=/srv/donetick "$@" \
    docker compose --project-directory "$stack_dir" \
    --env-file "$stack_dir/.env.example" config --format json
}

config="$(compose env)"

getenv() { jq -r --arg k "$1" '.services.donetick.environment[$k] // "<unset>"' <<<"$config"; }
expect() {
  [ "$(getenv "$1")" = "$2" ] || fail "$1 is '$(getenv "$1")', expected '$2'"
}
expect DT_OAUTH2_CLIENT_ID donetick
expect DT_OAUTH2_CLIENT_SECRET test-secret
expect DT_OAUTH2_AUTH_URL "https://$idp/application/o/authorize/"
expect DT_OAUTH2_TOKEN_URL "https://$idp/application/o/token/"
expect DT_OAUTH2_USER_INFO_URL "https://$idp/application/o/userinfo/"
expect DT_OAUTH2_REDIRECT_URL "https://$domain/auth/oauth2"
expect DT_OAUTH2_SCOPES openid,profile,email
expect DT_OAUTH2_NAME Authentik

for key in DT_DISABLE_PASSWORD_AUTH DT_OAUTH2_ADMIN_GROUPS DT_OAUTH2_MANAGER_GROUPS; do
  [ "$(getenv "$key")" = "<unset>" ] || fail "$key must stay unset, got '$(getenv "$key")'"
done

[ "$(jq -r --arg ca "$ca" '[.services.donetick.volumes[]
  | select(.type == "bind" and .source == $ca and .target == $ca and .read_only == true)]
  | length' <<<"$config")" = 1 ] || fail "host CA bundle is not mounted read-only at $ca"

expect DT_SQLITE_PATH /donetick-data/donetick.db
# The database directory must be a volume target, or a subdirectory of one.
db_dir_mounted() {
  jq -e --arg dir "$(dirname "$(getenv DT_SQLITE_PATH)")" '[.services.donetick.volumes[]
    | select(.type == "bind") | .target as $t | select($t == $dir or ($dir | startswith($t + "/")))]
    | length > 0' <<<"$config" >/dev/null
}
db_dir_mounted || fail "the directory of DT_SQLITE_PATH ($(getenv DT_SQLITE_PATH)) is not a volume"
# A stack variable (a host path set in Portainer broke it once) must not
# override the path.
config="$(compose env DT_SQLITE_PATH=/srv/donetick/donetick.db)"
expect DT_SQLITE_PATH /donetick-data/donetick.db
config="$(compose env)"

middlewares="$(jq -r '.services.donetick.labels | to_entries[]
  | select(.key | test("^traefik\\.http\\.routers\\.[^.]+\\.middlewares$")) | .value' <<<"$config")"
[ "$middlewares" = redirect-https ] \
  || fail "unexpected router middlewares (forward auth would block the mobile app and the API): $middlewares"

for missing in DONETICK_OIDC_CLIENT_SECRET AUTHENTIK_DOMAIN TODO_DOMAIN TODO_DONETICK_DATA_DIR; do
  out="$(compose env "$missing=" 2>&1 >/dev/null)" \
    && fail "rendering succeeds with an empty $missing"
  grep -q "Set $missing" <<<"$out" || fail "rendering without $missing fails for another reason: $out"
done

echo "OK"
