#!/usr/bin/env bash
# Applies the versioned blueprints on a throw-away Authentik (PostgreSQL +
# worker, private network, no published port) and checks the objects they
# create. The worker is the component that applies blueprints in production.
# Checks:
# - the three blueprints end in status "successful";
# - MFA validation: "configure" with TOTP and WebAuthn as enrolment choices;
# - Uptime Kuma: forward_single provider on the URL built from the env var,
#   application, group binding, provider attached to the embedded outpost,
#   outpost authentik_host built from the env var;
# - NG media: second forward_single provider, application hidden from the
#   library, media-users group binding; plus one bookmark application per
#   *arr app (Radarr, Sonarr, Bazarr, Lidarr, SABnzbd, Prowlarr): no provider
#   (a provider is tied to a host, the apps share one), launch URL on the NG
#   host and the app path, "NG media" library group, media-users binding;
#   same for h5ai, whose launch URL is the root of the NG host;
# - Portainer: third forward_single provider, application, portainer-users
#   group binding; plus a confidential OAuth2 provider (client_id
#   "portainer", authorization_code and refresh_token grant types (none by
#   default: every login would fail), one strict redirect URI to the
#   Portainer root URL, RS256 with the self-signed key, openid/email/profile scopes) on a second
#   application hidden from the library, bound to the same group, not on the
#   outpost;
# - OpenObserve: fourth forward_single provider, application,
#   openobserve-users group binding; the outpost carries exactly these four
#   providers;
# - Forgejo: confidential OAuth2 provider (client_id "forgejo", same grant
#   types, one strict redirect URI to the "authentik" source callback, RS256 with the
#   self-signed key, openid/email/profile scopes), application,
#   forgejo-users group binding, and not attached to the outpost;
# - Infrastructure: UniFi, Synology NAS and switch bookmarks (no provider,
#   launch URL built from the env var, an IP address for the switch,
#   "Infrastructure" library group, a single binding, to infra-users);
# - branding: default brand title, logo, favicon, flow background and dark
#   theme attribute; login flow title and the background of each flow a user
#   sees; icon, description and library group of each visible application
#   (files: tests/test_media.sh). The default authentication flow blueprint
#   can win the race on the title (30-branding.yaml), so the check first
#   re-applies 30-branding.yaml, as the README says to;
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
  -e BLUEPRINT_UNIFI_HOST=unifi.example.test \
  -e BLUEPRINT_NAS_HOST=nas.example.test \
  -e BLUEPRINT_SWITCH_HOST=192.0.2.30 \
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
# Also counts the instances not applied yet (the defaults among them): one
# applied after the check would undo the re-apply of 30-branding.yaml.
unapplied = B.objects.filter(status="unknown").count()
print(",".join(sorted(f"{b.path}={b.status}" for b in B.objects.filter(path__startswith="custom/")))
      + f",unapplied={unapplied}")'
# Messages of the apply tasks of a blueprint in error, shown on failure.
logs_py='
from authentik.blueprints.models import BlueprintInstance as B
for b in B.objects.filter(path__startswith="custom/", status="error"):
    for t in b.tasks.all():
        for m in t._previous_messages + t._messages:
            print(b.path, m)'
