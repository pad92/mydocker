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

### Access Control (Authentik)

The `openobserve` router goes through the `authentik@docker` forward-auth middleware of the management stack: a browser must first log in to Authentik (with MFA) as a member of the `openobserve-users` group. The provider, application and group are created by the `20-forward-auth-apps.yaml` blueprint of the management stack, which reads this host name from `OPENOBSERVE_HOST_LOCAL` in `management/.env`. That value must equal `OPENOBSERVE_DOMAIN`.

Log shippers cannot follow a browser login, so a second router, `openobserve_ingest`, skips the middleware for the ingestion endpoints only:

- method `POST` only;
- path `/api/<org>/<stream>/_json`, `/api/<org>/<stream>/_multi`, `/api/<org>/_bulk`, `/api/<org>/v1/{logs,metrics,traces}` or `/api/<org>/prometheus/api/v1/write`, nothing else (the regex is anchored at both ends).

These requests still need the OpenObserve Basic auth credentials. The UI, the search API (`_search`) and the management API stay behind Authentik.

Limits:

- OpenObserve keeps its own login page behind Authentik: users log in twice (Authentik, then OpenObserve).
- While `authentik_server` is down, the UI is unreachable (the middleware fails closed). Ingestion keeps working.
- An Uptime Kuma HTTP monitor on `https://<OPENOBSERVE_DOMAIN>/healthz` now gets a `302` to Authentik. Accept `302` as up, or monitor the container instead.
- The `openobserve-syslog` Vector container sends to `http://openobserve:5080` on the Docker network and does not go through Traefik, so it is not affected. OTLP over gRPC is not published either.

[`tests/test_stack.sh`](./tests/test_stack.sh) checks these routers without starting anything: forward auth on the UI router, the ingest router limited to `POST` on the host, no middleware on it, its regex tested against allowed and denied paths, and no other router on the host without the middleware.

```bash
./tests/test_stack.sh
```

---

## 2. Metadata Backup (`openobserve-backup`)

### Role
Copies the SQLite metadata database (`OPENOBSERVE_DATA_DIR/db/metadata.sqlite`) to `OPENOBSERVE_BACKUP_DIR` as `metadata-<UTC time>.sqlite.gz`. This database holds users, alerts, destinations, dashboards, functions, pipelines, stream settings and the list of Parquet files.

