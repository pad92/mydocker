# OpenObserve Stack

This stack deploys the following service:

## 1. OpenObserve (`openobserve`)

### Role
Single-node observability platform for logs, metrics and traces. It ingests data over HTTP (Elasticsearch-compatible bulk API, OTLP/HTTP, Prometheus remote write) and stores it as Parquet files under `/data`, with SQLite metadata (`ZO_LOCAL_MODE` default).

The web UI and the HTTP ingestion API are both served on port `5080` and published through Traefik only. No host port is exposed.

### External Links
- **Official Project**: [https://openobserve.ai/](https://openobserve.ai/)
- **Source Code**: [https://github.com/openobserve/openobserve](https://github.com/openobserve/openobserve) (AGPL-3.0)
- **Docker Image Maintainer**: [OpenObserve on Amazon ECR Public](https://gallery.ecr.aws/zinclabs/openobserve)
- **Environment Variables Reference**: [https://openobserve.ai/docs/environment-variables/](https://openobserve.ai/docs/environment-variables/)

### Service-Specific Configuration Variables

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `OPENOBSERVE_VERSION` | Image tag. | `v1.1.1` |
| `OPENOBSERVE_DOMAIN` | Hostname routed by Traefik. Also used to build `ZO_WEB_URL`. | `openobserve.example.com` |
| `OPENOBSERVE_DATA_DIR` | Host directory mounted on `/data` (Parquet data and SQLite metadata). Its ownership is set to `1030:100` by `openobserve-init` on each start. | `/srv/openobserve/data` |
| `ZO_ROOT_USER_EMAIL` | Email of the root user, created on first start. | `admin@example.com` |
| `ZO_ROOT_USER_PASSWORD` | Password of the root user, created on first start. 8 to 128 characters with a lowercase letter, an uppercase letter, a digit and a special character, otherwise the container exits on startup. | `CHANGEME` |
| `ZO_COMPACT_DATA_RETENTION_DAYS` | Days of data kept before automatic deletion (minimum 3). Can be overridden per stream in the UI. | `30` |

### Settings Fixed in the Compose File

| Variable | Value | Reason |
| :--- | :--- | :--- |
| `ZO_TELEMETRY` | `false` | Upstream sends anonymous usage data by default. |
| `ZO_COOKIE_SECURE_ONLY` | `true` | The UI is only reachable over HTTPS through Traefik. |
| `ZO_DATA_DIR` | `/data` | Matches the volume mount. |

### First Deployment

OpenObserve runs as `1030:100`. Before it starts, the one-shot `openobserve-init` container (busybox, root, no network) gives every file in `OPENOBSERVE_DATA_DIR` that is not already owned by `1030:100` to that user. This covers a directory created as root by Docker and files left by an earlier root run, which otherwise make OpenObserve exit with `create cache dir /data/cache/: Permission denied`. Symlinks are changed themselves, never their targets.

```bash
docker compose up -d
curl -fsS "https://$OPENOBSERVE_DOMAIN/healthz"
```

### Operational Notes
- The image is distroless (no shell, no curl), so the stack defines no container healthcheck. Monitor `https://<OPENOBSERVE_DOMAIN>/healthz` from Uptime Kuma instead.
- `ZO_ROOT_USER_EMAIL` and `ZO_ROOT_USER_PASSWORD` are only read when the root user does not exist yet. Changing them in `.env` afterwards has no effect: change the password from the UI instead.
- The upstream retention default is 3650 days. Size `OPENOBSERVE_DATA_DIR` according to the retention you set.
- OTLP over gRPC (port `5081`) is not published. Add a Traefik TCP/h2c route or a host port if a client needs it; OTLP over HTTP works through the existing route at `https://<OPENOBSERVE_DOMAIN>/api/<org>/v1/{logs,metrics,traces}`.
- Ingestion clients authenticate with HTTP Basic auth. The ready-to-use credentials are shown in the UI under *Data Sources*.