want="custom/10-mfa.yaml=successful,custom/20-forward-auth-apps.yaml=successful,custom/30-branding.yaml=successful,unapplied=0"
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
from authentik.brands.models import Brand
from authentik.core.models import Application, Group
from authentik.flows.models import Flow
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
    ig = Group.objects.get(name="infra-users")
    o = Outpost.objects.get(managed="goauthentik.io/outposts/embedded")
    br = Brand.objects.get(default=True)
    return [
        br.domain, br.branding_title, str(br.branding_logo), str(br.branding_favicon),
        str(br.branding_default_flow_background), br.attributes,
        Flow.objects.get(slug="default-authentication-flow").title,
        [(x.slug, str(x.background)) for x in Flow.objects.filter(slug__in=(
            "default-authentication-flow", "default-authenticator-static-setup",
            "default-authenticator-totp-setup", "default-authenticator-webauthn-setup",
            "default-invalidation-flow", "default-provider-invalidation-flow")).order_by("slug")],
        [(x.slug, str(x.meta_icon), x.meta_description, x.group)
         for x in (Application.objects.get(slug=y) for y in
                   ("uptime-kuma", "portainer", "openobserve", "forgejo", "radarr",
                    "sonarr", "bazarr", "lidarr", "sabnzbd", "prowlarr", "h5ai"))],
        s.not_configured_action,
        sorted(x.name for x in s.configuration_stages.all()),
        sorted(s.device_classes),
        p.mode, p.external_host, p.authorization_flow.slug, p.invalidation_flow.slug,
        a.provider_id == p.pk,
        PolicyBinding.objects.filter(target=a, group=g).count(),
        m.mode, m.external_host, m.authorization_flow.slug, m.invalidation_flow.slug,
        ma.provider_id == m.pk, ma.meta_launch_url,
        PolicyBinding.objects.filter(target=ma, group=mg).count(),
        [(b.slug, b.name, b.provider_id, b.group, b.meta_launch_url,
          PolicyBinding.objects.filter(target=b).count(),
          PolicyBinding.objects.filter(target=b, group=mg).count(),
          Application.objects.filter(slug=b.slug).count())
         for b in (Application.objects.get(slug=x) for x in
                   ("radarr", "sonarr", "bazarr", "lidarr", "sabnzbd", "prowlarr",
                    "h5ai"))],
        pp.mode, pp.external_host, pp.authorization_flow.slug, pp.invalidation_flow.slug,
        pa.provider_id == pp.pk,
        PolicyBinding.objects.filter(target=pa, group=pg).count(),
        ps.client_type, ps.client_id, len(ps.client_secret) >= 40, sorted(ps.grant_types),
        [(getattr(u.matching_mode, "value", u.matching_mode), u.url) for u in ps.redirect_uris],
        ps.signing_key.name if ps.signing_key else None,
        ps.authorization_flow.slug, ps.invalidation_flow.slug,
        sorted(x.scopemapping.scope_name for x in ps.property_mappings.all()),
        psa.provider_id == ps.pk, psa.meta_launch_url,
        PolicyBinding.objects.filter(target=psa, group=pg).count(),
        op.mode, op.external_host, op.authorization_flow.slug, op.invalidation_flow.slug,
        oa.provider_id == op.pk,
        PolicyBinding.objects.filter(target=oa, group=og).count(),
        f.client_type, f.client_id, len(f.client_secret) >= 40, sorted(f.grant_types),
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
        Brand.objects.filter(default=True).count(),
        [(b.slug, b.name, b.provider_id, b.group, str(b.meta_icon), b.meta_description,
          b.meta_launch_url, PolicyBinding.objects.filter(target=b).count(),
          PolicyBinding.objects.filter(target=b, group=ig).count(),
          Application.objects.filter(slug=b.slug).count())
         for b in (Application.objects.get(slug=x) for x in ("unifi", "nas", "switch"))],
        Group.objects.filter(name="infra-users").count(),
        (f.client_secret, ps.client_secret),  # last: compared, then dropped (never printed)
    ]

# Same steps as the apply_blueprint task, without its task context.
def apply(**filt):
    for b in BlueprintInstance.objects.filter(**filt):
        imp = Importer.from_string(b.retrieve(), b.context)
        assert imp.validate()[0], b.path
        assert imp.apply(), b.path

