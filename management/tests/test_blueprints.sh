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
# - NG media: second forward_single provider, application, media-users group
#   binding;
# - Portainer: third forward_single provider, application, portainer-users
#   group binding; plus a confidential OAuth2 provider (client_id
#   "portainer", one strict redirect URI to the Portainer root URL, RS256
#   with the self-signed key, openid/email/profile scopes) on a second
#   application hidden from the library, bound to the same group, not on the
#   outpost;
# - OpenObserve: fourth forward_single provider, application,
#   openobserve-users group binding; the outpost carries exactly these four
#   providers;
# - Forgejo: confidential OAuth2 provider (client_id "forgejo", one strict
#   redirect URI to the "authentik" source callback, RS256 with the
#   self-signed key, openid/email/profile scopes), application,
#   forgejo-users group binding, and not attached to the outpost;
# - a second apply creates no duplicate and keeps the generated Forgejo and
#   Portainer client secrets.
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
  -e BLUEPRINT_NG_HOST=media.example.test \
  -e BLUEPRINT_PORTAINER_HOST=portainer.example.test \
  -e BLUEPRINT_OPENOBSERVE_HOST=logs.example.test \
  -e BLUEPRINT_FORGEJO_HOST=git.example.test \
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
from authentik.providers.oauth2.models import OAuth2Provider
from authentik.providers.proxy.models import ProxyProvider
from authentik.stages.authenticator_validate.models import AuthenticatorValidateStage

def state():
    s = AuthenticatorValidateStage.objects.get(name="default-authentication-mfa-validation")
    p = ProxyProvider.objects.get(name="Uptime Kuma")
    a = Application.objects.get(slug="uptime-kuma")
    g = Group.objects.get(name="uptime-kuma-users")
    m = ProxyProvider.objects.get(name="NG media")
    ma = Application.objects.get(slug="ng-media")
    mg = Group.objects.get(name="media-users")
    pp = ProxyProvider.objects.get(name="Portainer")
    pa = Application.objects.get(slug="portainer")
    pg = Group.objects.get(name="portainer-users")
    ps = OAuth2Provider.objects.get(name="Portainer SSO")
    psa = Application.objects.get(slug="portainer-sso")
    op = ProxyProvider.objects.get(name="OpenObserve")
    oa = Application.objects.get(slug="openobserve")
    og = Group.objects.get(name="openobserve-users")
    f = OAuth2Provider.objects.get(name="Forgejo")
    fa = Application.objects.get(slug="forgejo")
    fg = Group.objects.get(name="forgejo-users")
    o = Outpost.objects.get(managed="goauthentik.io/outposts/embedded")
    return [
        s.not_configured_action,
        sorted(x.name for x in s.configuration_stages.all()),
        sorted(s.device_classes),
        p.mode, p.external_host, p.authorization_flow.slug, p.invalidation_flow.slug,
        a.provider_id == p.pk,
        PolicyBinding.objects.filter(target=a, group=g).count(),
        m.mode, m.external_host, m.authorization_flow.slug, m.invalidation_flow.slug,
        ma.provider_id == m.pk,
        PolicyBinding.objects.filter(target=ma, group=mg).count(),
        pp.mode, pp.external_host, pp.authorization_flow.slug, pp.invalidation_flow.slug,
        pa.provider_id == pp.pk,
        PolicyBinding.objects.filter(target=pa, group=pg).count(),
        ps.client_type, ps.client_id, len(ps.client_secret) >= 40,
        [(getattr(u.matching_mode, "value", u.matching_mode), u.url) for u in ps.redirect_uris],
        ps.signing_key.name if ps.signing_key else None,
        ps.authorization_flow.slug, ps.invalidation_flow.slug,
        sorted(x.scopemapping.scope_name for x in ps.property_mappings.all()),
        psa.provider_id == ps.pk, psa.meta_launch_url,
        PolicyBinding.objects.filter(target=psa, group=pg).count(),
        op.mode, op.external_host, op.authorization_flow.slug, op.invalidation_flow.slug,
        oa.provider_id == op.pk,
        PolicyBinding.objects.filter(target=oa, group=og).count(),
        f.client_type, f.client_id, len(f.client_secret) >= 40,
        [(getattr(u.matching_mode, "value", u.matching_mode), u.url) for u in f.redirect_uris],
        f.signing_key.name if f.signing_key else None,
        f.authorization_flow.slug, f.invalidation_flow.slug,
        sorted(x.scopemapping.scope_name for x in f.property_mappings.all()),
        fa.provider_id == f.pk,
        PolicyBinding.objects.filter(target=fa, group=fg).count(),
        sorted(x.pk for x in o.providers.all()) == sorted([p.pk, m.pk, pp.pk, op.pk]),
        o.config.authentik_host,
        Group.objects.filter(name="uptime-kuma-users").count(),
        ProxyProvider.objects.filter(name="Uptime Kuma").count(),
        Group.objects.filter(name="media-users").count(),
        ProxyProvider.objects.filter(name="NG media").count(),
        Group.objects.filter(name="portainer-users").count(),
        ProxyProvider.objects.filter(name="Portainer").count(),
        Group.objects.filter(name="openobserve-users").count(),
        ProxyProvider.objects.filter(name="OpenObserve").count(),
        Group.objects.filter(name="forgejo-users").count(),
        OAuth2Provider.objects.filter(name="Forgejo").count(),
        OAuth2Provider.objects.filter(name="Portainer SSO").count(),
        Outpost.objects.filter(managed="goauthentik.io/outposts/embedded").count(),
        (f.client_secret, ps.client_secret),  # last: compared, then dropped (never printed)
    ]

before = state()
# Same steps as the apply_blueprint task, without its task context.
for b in BlueprintInstance.objects.filter(path__startswith="custom/"):
    imp = Importer.from_string(b.retrieve(), b.context)
    assert imp.validate()[0], b.path
    assert imp.apply(), b.path
after = state()
same_secret = before.pop() == after.pop()
print("SAME" if before == after and same_secret else "CHANGED", before)'
result="$(ak_py "$check_py")"
expected="SAME ['configure', ['default-authenticator-totp-setup', 'default-authenticator-webauthn-setup'], ['static', 'totp', 'webauthn'], 'forward_single', 'https://uptime.example.test', 'default-provider-authorization-implicit-consent', 'default-provider-invalidation-flow', True, 1, 'forward_single', 'https://media.example.test', 'default-provider-authorization-implicit-consent', 'default-provider-invalidation-flow', True, 1, 'forward_single', 'https://portainer.example.test', 'default-provider-authorization-implicit-consent', 'default-provider-invalidation-flow', True, 1, 'confidential', 'portainer', True, [('strict', 'https://portainer.example.test/')], 'authentik Self-signed Certificate', 'default-provider-authorization-implicit-consent', 'default-provider-invalidation-flow', ['email', 'openid', 'profile'], True, 'blank://blank', 1, 'forward_single', 'https://logs.example.test', 'default-provider-authorization-implicit-consent', 'default-provider-invalidation-flow', True, 1, 'confidential', 'forgejo', True, [('strict', 'https://git.example.test/user/oauth2/authentik/callback')], 'authentik Self-signed Certificate', 'default-provider-authorization-implicit-consent', 'default-provider-invalidation-flow', ['email', 'openid', 'profile'], True, 1, True, 'https://auth.example.test', 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]"
[ "$result" = "$expected" ] || { tail -n 30 "$out" >&2; fail "unexpected state after apply:
  got:  $result
  want: $expected"; }

echo "OK"
