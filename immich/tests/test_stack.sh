#!/usr/bin/env bash
# Static checks on the Immich stack, as Compose renders it with .env.example
# plus test values (nothing is started). Sign-in with Authentik is set in the
# Immich admin UI, so the stack only has to let the server reach Authentik:
# - NODE_EXTRA_CA_CERTS points at the host CA bundle, so the OAuth discovery
#   trusts Authentik's internal-CA certificate (Node only trusts its bundled
#   roots otherwise);
# - that bundle is inside the read-only bind mount of the host /etc/ssl/certs;
# - the Immich router is not behind forward auth: the mobile app, the OAuth
#   callback and the public proxy call Immich directly.
# Needs Docker Compose and jq. Usage: ./tests/test_stack.sh
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
host=photos.home.test
ca=/etc/ssl/certs/ca-certificates.crt

fail() { echo "FAIL: $*" >&2; exit 1; }

config="$(TRAEFIK_HOST_LOCAL="$host" TRAEFIK_HOST_PUBLIC=share.home.test \
  UPLOAD_LOCATION=/srv/test/upload DB_DATA_LOCATION=/srv/test/db \
  NFS_SERVER_IP=192.0.2.10 PHOTO_NAS_PATH=/test/photos \
  PHOTO_NAS_PASCAL_PATH=/test/a PHOTO_NAS_NATH_PATH=/test/b \
  docker compose --project-directory "$stack_dir" \
  --env-file "$stack_dir/.env.example" config --format json)"

value="$(jq -r '.services["immich-server"].environment.NODE_EXTRA_CA_CERTS // "<unset>"' <<<"$config")"
[ "$value" = "$ca" ] || fail "NODE_EXTRA_CA_CERTS is '$value', expected '$ca'"

# The bundle file must come from a read-only host mount that contains it:
# the mount target is a parent directory of (or equal to) the bundle path.
[ "$(jq -r --arg ca "$ca" '[.services["immich-server"].volumes[]
  | select(.type == "bind" and .read_only == true and .source == .target) | .target as $t
  | select($ca == $t or ($ca | startswith($t + "/")))]
  | length' <<<"$config")" -ge 1 ] \
  || fail "immich-server: $ca is not under a read-only host bind mount"

rule="$(jq -r '.services["immich-server"].labels["traefik.http.routers.immich.rule"]' <<<"$config")"
[ "$rule" = "Host(\`$host\`)" ] || fail "router rule is '$rule', expected Host(\`$host\`)"

middlewares="$(jq -r '.services["immich-server"].labels | to_entries[]
  | select(.key | test("^traefik\\.http\\.routers\\.[^.]+\\.middlewares$")) | .value' <<<"$config")"
[ "$middlewares" = redirect-https ] \
  || fail "unexpected router middlewares (forward auth would block the app and the OAuth callback): $middlewares"

echo "OK"