- The copy uses the SQLite online backup API: OpenObserve keeps running, and the copy includes the changes still in the `-wal` file. Each copy passes `PRAGMA integrity_check` before it is compressed and given its final name.
- One backup every `OPENOBSERVE_BACKUP_INTERVAL_HOURS`. At startup, a backup is made right away if the newest one is older than the interval, so restarts do not pile up copies.
- After each successful backup, the `metadata-*.sqlite.gz` files older than `OPENOBSERVE_BACKUP_KEEP_DAYS` are deleted. The newest one is always kept, and other files in the directory are never touched. A failed backup deletes nothing and is retried one hour later.
- The healthcheck turns the container `unhealthy` when the newest backup is older than twice the interval.
- The container uses `python:3.13-alpine3.22` with no network, as a non-root user. Its root filesystem stays writable: Compose refuses to inject an inline config into a `read_only` service. The script is the `backup_script` entry under `configs:` in [`docker-compose.yml`](./docker-compose.yml). Compose interpolates `$` in this block too, so the script contains none.

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
OpenObserve removed its built-in syslog listener in v0.16.0. This [Vector](https://vector.dev/) container receives syslog over UDP (UniFi, switches, firewalls) and forwards it to OpenObserve over HTTP, in the `default` organization. Firewall logs of the UniFi gateway go to the `firewall` stream, see [Firewall Logs](#firewall-logs). Everything else goes to the `syslog` stream.

- RFC 3164 and RFC 5424 messages are parsed into `hostname`, `appname`, `severity`, `facility`, `message`, etc.
- Messages in another format are kept as is in `message`, with a `parse_error` field. Today these are mostly the kernel lines of the UniFi access points (`{0c1c a612} [354856.36] ...`), which carry no syslog header.
- UniFi events in CEF format (`appname` = `CEF`) are also split into fields, see [CEF Fields](#cef-fields). `message` is not changed, so searches and alerts on it keep working.
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

### CEF Fields

UniFi sends its events (firewall, IDS/IPS, Wi-Fi, VPN) as `CEF:0|Ubiquiti|UniFi Network|<version>|<id>|<name>|<severity>|key=value ...`. `parse_syslog` reads `CEF` as the `appname` and leaves the rest in `message`. The pipeline then parses it with VRL `parse_cef` and adds:

| Field | Content | Example |
| :--- | :--- | :--- |
| `cef_version` | CEF format version. | `0` |
| `cef_vendor` | Device vendor. | `Ubiquiti` |
| `cef_product` | Device product. | `UniFi Network` |
| `cef_product_version` | Product version. | `11.0.99` |
| `cef_signature_id` | Event type ID (string). | `203` |
| `cef_name` | Event name. | `Blocked by Firewall` |
| `cef_severity` | Severity 0-10, as an integer. | `4` |
| `cef_severity_label` | Only set when the severity is a word (`Low`, `High`...); `cef_severity` is then empty. | `High` |
| `cef_parse_error` | Set when the message contains `CEF:` but cannot be parsed. | |

Each `key=value` extension also becomes a field of its own, as a string: `UNIFIcategory`, `UNIFIrisk`, `UNIFIpolicyName`, `UNIFIsrcClientIp`, `src`, `dst`, `proto`, `spt`, `dpt`, `act`, `msg`, and so on depending on the event type. If an extension has the same name as a field already set by the pipeline (`appname`, `hostname`, `host_name`...), the pipeline's value is kept. OpenObserve stores field names in lower case: query `unificategory`, `unifirisk`, etc.

Example query for high-risk security events (the time range comes from the UI):

```sql
SELECT _timestamp, cef_name, unifirisk, msg FROM "syslog"
WHERE unificategory = 'Security' AND unifirisk = 'high'
```

### Firewall Logs

The UniFi gateway also sends the iptables log lines of its firewall rules, without CEF:

```text
[LAN_WAN-D-40001] DESCR="block-dns" IN=br0 OUT=eth6 MAC=... SRC=2001:db8::1 DST=2001:4860:4860::8888 LEN=80 TC=0 HOPLIMIT=63 FLOWLBL=0 PROTO=UDP SPT=41153 DPT=53 LEN=40 MARK=0x21940000
```

The pipeline splits them into fields with a `fw_` prefix, so they never mix with the `src`, `dst` and `proto` of the CEF events, and sends them to the `firewall` stream instead of `syslog`. `message` is kept as received.

| Field | Content | Example |
| :--- | :--- | :--- |
| `fw_rule` | Rule prefix of the log line. | `LAN_WAN-D-40001` |
| `fw_ruleset` | Rule set (traffic direction). | `LAN_WAN` |
| `fw_rule_id` | Rule number, as an integer. | `40001` |
| `fw_action` | `accept`, `drop` or `reject`, from the `A`, `D` or `R` letter of the prefix. | `drop` |
| `fw_action_code` | The letter itself. | `D` |
| `fw_descr` | Rule description set in UniFi. | `block-dns` |
| `fw_in`, `fw_out` | Input and output interfaces; empty when the packet is for the gateway itself. | `br0`, `eth6` |
| `fw_src`, `fw_dst` | Source and destination addresses, IPv4 or IPv6. | `2001:4860:4860::8888` |
| `fw_proto` | `TCP`, `UDP`, `ICMP`, `ICMPv6`... | `UDP` |
| `fw_spt`, `fw_dpt` | Source and destination ports, as integers. | `53` |
| `fw_len` | IP packet length, as an integer. | `80` |
| `fw_l4_len` | Layer 4 length (the second `LEN=` of the line), as an integer. | `40` |
| `fw_ttl`, `fw_hoplimit` | IPv4 TTL or IPv6 hop limit, as integers. | `63` |

Every other `KEY=value` pair becomes `fw_<key>` as a string (`fw_mac`, `fw_mark`, `fw_tos`, `fw_id`, `fw_window`, `fw_type`, `fw_code`...). A flag without a value, such as `DF` or `SYN`, becomes `true` (`fw_df`, `fw_syn`). The original packet that an ICMP error quotes between brackets is left out of the fields.

Example query for the most blocked destinations:

```sql
SELECT fw_descr, fw_dst, fw_dpt, count(*) AS hits FROM "firewall"
WHERE fw_action = 'drop'
GROUP BY fw_descr, fw_dst, fw_dpt ORDER BY hits DESC LIMIT 20
```

### Testing the Pipeline

[`tests/test_vector.sh`](./tests/test_vector.sh) renders the compose file with `.env.example`, runs `vector validate` on the resulting pipeline, then the unit tests of [`tests/vector_test.yaml`](./tests/vector_test.yaml) (syslog, CEF with and without syslog header, malformed CEF, field collisions, IPv4 and IPv6 firewall logs, routing to the `syslog` and `firewall` streams). It needs Docker, Docker Compose 2.23 or later and `jq`, and makes no network call:

```bash
./tests/test_vector.sh
```

### UniFi Setup
In UniFi Network, *Settings > CyberSecure > Traffic Logging* (or *System > Remote Logging* depending on the version): enable *SIEM Server* or *Syslog*, then set the host address and port `514`.
