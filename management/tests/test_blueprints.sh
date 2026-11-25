#!/usr/bin/env bash
# Applies the versioned blueprints on a throw-away Authentik (PostgreSQL +
# worker, private network, no published port) and checks the objects they
# create. The worker is the component that applies blueprints in production.
# Checks:
# - both blueprints end in status "successful";
# - MFA validation: "configure" with TOTP and WebAuthn as enrolment choices;
# - Uptime Kuma: forward_single provider on the URL built from the env var,
#   application, group binding, provider attached to the embedded outpost,
#   outpost authentik_host built from the env var;
# - a second apply creates no duplicate.
# Pulls ghcr.io/goauthentik/server and postgres:16-alpine if missing.
# Takes 1 to 3 minutes. Usage: ./tests/test_blueprints.sh
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tag="${AUTHENTIK_TAG:-2026.8.6}"
image="ghcr.io/goauthentik/server:$tag"
name="ak-bp-test-$$"
pg_pass="$(openssl rand -hex 16)"
secret="$(openssl rand -hex 32)"

fail() { echo "FAIL: $*" >&2; exit 1; }
cleanup() {
  docker rm -f "$name-worker" "$name-pg" >/dev/null 2>&1 || true
  docker network rm "$name" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker network create --internal "$name" >/dev/null
docker run -d --name "$name-pg" --network "$name" \
  -e POSTGRES_DB=authentik -e POSTGRES_USER=authentik -e POSTGRES_PASSWORD="$pg_pass" \
  postgres:16-alpine >/dev/null
for _ in $(seq 30); do
  docker exec "$name-pg" pg_isready -U authentik -d authentik >/dev/null 2>&1 && break
  sleep 1
done

docker run -d --name "$name-worker" --network "$name" \
  -e AUTHENTIK_SECRET_KEY="$secret" \
  -e AUTHENTIK_POSTGRESQL__HOST="$name-pg" \
  -e AUTHENTIK_POSTGRESQL__NAME=authentik \
  -e AUTHENTIK_POSTGRESQL__USER=authentik \
  -e AUTHENTIK_POSTGRESQL__PASSWORD="$pg_pass" \
  -e AUTHENTIK_ERROR_REPORTING__ENABLED=false \
  -e AUTHENTIK_DISABLE_STARTUP_ANALYTICS=true \
  -e BLUEPRINT_AUTHENTIK_HOST=auth.example.test \
  -e BLUEPRINT_UPTIME_HOST=uptime.example.test \
  -v "$stack_dir/authentik/blueprints:/blueprints/custom:ro" \
  "$image" worker >/dev/null

# Runs Python inside Authentik (Django ORM). Full output (stdout and stderr)
# goes to $out so a failure can be shown; the last line is printed.
out="$(mktemp)"
trap 'cleanup; rm -f "$out"' EXIT
ak_py() {
  docker exec -i "$name-worker" ak shell <<<"$1" >"$out" 2>&1 || true
  tail -n 1 "$out"
}

status_py='
from authentik.blueprints.models import BlueprintInstance as B
print(",".join(sorted(f"{b.path}={b.status}" for b in B.objects.filter(path__startswith="custom/"))))'
# Messages of the apply tasks of a blueprint in error, shown on failure.
logs_py='
from authentik.blueprints.models import BlueprintInstance as B
for b in B.objects.filter(path__startswith="custom/", status="error"):
    for t in b.tasks.all():
        for m in t._previous_messages + t._messages:
            print(b.path, m)'
want="custom/10-mfa.yaml=successful,custom/20-forward-auth-apps.yaml=successful"
status=""
for _ in $(seq 60); do
  status="$(ak_py "$status_py" || true)"
  [ "$status" = "$want" ] && break
  case "$status" in *error*)
    ak_py "$logs_py" >/dev/null; cat "$out" >&2
    fail "blueprint apply failed: $status" ;;
  esac
  sleep 5
done
[ "$status" = "$want" ] || fail "blueprints not applied in time: '$status'"

check_py='
from authentik.blueprints.models import BlueprintInstance
from authentik.blueprints.v1.importer import Importer
from authentik.core.models import Application, Group
from authentik.outposts.models import Outpost
from authentik.policies.models import PolicyBinding
from authentik.providers.proxy.models import ProxyProvider
from authentik.stages.authenticator_validate.models import AuthenticatorValidateStage

def state():
    s = AuthenticatorValidateStage.objects.get(name="default-authentication-mfa-validation")
    p = ProxyProvider.objects.get(name="Uptime Kuma")
    a = Application.objects.get(slug="uptime-kuma")
    g = Group.objects.get(name="uptime-kuma-users")
    o = Outpost.objects.get(managed="goauthentik.io/outposts/embedded")
    return [
        s.not_configured_action,
        sorted(x.name for x in s.configuration_stages.all()),
        sorted(s.device_classes),
        p.mode, p.external_host, p.authorization_flow.slug, p.invalidation_flow.slug,
        a.provider_id == p.pk,
        PolicyBinding.objects.filter(target=a, group=g).count(),
        [x.pk for x in o.providers.all()] == [p.pk],
        o.config.authentik_host,
        Group.objects.filter(name="uptime-kuma-users").count(),
        ProxyProvider.objects.filter(name="Uptime Kuma").count(),
        Outpost.objects.filter(managed="goauthentik.io/outposts/embedded").count(),
    ]

before = state()
# Same steps as the apply_blueprint task, without its task context.
for b in BlueprintInstance.objects.filter(path__startswith="custom/"):
    imp = Importer.from_string(b.retrieve(), b.context)
    assert imp.validate()[0], b.path
    assert imp.apply(), b.path
after = state()
print("SAME" if before == after else "CHANGED", before)'
result="$(ak_py "$check_py")"
expected="SAME ['configure', ['default-authenticator-totp-setup', 'default-authenticator-webauthn-setup'], ['static', 'totp', 'webauthn'], 'forward_single', 'https://uptime.example.test', 'default-provider-authorization-implicit-consent', 'default-provider-invalidation-flow', True, 1, True, 'https://auth.example.test', 1, 1, 1]"
[ "$result" = "$expected" ] || { tail -n 30 "$out" >&2; fail "unexpected state after apply:
  got:  $result
  want: $expected"; }

echo "OK"
