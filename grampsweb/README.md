# Gramps Web

This stack runs [Gramps Web](https://www.grampsweb.org/), a web app for
genealogy built on Gramps, behind Traefik. It follows the
[official docker-compose.yml](https://www.grampsweb.org/install_setup/deployment/):
the same image (`ghcr.io/gramps-project/grampsweb`, tag `latest` by default),
a Celery worker for long tasks and Valkey as broker. The external network
`traefik_gateway` and the certificate resolver `stepca` must already exist.
HTTP redirects to HTTPS.

| Service | Image | Role |
| --- | --- | --- |
| `grampsweb` | `ghcr.io/gramps-project/grampsweb:${GRAMPSWEB_VERSION:-latest}` | Web app and API (gunicorn, port 5000) |
| `grampsweb_celery` | same image | Background tasks: imports, exports, reports, e-mails |
| `grampsweb_redis` | `docker.io/valkey/valkey:${GRAMPSWEB_VALKEY_VERSION:-8-alpine}` | Celery broker and rate-limit store |

## Differences from the official file

- Named volumes become bind mounts under `GRAMPSWEB_DATA_DIR`, and the media
  under `GRAMPSWEB_MEDIA_DIR`, so they can be backed up with the host.
- No published port: Traefik serves `GRAMPSWEB_DOMAIN` over HTTPS, and
  `GRAMPSWEB_BASE_URL` is `https://<GRAMPSWEB_DOMAIN>`.
- `GRAMPSWEB_PROXY_FIX_X_FOR=1`, so that Gramps Web sees the client IP
  forwarded by Traefik instead of the proxy's.
- Only `grampsweb` joins `traefik_gateway`. The worker and Valkey stay on the
  internal `grampsweb` network.

## Configuration

Copy `.env.example` to `.env`, fill it in and run `chmod 600 .env`.

| Variable | Default | Use |
| --- | --- | --- |
| `GRAMPSWEB_VERSION` | `latest` | Image tag of Gramps Web |
| `GRAMPSWEB_VALKEY_VERSION` | `8-alpine` | Image tag of Valkey |
| `GRAMPSWEB_DOMAIN` | required | Traefik host and base of `GRAMPSWEB_BASE_URL` |
| `AUTHENTIK_DOMAIN` | required | Authentik host, base of the OIDC issuer |
| `GRAMPSWEB_OIDC_CLIENT_SECRET` | required | Client secret of the Authentik provider |
| `GRAMPSWEB_TREE` | `Gramps Web` | Tree name, created on first start if missing |
| `GRAMPSWEB_DATA_DIR` | required | Host directory for the app data (see below) |
| `GRAMPSWEB_MEDIA_DIR` | required | Host directory for photos and documents |
| `GUNICORN_NUM_WORKERS` | `8` | Web workers; each one costs CPU and RAM |
| `GRAMPSWEB_CELERY_CONCURRENCY` | `2` | Parallel tasks of the worker |
| `GRAMPSWEB_EMAIL_HOST` | empty (e-mail off) | SMTP server, `smtp.protonmail.ch` for Proton Mail |
| `GRAMPSWEB_EMAIL_PORT` | `587` | SMTP port |
| `GRAMPSWEB_EMAIL_USE_STARTTLS` | `true` | STARTTLS, as Proton Mail expects on 587 |
| `GRAMPSWEB_EMAIL_USE_SSL` | `false` | Implicit TLS, for port 465 only |
| `GRAMPSWEB_EMAIL_HOST_USER` | empty | SMTP user: the Proton address of the token |
| `GRAMPSWEB_EMAIL_HOST_PASSWORD` | empty | SMTP password: the Proton SMTP token |
| `GRAMPSWEB_DEFAULT_FROM_EMAIL` | empty | Sender of the e-mails, the same address |

Subdirectories of `GRAMPSWEB_DATA_DIR`, created by Docker on first start:

| Host | Container | Content |
| --- | --- | --- |
| `users` | `/app/users` | User accounts (SQLite) |
| `grampsdb` | `/root/.gramps/grampsdb` | Family tree database |
| `indexdir` | `/app/indexdir` | Search index |
| `thumbnail_cache` | `/app/thumbnail_cache` | Thumbnails |
| `cache` | `/app/cache` | Report and export caches |
| `secret` | `/app/secret` | Flask secret key |
| `tmp` | `/tmp` | Files shared by the web app and the worker |

`GRAMPSWEB_SECRET_KEY` is not set: on first start the image's entrypoint
writes a random key to `secret/secret` and reuses it afterwards. Back that
file up with the rest. Deleting it logs every user out.

Proton Mail sends over SMTP only on a paid plan, from a custom-domain
address, with an SMTP token generated in Settings > IMAP/SMTP > SMTP tokens
(the account password does not work). Under Portainer, enter these values in
the stack's environment variables, then redeploy the stack.

Other settings (registration, AI chat) are
`GRAMPSWEB_*` variables listed in the
[configuration page](https://www.grampsweb.org/install_setup/configuration/).
Add them to the `x-grampsweb` block of `docker-compose.yml` so the worker gets
them too. Most of them can also be set from the web interface.

## Sign-in with Authentik

Gramps Web signs users in with OpenID Connect against the `grampsweb`
application that the blueprint of the `management` stack creates. The login
page shows an "Authentik" button next to the local login, which stays on:
the first-run owner account and any local account keep working, for example
when Authentik is down. Traefik applies no forward auth to this host, since
the API and the OIDC callback must reach Gramps Web directly.

The role comes from the Authentik groups in the `groups` claim, at each
sign-in, the highest one winning:

| Authentik group | Gramps Web role |
| --- | --- |
| `grampsweb-owners` | Owner |
| `grampsweb-editors` | Editor |
| `grampsweb-members` | Member |

Authentik only lets members of these groups reach the application: a user
removed from all three can no longer sign in with Authentik, but the Gramps
Web account stays as it was until an owner disables it. A
role changed in the Gramps Web interface for an OIDC user is overwritten at
the next sign-in: change the group in Authentik instead.

The first OIDC sign-in creates a new Gramps Web account. It is not merged
with a local account of the same name or e-mail address.

Setup:

1. Set `GRAMPSWEB_HOST_LOCAL` in the `.env` of the `management` stack to the
   value of `GRAMPSWEB_DOMAIN`, then redeploy it. The redirect URI
   `https://<GRAMPSWEB_DOMAIN>/api/oidc/callback/custom` is built from it.
2. In Authentik, copy the client secret of the *Gramps Web* provider
   (Applications > Providers) into `GRAMPSWEB_OIDC_CLIENT_SECRET`, in the
   Portainer stack variables. The stack does not deploy while it is empty.
3. Add the users to one of the three groups (Directory > Groups).
4. Redeploy this stack.

Gramps Web reads its `GRAMPSWEB_*` variables as JSON: write booleans in
lowercase (`true`), since `True` is read as a non-empty string. Authentik
uses a certificate of the internal CA: the host bundle
`/etc/ssl/certs/ca-certificates.crt` is mounted read-only and
`REQUESTS_CA_BUNDLE` points at it, so the host must trust that CA.

`tests/test_stack.sh` renders the Compose file with test values and checks
this configuration (OIDC settings, roles, CA bundle, no forward auth, local
login kept, failure without the secret). It needs Docker Compose and `jq`.

## First start

```sh
docker compose up -d
```

Open `https://<GRAMPSWEB_DOMAIN>`. The first-run wizard creates the owner
account and can import an existing `.gramps` or GEDCOM file.

## Updates

With `latest`, `docker compose pull && docker compose up -d` moves to the
newest release. Pin a version in `GRAMPSWEB_VERSION` to choose when to
upgrade. The user database is migrated by the entrypoint at each start.
