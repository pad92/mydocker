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
| `OPENOBSERVE_DATA_DIR` | Host directory mounted on `/data` (Parquet data and SQLite metadata). Its ownership is set to `PUID:PGID` by `openobserve-init` on each start. | `/srv/openobserve/data` |
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

## 2. Syslog Receiver (`openobserve-syslog`)

### Role
OpenObserve removed its built-in syslog listener in v0.16.0. This [Vector](https://vector.dev/) container receives syslog over UDP (UniFi, switches, firewalls) and forwards it to OpenObserve over HTTP, in the `syslog` stream of the `default` organization.

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

### Testing the Pipeline

[`tests/test_vector.sh`](./tests/test_vector.sh) renders the compose file with `.env.example`, runs `vector validate` on the resulting pipeline, then the unit tests of [`tests/vector_test.yaml`](./tests/vector_test.yaml) (syslog, CEF with and without syslog header, malformed CEF, field collisions). It needs Docker, Docker Compose 2.23 or later and `jq`, and makes no network call:

```bash
./tests/test_vector.sh
```

### UniFi Setup
In UniFi Network, *Settings > CyberSecure > Traffic Logging* (or *System > Remote Logging* depending on the version): enable *SIEM Server* or *Syslog*, then set the host address and port `514`.
