# Management Stack

This stack runs Traefik, Authentik, Portainer, and Uptime Kuma.

## Shared settings

| Variable | Purpose | Default |
| --- | --- | --- |
| `CA_CERT_NAME` | CA certificate filename mounted into Traefik and Uptime Kuma | `example-root-ca.crt` |
| `MANAGEMENT_SHARE_CA_CERTIFICATES_DATA_DIR` | Host directory containing the CA certificate | `/usr/local/share/ca-certificates` |

## Traefik

Traefik routes HTTP and HTTPS traffic for the other Docker stacks. Its ACME resolver `stepca` uses the step-ca endpoint and email configured by `ACME_CA_SERVER` and `ACME_EMAIL`. `ACME_CA_SERVER` is required: Compose refuses to start without it, otherwise Traefik would fall back to Let's Encrypt. The dashboard host is set by `TRAEFIK_HOST_LOCAL`.

The static configuration is only defined by the `command` flags in `docker-compose.yml`. Traefik reads a single static source, so do not mount a `traefik.toml` at `/etc/traefik/`: Traefik would load it and silently ignore every flag, including `caserver`.

The active dynamic configuration is `traefik_dynamic.toml`. Start from `traefik_dynamic.toml.example` and keep host-specific addresses and authentication data in the ignored active file.

## Authentik

Authentik is the identity provider (SSO). It runs as three containers:

| Container | Role | Networks |
| --- | --- | --- |
| `authentik_postgresql` | PostgreSQL 16 database | `authentik` |
| `authentik_server` | Web UI, API, and the embedded outpost that answers Traefik | `authentik`, `traefik_gateway` |
| `authentik_worker` | Background tasks (e-mail, blueprints, cleanup) | `authentik` |

Redis is not used: since 2025.10, Authentik keeps its cache and task queue in PostgreSQL. No port is published on the host; Traefik is the only way in.

