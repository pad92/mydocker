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
| `GRAMPSWEB_TREE` | `Gramps Web` | Tree name, created on first start if missing |
| `GRAMPSWEB_DATA_DIR` | required | Host directory for the app data (see below) |
| `GRAMPSWEB_MEDIA_DIR` | required | Host directory for photos and documents |
| `GUNICORN_NUM_WORKERS` | `8` | Web workers; each one costs CPU and RAM |
| `GRAMPSWEB_CELERY_CONCURRENCY` | `2` | Parallel tasks of the worker |

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

Other settings (SMTP for password resets, OIDC, registration, AI chat) are
`GRAMPSWEB_*` variables listed in the
[configuration page](https://www.grampsweb.org/install_setup/configuration/).
Add them to the `x-grampsweb` block of `docker-compose.yml` so the worker gets
them too. Most of them can also be set from the web interface.

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