apply(path="custom/30-branding.yaml")
before = state()
apply(path__startswith="custom/")
after = state()
same_secret = before.pop() == after.pop()
print("SAME" if before == after and same_secret else "CHANGED", before)'
result="$(ak_py "$check_py")"
expected="SAME ['authentik-default', 'Homelab', 'homelab/logo.svg', 'homelab/favicon.svg', 'homelab/background.svg', {'settings': {'theme': {'base': 'dark'}}}, 'Homelab', [('default-authentication-flow', 'homelab/background.svg'), ('default-authenticator-static-setup', 'homelab/background.svg'), ('default-authenticator-totp-setup', 'homelab/background.svg'), ('default-authenticator-webauthn-setup', 'homelab/background.svg'), ('default-invalidation-flow', 'homelab/background.svg'), ('default-provider-invalidation-flow', 'homelab/background.svg')], [('uptime-kuma', 'homelab/icons/uptime-kuma.svg', 'Uptime monitoring', 'Administration'), ('portainer', 'homelab/icons/portainer.svg', 'Docker management', 'Administration'), ('openobserve', 'homelab/icons/openobserve.svg', 'Logs and metrics', 'Administration'), ('forgejo', 'homelab/icons/forgejo.svg', 'Git forge', 'Administration'), ('radarr', 'homelab/icons/radarr.svg', 'Movies', 'NG media'), ('sonarr', 'homelab/icons/sonarr.svg', 'TV series', 'NG media'), ('bazarr', 'homelab/icons/bazarr.svg', 'Subtitles', 'NG media'), ('lidarr', 'homelab/icons/lidarr.svg', 'Music', 'NG media'), ('sabnzbd', 'homelab/icons/sabnzbd.svg', 'Usenet downloads', 'NG media'), ('prowlarr', 'homelab/icons/prowlarr.svg', 'Indexers', 'NG media'), ('h5ai', 'homelab/icons/h5ai.svg', 'File browser', 'NG media')], 'configure', ['default-authenticator-totp-setup', 'default-authenticator-webauthn-setup'], ['static', 'totp', 'webauthn'], 'forward_single', 'https://uptime.example.test', 'default-provider-authorization-implicit-consent', 'default-provider-invalidation-flow', True, 1, 'forward_single', 'https://media.example.test', 'default-provider-authorization-implicit-consent', 'default-provider-invalidation-flow', True, 'blank://blank', 1, [('radarr', 'Radarr', None, 'NG media', 'https://media.example.test/radarr', 1, 1, 1), ('sonarr', 'Sonarr', None, 'NG media', 'https://media.example.test/sonarr', 1, 1, 1), ('bazarr', 'Bazarr', None, 'NG media', 'https://media.example.test/bazarr', 1, 1, 1), ('lidarr', 'Lidarr', None, 'NG media', 'https://media.example.test/lidarr', 1, 1, 1), ('sabnzbd', 'SABnzbd', None, 'NG media', 'https://media.example.test/sabnzbd', 1, 1, 1), ('prowlarr', 'Prowlarr', None, 'NG media', 'https://media.example.test/prowlarr', 1, 1, 1), ('h5ai', 'h5ai', None, 'NG media', 'https://media.example.test', 1, 1, 1)], 'forward_single', 'https://portainer.example.test', 'default-provider-authorization-implicit-consent', 'default-provider-invalidation-flow', True, 1, 'confidential', 'portainer', True, ['authorization_code', 'refresh_token'], [('strict', 'https://portainer.example.test/')], 'authentik Self-signed Certificate', 'default-provider-authorization-implicit-consent', 'default-provider-invalidation-flow', ['email', 'openid', 'profile'], True, 'blank://blank', 1, 'forward_single', 'https://logs.example.test', 'default-provider-authorization-implicit-consent', 'default-provider-invalidation-flow', True, 1, 'confidential', 'forgejo', True, ['authorization_code', 'refresh_token'], [('strict', 'https://git.example.test/user/oauth2/authentik/callback')], 'authentik Self-signed Certificate', 'default-provider-authorization-implicit-consent', 'default-provider-invalidation-flow', ['email', 'openid', 'profile'], True, 1, True, 'https://auth.example.test', 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, [('unifi', 'UniFi', None, 'Infrastructure', 'homelab/icons/unifi.svg', 'Network controller', 'https://unifi.example.test', 1, 1, 1), ('nas', 'Synology NAS', None, 'Infrastructure', 'homelab/icons/synology.svg', 'DSM storage', 'https://nas.example.test', 1, 1, 1), ('switch', 'XGS1210-12', None, 'Infrastructure', 'homelab/icons/zyxel.svg', 'Zyxel switch', 'https://192.0.2.30', 1, 1, 1)], 1]"
[ "$result" = "$expected" ] || { tail -n 30 "$out" >&2; fail "unexpected state after apply:
  got:  $result
  want: $expected"; }

echo "OK"