The Compose file follows the [official one](https://goauthentik.io/compose.yml) with these differences:

- The worker runs without `user: root` and without the Docker socket. The official file mounts them so Authentik can deploy extra outposts as containers. Forward auth with Traefik only needs the embedded outpost, and a writable Docker socket gives root on the host.
- Error reporting (Sentry) and startup analytics are disabled.
- The data lives in `MANAGEMENT_AUTHENTIK_DATA_DIR` instead of a named volume.

### Settings

| Variable | Purpose |
| --- | --- |
| `AUTHENTIK_HOST_LOCAL` | Internal host name of the Authentik UI, for example `auth.example.lan` |
| `AUTHENTIK_HOST_PUBLIC` | Optional public host name, for example `auth.example.com`. Leave empty to keep Authentik internal |
| `AUTHENTIK_SECRET_KEY` | Signs sessions and tokens. Never change it after the first start |
| `AUTHENTIK_PG_PASS` | PostgreSQL password |
| `AUTHENTIK_TAG` | Image version, pinned. Authentik no longer publishes `latest` |
| `MANAGEMENT_AUTHENTIK_DATA_DIR` | Host directory for `database/`, `data/`, `certs/`, and `custom-templates/` |

Generate each secret with:

```bash
openssl rand -base64 60 | tr -d '\n'
```

### First start

The Compose file requires `AUTHENTIK_HOST_LOCAL`, `AUTHENTIK_PG_PASS`, `AUTHENTIK_SECRET_KEY`, and `MANAGEMENT_AUTHENTIK_DATA_DIR` for the whole project. On a host whose `.env` predates Authentik, add them before running any `docker compose` command in this stack: without them, even `docker compose up -d traefik` stops with a "Set ... in .env" error.

The server and worker run as UID 1000. Create the directories with that owner before the first start. The shell does not read `.env`, so set the variable first; the `:?` makes the commands stop instead of running on `/data`, `/certs`, and `/custom-templates` when it is empty:

```bash
MANAGEMENT_AUTHENTIK_DATA_DIR=/path/to/authentik
mkdir -p "${MANAGEMENT_AUTHENTIK_DATA_DIR:?}"/{data,certs,custom-templates}
chown -R 1000:1000 "${MANAGEMENT_AUTHENTIK_DATA_DIR:?}"/{data,certs,custom-templates}
docker compose up -d authentik_postgresql authentik_server authentik_worker
```

Then open `https://<AUTHENTIK_HOST_LOCAL>/if/flow/initial-setup/` to set the password of the `akadmin` account. Do this right away: until then, anyone who reaches the URL can claim the admin account.

### Internal and public exposure

The `authentik` router answers on `AUTHENTIK_HOST_LOCAL` and the `authentik_pub` router, when the variable is set, on `AUTHENTIK_HOST_PUBLIC`. Each router has its own certificate, so if step-ca cannot validate the public name, the internal one keeps working. Publishing on the internet goes through the same path as the other public services: Cloudflare Tunnel (`cloudflared` stack) forwards the public host name to Traefik. Add the public host name to the tunnel ingress rules in the Cloudflare dashboard; nothing in this stack opens a port.

**Pick one canonical URL.** An identity provider does not behave like an ordinary web app when it has two names:

- **Sessions.** The login cookie is set per host. A user logged in on `auth.example.lan` is not logged in on `auth.example.com`.
- **Passkeys (WebAuthn).** A passkey is bound to the domain it was created on. A passkey registered on `auth.example.lan` does not work on `auth.example.com`, and the reverse.
- **OIDC.** The issuer URL of a provider contains the host name the request came on. An application configured with the `.lan` issuer rejects tokens issued through the public name.
- **Forward auth.** The embedded outpost redirects browsers to a single Authentik URL. If that URL is the `.lan` one, a visitor coming from the internet is sent to a host name they cannot resolve.

The setup that avoids all four problems: use the public name everywhere (OIDC applications, outpost, passkeys), and make it resolve to Traefik on the LAN with a DNS rewrite in AdGuard (split-horizon DNS). LAN traffic then never leaves the network, and `auth.example.lan` stays as a fallback to reach the admin UI if the public DNS or the tunnel is down. The URL the outpost uses (`authentik_host`) is set by the forward auth blueprint from `AUTHENTIK_HOST_LOCAL`: to switch to the public name, change the `BLUEPRINT_AUTHENTIK_HOST` line of `authentik_worker` in `docker-compose.yml`, not the admin UI, which the next blueprint apply would overwrite.

**Before publishing**, harden the instance. Once Authentik is public, it is the front door of every service it protects:

- MFA is enforced for every user by the `10-mfa.yaml` blueprint (see [Blueprints](#blueprints)). Set a strong `akadmin` password, or replace `akadmin` with a named admin account and deactivate `akadmin`.
- Keep the default reputation policy, which slows down brute force by client IP, and check that the logs show real client IPs. Behind Cloudflare Tunnel, Traefik sees `cloudflared` as the client. Traefik only keeps the `X-Forwarded-For` header sent by `cloudflared` if the source address of `cloudflared` is in `--entrypoints.websecure.forwardedHeaders.trustedIPs`. That flag is not set today: add it with the exact source address of `cloudflared` (host network, so a loopback or host address) after checking it in the Traefik access log. Never trust a wide range: any client in it could fake its IP.
- Disable enrollment and recovery flows you do not use, so that the public host offers nothing but login.

### Protecting a service with Traefik forward auth

Forward auth works like this: for each request on a protected router, Traefik first asks Authentik (`/outpost.goauthentik.io/auth/traefik`) whether the user is logged in. If not, Authentik answers with a redirect to its login page. If yes, Traefik forwards the request to the service and adds `X-authentik-*` headers (user name, e-mail, groups).

Three pieces are needed. The first two are already in this stack.

1. The `authentik` middleware, declared in the labels of `authentik_server`. Other stacks use it as `authentik@docker`.
2. The `authentik_outpost` router. It sends `/outpost.goauthentik.io/` on any host to Authentik, which receives the login callback there. Its priority (1000) keeps it ahead of the service routers. Because it has no `Host()`, it also answers on public host names forwarded by Cloudflare Tunnel, even when `AUTHENTIK_HOST_PUBLIC` is empty: the outpost endpoints are reachable from the internet, though the login itself happens on the Authentik host. To keep Authentik strictly internal, replace the rule with `Host(...) && PathPrefix(...)` listing only the protected hosts.
3. A provider and an application in Authentik, plus the middleware on the service router. Both are per service, see below. Uptime Kuma is already set up this way.

Per service:

1. In `authentik/blueprints/20-forward-auth-apps.yaml`, copy the Uptime Kuma entries: a group, a **Proxy Provider** in `forward_single` mode, an application, and a policy binding between them. Take the host name from a new `BLUEPRINT_*` variable on `authentik_worker`, never write it in the file.
2. Add the provider to the `providers` list of the embedded outpost at the end of the file. Without this step, Authentik answers 404 and the service stays unreachable.
3. Run `./tests/test_blueprints.sh` (extend its checks for the new service), then `docker compose up -d authentik_worker`.
4. Add the middleware to the HTTPS router of the service, for example in its `docker-compose.yml`:

   ```yaml
   traefik.http.routers.uptime.middlewares: "authentik@docker"
   ```

   If the router already has middlewares, list them separated by commas. Put `authentik@docker` first so the request is authenticated before anything else touches it.

For a service in the file provider (`traefik_dynamic.toml`, for example Proxmox), use the same name:

```toml
[http.routers.proxmox]
  middlewares = ["authentik@docker"]
```

The **Forward auth (domain level)** mode protects many hosts with a single provider and shares the session cookie across a domain such as `example.lan`. It saves configuration but gives every protected service the same access rules.

### Behaviour and limits

- **Fail closed.** If `authentik_server` is stopped, the `authentik@docker` middleware disappears and Traefik disables the routers that reference it: the protected services answer 404 instead of being served without authentication. Keep this in mind for Portainer and the Traefik dashboard: protecting them with Authentik makes them unreachable while Authentik is down.
- **Monitoring.** Uptime Kuma probes a protected service through Traefik and gets the login redirect. Check the service on its internal address, or accept the 302 status as healthy.
- **Uptime Kuma push monitors.** Uptime Kuma itself is protected, except `/api/push/`: the `uptime_push` router serves that path without the middleware, so scripts and cron jobs can still report heartbeats. Push URLs carry their own token.
- **APIs and mobile apps.** Clients that cannot follow a browser login (API tokens, mobile apps, WebDAV) break behind forward auth. For those services, use the native OIDC/SAML support of the application with Authentik as provider, or leave the API path outside the protected router.
- **Trusted headers.** The service must trust the `X-authentik-*` headers only because they come from Traefik. Do not publish a protected service on a host port, or a client could reach it directly and forge those headers.
- **Backups.** Back up `MANAGEMENT_AUTHENTIK_DATA_DIR` and `AUTHENTIK_SECRET_KEY` together. For the database, prefer a `pg_dump` over a copy of the files of a running server.
- **Upgrades.** Change `AUTHENTIK_TAG` one minor version at a time and read the [release notes](https://docs.goauthentik.io/releases/) first: migrations are not reversible.

### Blueprints

The Authentik configuration is versioned as [blueprints](https://docs.goauthentik.io/customize/blueprints/) in `authentik/blueprints/`, mounted read-only on the worker at `/blueprints/custom`. The worker applies them at start and every time a file changes.

| File | Effect |
| --- | --- |
| `10-mfa.yaml` | The default authentication flow asks for a second factor (TOTP, WebAuthn, or a static recovery code). A user without one must enroll TOTP or WebAuthn at the next login. |
| `20-forward-auth-apps.yaml` | Forward auth providers and applications (Uptime Kuma), their access groups, and the provider list of the embedded outpost. |

How they behave:

- **No private data.** The files contain no host name, login, or address. Host names come from the `BLUEPRINT_*` environment variables of `authentik_worker`, built from `.env`, and `tests/test_stack.sh` fails if a domain, URL, e-mail, or IP shows up in them.
- **Applied when the file changes.** Authentik re-applies a blueprint when the hash of its file changes, not when an environment variable does. After changing a host name in `.env`, force an apply under *Customization > Blueprints* (Apply button) or with `docker compose exec authentik_worker ak apply_blueprint custom/20-forward-auth-apps.yaml`.
- **The file wins.** Each apply resets the fields it declares. Change those fields in the file, not in the admin UI. Fields it does not declare (users, group members, other applications) stay as set in the UI.
- **Fail closed.** An application is only reachable by members of its group, for example `uptime-kuma-users`. Nobody is a member at first, administrators included: add users under *Directory > Groups*.
- **Removing an entry from a file does not delete the object.** Delete it in the admin UI as well.

`tests/test_blueprints.sh` applies the blueprints on a throw-away Authentik (PostgreSQL and worker on an internal Docker network, no published port, removed at the end), checks the resulting objects, and applies them a second time to check that nothing is duplicated. It pulls the Authentik and PostgreSQL images if needed and takes one to three minutes.

## Portainer

Portainer manages the Docker environment. Set `MANAGEMENT_PORTAINER_DATA_DIR` to its existing data directory and `PORTAINER_HOST_LOCAL` to its host name.

## Uptime Kuma

Uptime Kuma monitors hosts and services. Set `MANAGEMENT_UPTIME_KUMA_DATA_DIR` to its existing data directory and `UPTIME_HOST_LOCAL` to its host name.

## Other example settings

The `.env.example` file also contains host names and settings for optional services kept commented out in the Compose file, including Homarr, Homepage, and the mirror.
