# OpenObserve Stack

This stack deploys the following services:

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
| `OPENOBSERVE_VERSION` | Image tag. | `v1.1.2` |
| `OPENOBSERVE_DOMAIN` | Hostname routed by Traefik. Also used to build `ZO_WEB_URL`. | `openobserve.example.com` |
| `OPENOBSERVE_DATA_DIR` | Host directory mounted on `/data` (Parquet data and SQLite metadata; `openobserve-backup` copies the metadata). Its ownership is set to `PUID:PGID` by `openobserve-init` on each start. | `/srv/openobserve/data` |
| `PGID` | Group ID matching host permissions to run the container. | *None (empty)* |
| `PUID` | User ID matching host permissions to run the container. | *None (empty)* |
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

OpenObserve runs as `PUID:PGID`. Before it starts, the one-shot `openobserve-init` container (busybox, root, no network) gives every file in `OPENOBSERVE_DATA_DIR` that is not already owned by `PUID:PGID` to that user. This covers a directory created as root by Docker and files left by an earlier root run, which otherwise make OpenObserve exit with `create cache dir /data/cache/: Permission denied`. Symlinks are changed themselves, never their targets.

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

---

## 2. Metadata Backup (`openobserve-backup`)

### Role
Copies the SQLite metadata database (`OPENOBSERVE_DATA_DIR/db/metadata.sqlite`) to `OPENOBSERVE_BACKUP_DIR` as `metadata-<UTC time>.sqlite.gz`. This database holds users, alerts, destinations, dashboards, functions, pipelines, stream settings and the list of Parquet files.

- The copy uses the SQLite online backup API: OpenObserve keeps running, and the copy includes the changes still in the `-wal` file. Each copy passes `PRAGMA integrity_check` before it is compressed and given its final name.
- One backup every `OPENOBSERVE_BACKUP_INTERVAL_HOURS`. At startup, a backup is made right away if the newest one is older than the interval, so restarts do not pile up copies.
- After each successful backup, the `metadata-*.sqlite.gz` files older than `OPENOBSERVE_BACKUP_KEEP_DAYS` are deleted. The newest one is always kept, and other files in the directory are never touched. A failed backup deletes nothing and is retried one hour later.
- The healthcheck turns the container `unhealthy` when the newest backup is older than twice the interval.
- The container uses `python:3.13-alpine3.22` with no network and a read-only root filesystem. The script is the `backup_script` entry under `configs:` in [`docker-compose.yml`](./docker-compose.yml). Compose interpolates `$` in this block too, so the script contains none.

The Parquet files (`OPENOBSERVE_DATA_DIR/stream/`) are not copied: with 30 days of retention they can weigh tens of GB. They are written once and then only deleted by compaction, so the host backup tool (rsync, restic, Hyper Backup...) can copy `OPENOBSERVE_DATA_DIR/stream/` as is. Include `OPENOBSERVE_BACKUP_DIR` in that host backup as well, since a copy kept on the same disk does not survive a disk failure. `cache/`, `tmp/` and `mmdb/` are rebuilt by OpenObserve.

### Service-Specific Configuration Variables

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `OPENOBSERVE_BACKUP_DIR` | Host directory mounted on `/backup`. Ownership set to `PUID:PGID` by `openobserve-init`. Preferably on another disk than `OPENOBSERVE_DATA_DIR`. | `/srv/openobserve/backup` |
| `OPENOBSERVE_BACKUP_INTERVAL_HOURS` | Hours between two backups. | `24` |
| `OPENOBSERVE_BACKUP_KEEP_DAYS` | Days a backup is kept. | `14` |

### Manual Backup

Before an upgrade, for example:

```bash
docker exec openobserve-backup python /opt/openobserve-backup.py --once
```

### Restore

The metadata lists the Parquet files of each stream. Restore it into the same `OPENOBSERVE_DATA_DIR`, with its `stream/` directory, or with a `stream/` directory restored from the same time. Logs written after the backup are no longer listed and disappear from searches. Parquet files that compaction or retention deleted after the backup are still listed, so searches over their time range may return errors.

