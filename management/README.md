# Management Stack

This stack runs Traefik, Authentik, Portainer, and Uptime Kuma.

## Shared settings

| Variable | Purpose | Default |
| --- | --- | --- |
| `CA_CERT_NAME` | CA certificate filename mounted into Traefik and Uptime Kuma | `home-lan-root-ca.crt` |
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
| `AUTHENTIK_HOST_LOCAL` | Internal host name of the Authentik UI, for example `auth.home.lan` |
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

The server and worker run as UID 1000. Create the directories with that owner before the first start:

```bash
mkdir -p "$MANAGEMENT_AUTHENTIK_DATA_DIR"/{data,certs,custom-templates}
chown -R 1000:1000 "$MANAGEMENT_AUTHENTIK_DATA_DIR"/{data,certs,custom-templates}
docker compose up -d authentik_postgresql authentik_server authentik_worker
```

Then open `https://<AUTHENTIK_HOST_LOCAL>/if/flow/initial-setup/` to set the password of the `akadmin` account. Do this right away: until then, anyone who reaches the URL can claim the admin account.

### Internal and public exposure

The `authentik` router answers on `AUTHENTIK_HOST_LOCAL` and, when set, on `AUTHENTIK_HOST_PUBLIC`. Both names share one router, so Traefik asks step-ca for one certificate that covers both. Publishing on the internet goes through the same path as the other public services: Cloudflare Tunnel (`cloudflared` stack) forwards the public host name to Traefik. Add the public host name to the tunnel ingress rules in the Cloudflare dashboard; nothing in this stack opens a port.

**Pick one canonical URL.** An identity provider does not behave like an ordinary web app when it has two names:

- **Sessions.** The login cookie is set per host. A user logged in on `auth.home.lan` is not logged in on `auth.example.com`.
- **Passkeys (WebAuthn).** A passkey is bound to the domain it was created on. A passkey registered on `auth.home.lan` does not work on `auth.example.com`, and the reverse.
- **OIDC.** The issuer URL of a provider contains the host name the request came on. An application configured with the `.lan` issuer rejects tokens issued through the public name.
- **Forward auth.** The embedded outpost redirects browsers to a single Authentik URL. If that URL is the `.lan` one, a visitor coming from the internet is sent to a host name they cannot resolve.

The setup that avoids all four problems: use the public name everywhere (OIDC applications, outpost, passkeys), and make it resolve to Traefik on the LAN with a DNS rewrite in AdGuard (split-horizon DNS). LAN traffic then never leaves the network, and `auth.home.lan` stays as a fallback to reach the admin UI if the public DNS or the tunnel is down. Set the URL the outpost uses under *Applications > Outposts > authentik Embedded Outpost > Advanced settings*, key `authentik_host`.

**Before publishing**, harden the instance. Once Authentik is public, it is the front door of every service it protects:

- Enforce MFA (WebAuthn or TOTP) in the authentication flow, at least for administrators, and set a strong `akadmin` password, or replace `akadmin` with a named admin account.
- Keep the default reputation policy, which slows down brute force by client IP, and check that the logs show real client IPs. Behind Cloudflare Tunnel, Traefik sees `cloudflared` as the client. Traefik only keeps the `X-Forwarded-For` header sent by `cloudflared` if the source address of `cloudflared` is in `--entrypoints.websecure.forwardedHeaders.trustedIPs`. That flag is not set today: add it with the exact source address of `cloudflared` (host network, so a loopback or host address) after checking it in the Traefik access log. Never trust a wide range: any client in it could fake its IP.
- Disable enrollment and recovery flows you do not use, so that the public host offers nothing but login.

### Protecting a service with Traefik forward auth

Forward auth works like this: for each request on a protected router, Traefik first asks Authentik (`/outpost.goauthentik.io/auth/traefik`) whether the user is logged in. If not, Authentik answers with a redirect to its login page. If yes, Traefik forwards the request to the service and adds `X-authentik-*` headers (user name, e-mail, groups).

Three pieces are needed. The first two are already in this stack.

1. The `authentik` middleware, declared in the labels of `authentik_server`. Other stacks use it as `authentik@docker`.
2. The `authentik_outpost` router. It sends `/outpost.goauthentik.io/` on any host to Authentik, which receives the login callback there. Its priority (1000) keeps it ahead of the service routers.
3. A provider and an application in Authentik, plus the middleware on the service router. Both are per service, see below.

Per service:

1. In Authentik, under *Applications > Providers*, create a **Proxy Provider** in **Forward auth (single application)** mode, with the external URL of the service (for example `https://uptime.home.lan`).
2. Under *Applications > Applications*, create an application that uses this provider. Restrict access with a policy or group binding if needed.
3. Under *Applications > Outposts*, edit the **authentik Embedded Outpost** and add the application to it. Without this step, Authentik answers 404 and the service stays unreachable.
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

The **Forward auth (domain level)** mode protects many hosts with a single provider and shares the session cookie across a domain such as `home.lan`. It saves configuration but gives every protected service the same access rules.

### Behaviour and limits

- **Fail closed.** If `authentik_server` is stopped, the `authentik@docker` middleware disappears and Traefik disables the routers that reference it: the protected services answer 404 instead of being served without authentication. Keep this in mind for Portainer and the Traefik dashboard: protecting them with Authentik makes them unreachable while Authentik is down.
- **Monitoring.** Uptime Kuma probes a protected service through Traefik and gets the login redirect. Check the service on its internal address, or accept the 302 status as healthy.
- **APIs and mobile apps.** Clients that cannot follow a browser login (API tokens, mobile apps, WebDAV) break behind forward auth. For those services, use the native OIDC/SAML support of the application with Authentik as provider, or leave the API path outside the protected router.
- **Trusted headers.** The service must trust the `X-authentik-*` headers only because they come from Traefik. Do not publish a protected service on a host port, or a client could reach it directly and forge those headers.
- **Backups.** Back up `MANAGEMENT_AUTHENTIK_DATA_DIR` and `AUTHENTIK_SECRET_KEY` together. For the database, prefer a `pg_dump` over a copy of the files of a running server.
- **Upgrades.** Change `AUTHENTIK_TAG` one minor version at a time and read the [release notes](https://docs.goauthentik.io/releases/) first: migrations are not reversible.

## Portainer

Portainer manages the Docker environment. Set `MANAGEMENT_PORTAINER_DATA_DIR` to its existing data directory and `PORTAINER_HOST_LOCAL` to its host name.

## Uptime Kuma

Uptime Kuma monitors hosts and services. Set `MANAGEMENT_UPTIME_KUMA_DATA_DIR` to its existing data directory and `UPTIME_HOST_LOCAL` to its host name.

## Other example settings

The `.env.example` file also contains host names and settings for optional services kept commented out in the Compose file, including Homarr, Homepage, and the mirror.
