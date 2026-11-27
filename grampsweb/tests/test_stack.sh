#!/usr/bin/env bash
# Static checks on the Gramps Web stack, as Compose renders it with
# .env.example plus test values (nothing is started). For the web server and
# the Celery worker, which share one configuration:
# - OIDC sign-in is on (lowercase "true": Flask parses GRAMPSWEB_* as JSON, so
#   "True" would stay a string), against the "grampsweb" Authentik
#   application, with the client id of the management blueprint;
# - BASE_URL is https on the Gramps domain: Gramps Web builds the redirect URI
#   <BASE_URL>/api/oidc/callback/custom from it, and the Authentik provider
#   only accepts that exact URI;
# - the "groups" claim maps the three blueprint groups to owner, editor and
#   member, and no other role is mapped;
# - local accounts stay usable: no DISABLE_LOCAL_AUTH, no AUTO_REDIRECT;
# - the host CA bundle is mounted read-only and REQUESTS_CA_BUNDLE points at
#   it, so the OIDC discovery trusts Authentik's internal-CA certificate.
# - the AI chat is on for both: LLM_BASE_URL ends in /v1/ (Ollama's
#   OpenAI-compatible API; without it requests hit Ollama's native routes and
#   fail), the model carries the "ollama:" prefix (Ollama provider, no
#   OPENAI_API_KEY to leak or forget), and LLM_MAX_CONTEXT_LENGTH is a plain
#   integer, since Flask parses it as JSON.
# Rendering fails without the client secret, the Authentik domain or the LLM
# base URL, and the
# Traefik router is not behind forward auth (Gramps Web does its own login).
# Needs Docker Compose and jq. Usage: ./tests/test_stack.sh
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
domain=genealogy.home.test
idp=auth.home.test
ca=/etc/ssl/certs/ca-certificates.crt

fail() { echo "FAIL: $*" >&2; exit 1; }

render() {
  docker compose --project-directory "$stack_dir" \
    --env-file "$stack_dir/.env.example" config --format json
}

config="$(GRAMPSWEB_DOMAIN="$domain" AUTHENTIK_DOMAIN="$idp" \
  GRAMPSWEB_OIDC_CLIENT_SECRET=test-secret render)"

for svc in grampsweb grampsweb_celery; do
  getenv() { jq -r --arg s "$svc" --arg k "$1" '.services[$s].environment[$k] // "<unset>"' <<<"$config"; }
  expect() {
    [ "$(getenv "$1")" = "$2" ] || fail "$svc: $1 is '$(getenv "$1")', expected '$2'"
  }
  expect GRAMPSWEB_OIDC_ENABLED true
  expect GRAMPSWEB_BASE_URL "https://$domain"
  expect GRAMPSWEB_OIDC_ISSUER "https://$idp/application/o/grampsweb/"
  expect GRAMPSWEB_OIDC_CLIENT_ID grampsweb
  expect GRAMPSWEB_OIDC_CLIENT_SECRET test-secret
  expect GRAMPSWEB_OIDC_ROLE_CLAIM groups
  expect GRAMPSWEB_OIDC_GROUP_OWNER grampsweb-owners
  expect GRAMPSWEB_OIDC_GROUP_EDITOR grampsweb-editors
  expect GRAMPSWEB_OIDC_GROUP_MEMBER grampsweb-members
  expect REQUESTS_CA_BUNDLE "$ca"
  expect GRAMPSWEB_LLM_MODEL "ollama:qwen2.5:7b"
  expect GRAMPSWEB_LLM_MAX_CONTEXT_LENGTH 20000
  [[ "$(getenv GRAMPSWEB_LLM_BASE_URL)" == http*://*/v1/ ]] \
    || fail "$svc: GRAMPSWEB_LLM_BASE_URL must end in /v1/"
  [[ "$(getenv GRAMPSWEB_LLM_MODEL)" == ollama:?* ]] \
    || fail "$svc: GRAMPSWEB_LLM_MODEL must keep the ollama: prefix"
  [[ "$(getenv GRAMPSWEB_LLM_MAX_CONTEXT_LENGTH)" =~ ^[1-9][0-9]*$ ]] \
    || fail "$svc: GRAMPSWEB_LLM_MAX_CONTEXT_LENGTH is not an integer"
  expect OPENAI_API_KEY "<unset>"

  others="$(jq -r --arg s "$svc" '.services[$s].environment | keys[]
    | select(test("^GRAMPSWEB_OIDC_(GROUP_|DISABLE_LOCAL_AUTH|AUTO_REDIRECT)"))
    | select(IN("GRAMPSWEB_OIDC_GROUP_OWNER","GRAMPSWEB_OIDC_GROUP_EDITOR","GRAMPSWEB_OIDC_GROUP_MEMBER") | not)' <<<"$config")"
  [ -z "$others" ] || fail "$svc: unexpected OIDC settings: $others"

  [ "$(jq -r --arg s "$svc" --arg ca "$ca" '[.services[$s].volumes[]
    | select(.type == "bind" and .source == $ca and .target == $ca and .read_only == true)]
    | length' <<<"$config")" = 1 ] || fail "$svc: host CA bundle is not mounted read-only at $ca"
done

middlewares="$(jq -r '.services.grampsweb.labels | to_entries[]
  | select(.key | test("^traefik\\.http\\.routers\\.[^.]+\\.middlewares$")) | .value' <<<"$config")"
[ "$middlewares" = redirect-https ] \
  || fail "unexpected router middlewares (forward auth would block the OIDC callback and the API): $middlewares"

for missing in GRAMPSWEB_OIDC_CLIENT_SECRET AUTHENTIK_DOMAIN GRAMPSWEB_LLM_BASE_URL; do
  out="$(GRAMPSWEB_DOMAIN="$domain" AUTHENTIK_DOMAIN="$idp" GRAMPSWEB_OIDC_CLIENT_SECRET=test-secret \
    bash -c 'export "$1="; shift; "$@"' _ "$missing" \
    docker compose --project-directory "$stack_dir" --env-file "$stack_dir/.env.example" \
    config --format json 2>&1 >/dev/null)" \
    && fail "rendering succeeds with an empty $missing"
  grep -q "Set $missing" <<<"$out" || fail "rendering without $missing fails for another reason: $out"
done

echo "OK"