1. Stop `openobserve` (Portainer, or `docker stop openobserve`). `openobserve-syslog` can keep running: Vector retries and loses nothing for a few minutes.
2. Move the current database aside with its `-wal` and `-shm` files, then restore the chosen backup. A `-wal` file left next to the restored database would be replayed on it by SQLite.

   ```bash
   cd "$OPENOBSERVE_DATA_DIR/db"
   mkdir -p ../db.before-restore && mv metadata.sqlite* ../db.before-restore/
   gunzip -c "$OPENOBSERVE_BACKUP_DIR/metadata-20260101T030000Z.sqlite.gz" > metadata.sqlite
   ```

3. Redeploy the stack, or `docker start openobserve-init openobserve`. `openobserve-init` gives the restored file back to `PUID:PGID`.
4. Check `https://<OPENOBSERVE_DOMAIN>/healthz`, then the alerts and dashboards in the UI. Delete `db.before-restore/` once everything works.

### Testing the Backup

[`tests/test_backup.sh`](./tests/test_backup.sh) runs the script, as Compose renders it with `.env.example`, against a throwaway SQLite database in WAL mode: missing database, uncheckpointed rows, retention, healthcheck and invalid settings. It needs Docker, Docker Compose 2.23 or later and `jq`.

```bash
./tests/test_backup.sh
```

---

## 3. Syslog Receiver (`openobserve-syslog`)

### Role
OpenObserve removed its built-in syslog listener in v0.16.0. This [Vector](https://vector.dev/) container receives syslog over UDP (UniFi, switches, firewalls) and forwards it to OpenObserve over HTTP, in the `syslog` stream of the `default` organization.

- RFC 3164 and RFC 5424 messages are parsed into `hostname`, `appname`, `severity`, `facility`, `message`, etc.
- Messages in another format (UniFi CEF, for example) are kept as is in `message`, with a `parse_error` field.
- `_timestamp` is the time Vector received the message. The time sent by the device is kept in `syslog_timestamp`: device clocks drift, RFC 3164 has no year, and OpenObserve rejects events that are too old.
- `source_ip` is the address of the sending device.
- `host_name` names the sender like the `host_name` of the other streams (the FQDN of the hosts): its entry in `OPENOBSERVE_SYSLOG_SENDERS`, else its syslog `hostname` in lower case, else its IP. `device_vendor` comes from the same entry.

The pipeline is the `vector_config` entry under `configs:` at the end of [`docker-compose.yml`](./docker-compose.yml), mounted on `/etc/vector/vector.yaml`. It is inline rather than a `./vector.yaml` bind mount because Portainer resolves relative paths on its own disk: Docker then creates an empty directory on the host and the deployment fails with `mkdirat etc/vector/vector.yaml: file exists`. Compose interpolates `$` in this block, so write `$$` for a literal `$`. Inline `configs` need Docker Compose 2.23 or later. Vector 0.61 no longer expands `${VAR}` in its configuration, so the ingestion credentials reach it as Compose secrets (`/run/secrets`), not as environment variables.

### External Links
- **Official Project**: [https://vector.dev/](https://vector.dev/)
- **Docker Image Maintainer**: [Datadog (timberio/vector)](https://hub.docker.com/r/timberio/vector)
- **OpenObserve syslog documentation**: [https://openobserve.ai/docs/ingestion/logs/syslog/](https://openobserve.ai/docs/ingestion/logs/syslog/)

### Service-Specific Configuration Variables

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `VECTOR_VERSION` | Vector version (the `-distroless-libc` suffix is added by the compose file). | `0.61.0` |
| `OPENOBSERVE_SYSLOG_PORT` | UDP port published on the host. Nothing else on the host may listen on it (rsyslog, for example). | `514` |
| `OPENOBSERVE_INGEST_USER` | OpenObserve user used to send the logs. | `admin@example.com` |
| `OPENOBSERVE_INGEST_PASSWORD` | Its ingestion passcode, shown in the UI under *Data Sources*. Prefer it to the account password. | `CHANGEME` |
| `OPENOBSERVE_SYSLOG_SENDERS` | Known senders, one JSON line keyed by source IP: `name` (FQDN, the `host_name` field) and `vendor` (`device_vendor`). Compose writes it into the pipeline; empty or invalid JSON means no table. | `{"192.0.2.1":{"name":"gw.example.com","vendor":"unifi"}}` |

### UniFi Setup
In UniFi Network, *Settings > CyberSecure > Traffic Logging* (or *System > Remote Logging* depending on the version): enable *SIEM Server* or *Syslog*, then set the host address and port `514`.
