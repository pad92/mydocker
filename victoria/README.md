# Victoria Stack

This stack replaces OpenObserve. It deploys the following services:

- `victorialogs`: log database, UI on `logs.<domain>`.
- `victoriametrics`: metric database, UI on `metrics.<domain>`.
- `vector`: the only writer of `victorialogs`. It receives OTLP logs from the collectors and UDP syslog from network devices, parses them and sends them on.
- `vmalert-logs` and `vmalert-metrics`: alert rules on the logs (LogsQL) and on the metrics (MetricsQL).
- `alertmanager`: groups the alerts and sends them as SMS through Vector and the Free Mobile API.
- `grafana` (container `victoria-grafana`): Authentik and Proxmox dashboards, UI on `grafana.<domain>`.
- `victoria-init`: one-shot container that fixes the ownership of the data directories.

## Service-Specific Configuration Variables

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `VICTORIA_LOGS_VERSION` | VictoriaLogs image tag. | `v1.54.0` |
| `VICTORIA_METRICS_VERSION` | VictoriaMetrics image tag. | `v1.156.0` |
| `VECTOR_VERSION` | Vector version (the compose file adds the `-distroless-libc` suffix). | `0.61.0` |
| `VMALERT_VERSION` | vmalert image tag, for both instances. | `v1.156.0` |
| `ALERTMANAGER_VERSION` | Alertmanager image tag. | `v0.35.1` |
| `GRAFANA_VERSION` | Grafana image tag. | `13.2.7` |
| `GRAFANA_LOGS_PLUGIN_VERSION` | Version of the `victoriametrics-logs-datasource` Grafana plugin. | `0.34.0` |
| `VICTORIA_LOGS_DOMAIN` | Host name of the logs UI and of the OTLP logs endpoint. Must equal `VICTORIA_LOGS_HOST_LOCAL` in `management/.env`. | `logs.example.com` |
| `VICTORIA_METRICS_DOMAIN` | Host name of the metrics UI and of the OTLP metrics endpoint. Must equal `VICTORIA_METRICS_HOST_LOCAL` in `management/.env`. | `metrics.example.com` |
| `VICTORIA_LOGS_DATA_DIR` | Host directory of the VictoriaLogs data. | `/srv/victoria/logs` |
| `VICTORIA_GRAFANA_DOMAIN` | Host name of the Grafana UI. Must equal `VICTORIA_GRAFANA_HOST_LOCAL` in `management/.env`. | `grafana.example.com` |
| `VICTORIA_METRICS_DATA_DIR` | Host directory of the VictoriaMetrics data. | `/srv/victoria/metrics` |
| `ALERTMANAGER_DATA_DIR` | Host directory of the Alertmanager notification log and silences. | `/srv/victoria/alertmanager` |
| `GRAFANA_DATA_DIR` | Host directory of the Grafana database (users, preferences) and plugins. | `/srv/victoria/grafana` |
| `VICTORIA_LOGS_RETENTION` | Log retention (`-retentionPeriod`). Older data is deleted. | `30d` |
| `VICTORIA_METRICS_RETENTION` | Metric retention (`-retentionPeriod`). | `30d` |
| `PGID` | Group ID that owns the data directories and runs the databases, vmalert, Alertmanager and Grafana. | *None (empty)* |
| `PUID` | User ID that owns the data directories and runs the databases, vmalert, Alertmanager and Grafana. | *None (empty)* |
| `VECTOR_SYSLOG_PORT` | UDP port published on the host for syslog. Nothing else on the host may listen on it (rsyslog, for example). | `514` |
| `VECTOR_SYSLOG_SENDERS` | Known syslog senders, one JSON line keyed by source IP: `name` (FQDN, the `host_name` field) and `vendor` (`device_vendor`). Empty or invalid JSON means no table. No single quote (`'`): the value goes into a VRL raw string. | `{"192.0.2.1":{"name":"gw.example.com","vendor":"unifi"}}` |
| `GRAFANA_ADMIN_USER` | Authentik username that becomes the Grafana server admin. | `admin` |
| `GRAFANA_DEFAULT_ROLE` | Grafana role of the other Authentik users: `Viewer`, `Editor` or `Admin`. | `Viewer` |
| `FREE_MOBILE_USER` | Free Mobile account ID for the SMS API. Secret: set it only in the `.env` of the host. Empty means no SMS. | *None (empty)* |
| `FREE_MOBILE_PASS` | Free Mobile SMS API key. Secret: set it only in the `.env` of the host. Empty means no SMS. | *None (empty)* |

## First Deployment

1. Fill `.env` from `.env.example`, including `PUID` and `PGID`.
2. Generate the ingestion password hash with `htpasswd -nB collector` and replace `REPLACE_WITH_HTPASSWD_BCRYPT_HASH` in the `victoria-ingest-auth` middleware of `management/traefik_dynamic.toml`. Store the same password in the myansible vault. Until the hash is replaced, the middleware refuses every ingestion request.
3. Set `VICTORIA_LOGS_HOST_LOCAL`, `VICTORIA_METRICS_HOST_LOCAL` and `VICTORIA_GRAFANA_HOST_LOCAL` in `management/.env` and redeploy the management stack, so that the Authentik blueprint creates the three forward-auth applications.
4. In the Free Mobile customer area, turn on *Mon compte > Mes options > Notifications par SMS*. Put the account ID in `FREE_MOBILE_USER` and the API key shown there in `FREE_MOBILE_PASS`, in the `.env` of the host only. Without them the alerts still fire, but no SMS leaves.
5. Start the stack, check both databases, then open `https://<VICTORIA_GRAFANA_DOMAIN>/` and log in through Authentik:

```bash
docker compose up -d
curl -fsS "https://$VICTORIA_LOGS_DOMAIN/health"
curl -fsS "https://$VICTORIA_METRICS_DOMAIN/health"
```

The databases, vmalert, Alertmanager and Grafana run as `PUID:PGID`. Before they start, `victoria-init` (busybox, root, no network) gives every file of the four data directories that is not owned by `PUID:PGID` to that user. Docker creates a missing bind-mount source as root, and an earlier root run leaves root-owned files; both would stop the services with `permission denied`. Symlinks are changed themselves, never their targets.

## 1. VictoriaLogs (`victorialogs`)

### Role
Log database. It stores what `vector` sends and serves the web UI (vmui) and the LogsQL query API on port `9428`, published through Traefik only. A request on `/` is redirected to `/select/vmui/`.

The stream fields are `log_stream`, `host_name` and `container_name`. `log_stream` takes the role of the OpenObserve stream name (`docker`, `traefik`, `journald`, `authentik`, `proxmox`, `syslog`, `firewall`...). Filter on it first: a stream filter is much cheaper than a field filter.

`-insert.maxLineSizeBytes` is raised to `2MiB`. The collectors accept Docker log records up to 1 MiB (`otel_collector_docker_max_log_size` in myansible) and the default limit of 256 KiB would reject them.

### External Links
- **Official Project**: [https://docs.victoriametrics.com/victorialogs/](https://docs.victoriametrics.com/victorialogs/)
- **Source Code**: [https://github.com/VictoriaMetrics/VictoriaLogs](https://github.com/VictoriaMetrics/VictoriaLogs) (Apache-2.0)
- **Docker Image**: [victoriametrics/victoria-logs](https://hub.docker.com/r/victoriametrics/victoria-logs)
- **LogsQL Reference**: [https://docs.victoriametrics.com/victorialogs/logsql/](https://docs.victoriametrics.com/victorialogs/logsql/)

### Query Examples

Most blocked firewall destinations:

```text
{log_stream="firewall"} fw_action:drop
  | stats by (fw_descr, fw_dst, fw_dpt) count() hits
  | sort by (hits desc) | limit 20
```

Failed Authentik logins by user and IP:

```text
{log_stream="authentik"} ak_action:in(login_failed, invalid_identifier)
  | stats by (ak_user, ak_client_ip) count() hits
```

Failed Proxmox tasks:

```text
{log_stream="proxmox"} pve_task_failed:true | fields _time, pve_task_type, pve_task_status
```

VictoriaLogs does not store empty fields. A field missing from a record means the field does not apply; queries do not fail on it.

## 2. VictoriaMetrics (`victoriametrics`)

### Role
Metric database. It receives OTLP metrics over HTTP on `/opentelemetry/v1/metrics` and serves vmui and the PromQL/MetricsQL API on port `8428`, published through Traefik only. A request on `/` is redirected to `/vmui/`.

`-opentelemetry.usePrometheusNaming` turns OTLP names into Prometheus names with unit and type suffixes: `system.cpu.time` becomes `system_cpu_time_seconds_total`. Metric names therefore differ from the ones OpenObserve stored. Check the actual names in vmui after the switch before writing queries or alerts.

### External Links
- **Official Project**: [https://docs.victoriametrics.com/](https://docs.victoriametrics.com/)
- **Source Code**: [https://github.com/VictoriaMetrics/VictoriaMetrics](https://github.com/VictoriaMetrics/VictoriaMetrics) (Apache-2.0)
- **Docker Image**: [victoriametrics/victoria-metrics](https://hub.docker.com/r/victoriametrics/victoria-metrics)
- **OpenTelemetry ingestion**: [https://docs.victoriametrics.com/victoriametrics/integrations/opentelemetry/](https://docs.victoriametrics.com/victoriametrics/integrations/opentelemetry/)

### Proxmox Metric Server Setup
In the Proxmox UI, *Datacenter > Metric Server*, edit the OpenTelemetry entry:

- Server `metrics.home.lan`, port `443`, protocol HTTPS, path `/opentelemetry/v1/metrics`. Keep certificate verification on.
- Header `Authorization: Basic <base64 of collector:password>`, with the password of the `victoria-ingest-auth` middleware. The password is not stored in this repository.

The host pushes node, guest and storage metrics every 10 seconds: `proxmox_node_*` (CPU, memory, ZFS ARC, load, network, uptime), `proxmox_vm_*` (labels `name` and `vmid`) and `proxmox_storage_*` (label `storage`). Their exact names after Prometheus naming are to be read in vmui.

## 3. Vector (`vector`)

### Role
Single entry point of the logs. It receives:

- OTLP/HTTP logs on port `4318`, from the OpenTelemetry collectors deployed by myansible, through `https://<VICTORIA_LOGS_DOMAIN>/v1/logs`. The collector names the stream in the `stream-name` header (`otel_collector_streams` in myansible).
- UDP syslog on container port `5514`, published on the host as `VECTOR_SYSLOG_PORT`. This is the only port the stack publishes.

It then parses the records and writes them to `http://victorialogs:9428/insert/jsonline` on the Docker network.

```text
otlp -> normalize -> route_streams --docker, traefik--> redact_url_secrets -> route_authentik --authentik_*--> parse_authentik
                                   |--journald--> parse_http -> parse_proxmox
                                   |--other streams--> sink
syslog_udp -> parse_syslog
```

Every branch ends in the `victorialogs` sink.

The pipeline is the `vector_config` entry under `configs:` at the end of [`docker-compose.yml`](./docker-compose.yml), mounted on `/etc/vector/vector.yaml`. It is inline rather than a `./vector.yaml` bind mount because Portainer resolves relative paths on its own disk: Docker then creates an empty directory on the host and the deployment fails with `mkdirat etc/vector/vector.yaml: file exists`. Compose interpolates `$` in this block, so write `$$` for a literal `$`. Inline `configs` need Docker Compose 2.23 or later. Vector 0.61 does not expand `${VAR}` in its configuration, so Compose writes `VECTOR_SYSLOG_SENDERS` into the pipeline.

### External Links
- **Official Project**: [https://vector.dev/](https://vector.dev/)
- **Docker Image**: [timberio/vector](https://hub.docker.com/r/timberio/vector)
- **VRL Reference**: [https://vector.dev/docs/reference/vrl/](https://vector.dev/docs/reference/vrl/)

### Normalization (`normalize`)
Every OTLP record becomes a flat record with stable field names:

- Resource and record attributes are flattened with `_` (`container.name` becomes `container_name`, `app.RequestPath` becomes `app_requestpath`). A record attribute wins over a resource attribute of the same name.
- A map body becomes `body_*` fields (journald: `body_message`, `body_syslog_identifier`...). A string body goes to `body`. Any other body is stored as JSON in `body`.
- Field names are lowercased and limited to `[a-z0-9_]`.
- `log_stream` comes from the `stream-name` header. A name that does not match `^[a-z0-9_]{1,64}$` becomes `default`.
- The record time falls back to the collector receive time, then to the Vector time.
- `severity`, `severity_number`, `trace_id` and `span_id` are kept when set. The OTLP bookkeeping fields (scope, flags, dropped counts, observed timestamp) are dropped.

### Sink Notes
- The sink sends `Content-Type: application/x-ndjson`. Without it VictoriaLogs answers `200` and stores nothing.
- End-to-end acknowledgements are on: the OTLP source answers the collector only once VictoriaLogs has accepted the batch, so the collector retries on failure. UDP syslog has no such retry: messages sent while Vector is down are lost.
- Batches are sent every 1000 events or 5 seconds.
- Vector keeps its state on a tmpfs (`/var/lib/vector`); the pipeline has no disk buffer.

### Secret Masking (`redact_url_secrets`)
Records of the `docker` and `traefik` streams have the values of secret-looking parameters (`token`, `code`, `password`, `key`...) replaced by `[REDACTED]` in `body`, `app_msg`, `app_message` and `app_requestpath`. A parameter whose name only contains such a word (`monkey=`) is not masked.

### HAProxy and camera-streamer (`parse_http`, `journald` stream)
HAProxy `httplog` lines get the fields below. The request line is masked the same way in `http_path` and in `body_message`.

| Field | Content | Example |
| :--- | :--- | :--- |
| `http_client_ip` | Client IP, IPv4 or IPv6. | `192.0.2.10` |
| `http_frontend` | HAProxy frontend. | `https~` |
| `http_backend`, `http_server` | Backend and server. | `web`, `srv1` |
| `http_method` | HTTP method. | `GET` |
| `http_path` | Request path, secrets masked. | `/login?password=[REDACTED]` |
| `http_status` | Status code, as an integer (`-1` for an aborted request). | `404` |
| `http_bytes` | Bytes sent, as an integer. | `1234` |
| `http_ta_ms` | Total active time in ms, as an integer. | `6` |

camera-streamer connection lines get `http_client_ip` and `http_event` (`connected` or `disconnected`). A journald `MESSAGE` sent as an array of bytes is decoded; invalid UTF-8 is replaced by U+FFFD.

### Authentik Logs (`parse_authentik`, `authentik` stream)
Records of the `docker` stream whose `container_name` contains `authentik_` move to the `authentik` stream. Traefik access logs of Authentik routes stay in `traefik`. Secrets are also masked in `app_event`, `app_path` and `app_context_http_request`. Nothing changes on the Authentik side.

| Field | Content | Example |
| :--- | :--- | :--- |
| `ak_component` | Container name without the `authentik_` prefix. | `server`, `worker`, `postgresql` |
| `ak_kind` | `event` (Authentik event), `forward_auth` (embedded outpost), `health`, `http`, `task` or `log`. | `forward_auth` |
| `ak_level` | Level in a single vocabulary: `debug`, `trace`, `info`, `warning`, `error`, `critical`. | `warning` |
| `ak_client_ip` | Client IP, from `app_client_ip` (Python) or `app_remote` (outpost). | `192.0.2.10` |
| `ak_runtime_ms` | Request duration in ms, as a float. | `3.2` |
| `ak_action` | Event action; only on events. | `login_failed` |
| `ak_user` | User of the event (the name typed for `login_failed`); only on events. | `bob` |
| `ak_app_host` | Protected host of a forward-auth request. | `app.example.com` |

`ak_level` is normalized because the sources disagree. Authentik writes `warning` (Python) or `warn` (outpost); `warn` becomes `warning`, and `fatal` or `panic` becomes `critical`. The collector tags every PostgreSQL line `WARN`, so for `postgresql` the level is read from the `[pid] LEVEL:` prefix of the message: `ERROR` gives `error`, `FATAL` and `PANIC` give `critical`, `WARNING` gives `warning`, anything else `info`.

### Proxmox Logs (`parse_proxmox`, `proxmox` stream)
`journald` records whose syslog identifier is `pve*` (pvedaemon, pveproxy, pvescheduler, pveupdate, pvestatd, pve-ha-*, pve-firewall...), `pmxcfs`, `proxmox-*`, `vzdump`, `qmeventd` or `spiceproxy` move to the `proxmox` stream. Anything else stays in `journald` and gets no `pve_*` field.

| Field | Content | Example |
| :--- | :--- | :--- |
| `pve_component` | Syslog identifier of the daemon. | `pvedaemon` |
| `pve_level` | `critical`, `error`, `warning`, `info` or `debug`, from the journald priority. | `error` |
| `pve_kind` | `task`, `backup`, `auth`, `notification`, `ha` or `log`. | `task` |
| `pve_task_type` | Task type taken from the UPID. | `vzdump`, `acmerenew`, `qmstart` |
| `pve_task_event` | `start` or `end`. | `end` |
| `pve_task_status` | `OK`, or the error message of a finished task. | `OK` |
| `pve_task_failed` | `true` when a task ended with anything other than `OK`. | `false` |
| `pve_user` | PVE user. | `root@pam` |
| `pve_vmid` | VMID from the UPID or the backup line. | `105` |
| `pve_backup_event` | `job_start`, `vm_start`, `vm_ok`, `vm_failed`, `job_ok` or `job_failed`. | `vm_ok` |
| `pve_duration_s` | Backup duration of one guest in seconds (`vm_ok` only). | `42` |
| `pve_auth_result` | `success` or `failure`. | `failure` |
| `pve_client_ip` | Client IP of a failed login. | `192.0.2.10` |

### Syslog (`parse_syslog`, `syslog` and `firewall` streams)
UDP syslog from UniFi, switches and the NAS.

- RFC 3164 and RFC 5424 messages are parsed into `hostname`, `appname`, `severity`, `facility`, `message`, etc.
- Messages in another format are kept as is in `message`, with a `parse_error` field. Today these are mostly the kernel lines of the UniFi access points, which carry no syslog header.
- `_time` is the time Vector received the message. The time sent by the device is kept in `syslog_timestamp`: device clocks drift and RFC 3164 has no year.
- `source_ip` is the address of the sending device.
- `host_name` is the entry of the sender in `VECTOR_SYSLOG_SENDERS`, else its syslog `hostname` in lower case, else its IP. `device_vendor` comes from the same entry.
- Firewall lines go to the `firewall` stream, everything else to `syslog`.

#### CEF Fields
UniFi sends its events (firewall, IDS/IPS, Wi-Fi, VPN) as `CEF:0|Ubiquiti|UniFi Network|<version>|<id>|<name>|<severity>|key=value ...`. `parse_syslog` reads `CEF` as the `appname`; the pipeline puts the prefix back and parses the message with VRL `parse_cef`. `message` is not changed.

| Field | Content | Example |
| :--- | :--- | :--- |
| `cef_version` | CEF format version. | `0` |
| `cef_vendor` | Device vendor. | `Ubiquiti` |
| `cef_product` | Device product. | `UniFi Network` |
| `cef_product_version` | Product version. | `11.0.99` |
| `cef_signature_id` | Event type ID (string). | `203` |
| `cef_name` | Event name. | `Blocked by Firewall` |
| `cef_severity` | Severity 0-10, as an integer. | `4` |
| `cef_severity_label` | Only set when the severity is a word (`Low`, `High`...); `cef_severity` is then absent. | `High` |
| `cef_parse_error` | Set when the message contains `CEF:` but cannot be parsed. | |

Each `key=value` extension also becomes a field of its own, as a string: `UNIFIcategory`, `UNIFIrisk`, `src`, `dst`, `proto`, `spt`, `dpt`, `act`, `msg`, and so on depending on the event type. If an extension has the same name as a field already set by the pipeline (`appname`, `hostname`, `host_name`...), the pipeline's value is kept.

#### Firewall Logs
The UniFi gateway also sends the iptables log lines of its firewall rules, without CEF:

```text
[LAN_WAN-D-40001] DESCR="block-dns" IN=br0 OUT=eth6 MAC=... SRC=2001:db8::1 DST=2001:4860:4860::8888 LEN=80 TC=0 HOPLIMIT=63 FLOWLBL=0 PROTO=UDP SPT=41153 DPT=53 LEN=40 MARK=0x21940000
```

The pipeline splits them into fields with a `fw_` prefix, so they never mix with the `src`, `dst` and `proto` of the CEF events. `message` is kept as received.

| Field | Content | Example |
| :--- | :--- | :--- |
| `fw_rule` | Rule prefix of the log line. | `LAN_WAN-D-40001` |
| `fw_ruleset` | Rule set (traffic direction). | `LAN_WAN` |
| `fw_rule_id` | Rule number, as an integer. | `40001` |
| `fw_action` | `accept`, `drop` or `reject`, from the `A`, `D` or `R` letter of the prefix. | `drop` |
| `fw_action_code` | The letter itself. | `D` |
| `fw_descr` | Rule description set in UniFi. | `block-dns` |
| `fw_in`, `fw_out` | Input and output interfaces; absent when the packet is for the gateway itself. | `br0`, `eth6` |
| `fw_src`, `fw_dst` | Source and destination addresses, IPv4 or IPv6. | `2001:4860:4860::8888` |
| `fw_proto` | `TCP`, `UDP`, `ICMP`, `ICMPv6`... | `UDP` |
| `fw_spt`, `fw_dpt` | Source and destination ports, as integers. | `53` |
| `fw_len` | IP packet length, as an integer. | `80` |
| `fw_l4_len` | Layer 4 length (the second `LEN=` of the line), as an integer. | `40` |
| `fw_ttl`, `fw_hoplimit` | IPv4 TTL or IPv6 hop limit, as integers. | `63` |

Every other `KEY=value` pair becomes `fw_<key>` as a string (`fw_mac`, `fw_mark`, `fw_tos`...). A flag without a value, such as `DF` or `SYN`, becomes `true` (`fw_df`, `fw_syn`). The original packet that an ICMP error quotes between brackets is left out of the fields.

#### UniFi Setup
In UniFi Network, *Settings > CyberSecure > Traffic Logging* (or *System > Remote Logging* depending on the version): enable *SIEM Server* or *Syslog*, then set the host address and port `514`.

## Alerting

Two vmalert instances evaluate the rules, both defined in the `configs:` section of the compose file. `vmalert-logs` runs LogsQL rules against VictoriaLogs and `vmalert-metrics` runs MetricsQL rules against VictoriaMetrics. Both send their alerts to `alertmanager`. They keep the alert state (`ALERTS`, `ALERTS_FOR_STATE`) in VictoriaMetrics through `-remoteWrite.url` and read it back at startup through `-remoteRead.url`, so a restart does not reset a pending or firing alert.

The rules carry over the OpenObserve alerts:

| Alert | Source | Fires when | Repeat |
| :--- | :--- | :--- | :--- |
| `authentik_login_failed_burst` | logs | 5 or more `login_failed` or `invalid_identifier` events in 15 minutes | 60m |
| `authentik_sensitive_event` | logs | a suspicious request, an impersonation, a system or policy exception, or a configuration error in 5 minutes | 60m |
| `authentik_errors` | logs | 3 or more `error` or `critical` records in 15 minutes | 60m |
| `authentik_logs_silent` | logs | no record from `server` or `worker` for 10 minutes, for a component seen in the last 24 hours | 60m |
| `proxmox_backup_failed` | logs | a failed vzdump job or guest in 15 minutes | 60m |
| `proxmox_task_failed` | logs | a failed task in 15 minutes, `acmerenew` excluded | 1440m |
| `proxmox_auth_failed_burst` | logs | 5 or more failed Proxmox logins in 15 minutes | 60m |
| `proxmox_backup_missing` | logs | no successful vzdump job for 26 hours, once the stream holds records older than 24 hours (checked every hour) | 720m |
| `proxmox_metrics_silent` | metrics | no `proxmox_node_uptime` sample from a node for 10 minutes | 60m |
| `proxmox_storage_usage_high` | metrics | a storage at 85% or more | 720m |
| `proxmox_node_memory_high` | metrics | node memory at 90% or more, ZFS ARC excluded | 120m |
| `proxmox_node_cpu_high` | metrics | node CPU above 90% on a 15 minute average | 120m |
| `proxmox_guest_restarted` | metrics | a running guest with an uptime under 10 minutes | 30m |

The repeat column replaces the OpenObserve silence period. Each alert has its own Alertmanager route, and its `repeat_interval` equals the `keep_firing_for` of the rule. While a rule keeps matching, the SMS comes back once per interval. `keep_firing_for` keeps the alert firing for that long after the last match, so an alert that flaps does not send one SMS per flap. Alertmanager groups by `alertname` (one SMS per rule), waits 30 seconds before the first SMS of a group, and sends nothing when an alert resolves. Its notification log and silences live in `ALERTMANAGER_DATA_DIR`, so a restart does not send the SMS of a firing alert again.

`acmerenew` is left out of `proxmox_task_failed` because the daily ACME renewal of the Proxmox host fails until its certificate setup is fixed, and it would send an SMS every day. Remove the `-pve_task_type:=acmerenew` filter once the renewal works.

### SMS Bridge

Alertmanager posts its webhook to the `alertmanager_webhook` source of Vector (`http://vector:8080/alertmanager`, at most 10 alerts per call). The `sms_message` transform writes one line per firing alert, from its `summary` annotation, adds `(+N autres alertes)` when Alertmanager truncated the list, and cuts the text at 900 characters. The `free_mobile` sink posts `{user, pass, msg}` as JSON to `https://smsapi.free-mobile.fr/sendmsg`, one SMS per request, with TLS verification on. It retries 3 times on a `5xx` and gives up on the other errors:

| Free Mobile code | Meaning |
| :--- | :--- |
| `200` | SMS sent. |
| `400` | Missing parameter. |
| `402` | Too many SMS in too little time. |
| `403` | SMS option off in the customer area, or wrong credentials. |
| `500` | Server error, retried. |

With `FREE_MOBILE_USER` or `FREE_MOBILE_PASS` empty, Vector logs `SMS not sent` as an error and drops the message. The alerts still show in vmalert and Alertmanager.

### Post-Deployment Check of the Metric Names

The metric rules and the Proxmox dashboard use the names that the Proxmox VE OpenTelemetry metric server is expected to send (`proxmox_node_uptime`, `proxmox_storage_used`, `proxmox_node_memory_arcsize`, `proxmox_vm_uptime`...). No test can confirm them before Proxmox sends real data. After the first deployment, open the VictoriaMetrics UI, run `{__name__=~"proxmox_.*"}` and compare the names and labels (`host_name`, `storage`, `name`, `vmid`) with the `vmalert_metrics_rules` config and the dashboard queries. A wrong name gives a rule that never fires and an empty panel, with no error.

## Grafana

`victoria-grafana` is separate from the `grafana` stack of this repository. It trusts the `X-authentik-username` header that the Authentik forward auth sets (auth proxy) and creates the user at the first login. No Grafana password works: the login form, Basic auth, anonymous access and the auth proxy login token are off. The Authentik user named in `GRAFANA_ADMIN_USER` is the Grafana server admin. The other users get `GRAFANA_DEFAULT_ROLE` (`Viewer` by default).

`GF_AUTH_DISABLE_LOGIN` stays unset. Grafana 13.2 answers HTTP 500 to every proxied request when it is `true`, and `tests/test_stack.sh` fails if it is set.

Grafana installs the `victoriametrics-logs-datasource` plugin at the pinned version before it starts (`GF_PLUGINS_PREINSTALL_SYNC`), which needs Internet access from the host at the first start. The plugin then stays in `GRAFANA_DATA_DIR`.

The datasources (`victorialogs`, `victoriametrics`) and the two dashboards are provisioned from the compose file: *Authentik* (uid `victoria-authentik`) and *Proxmox VE* (uid `victoria-proxmox`). The dashboards are read-only in the UI: an edit cannot be saved, and a change goes into the `grafana_dashboard_*` configs. The OpenObserve Authentik dashboard enriched source IPs with their reverse DNS name (ptr). VictoriaLogs has no such lookup, so the panels show the IPs only.

## 4. Access Control

The three UI routers (`victorialogs`, `victoriametrics`, `victoria_grafana`) go through the `authentik@docker` forward-auth middleware of the management stack, placed first so that the UIs fail closed while `authentik_server` is down. A browser must log in to Authentik as a member of `victorialogs-users`, `victoriametrics-users` or `victoria-grafana-users`. The providers, applications and groups are created by the `20-forward-auth-apps.yaml` blueprint of the management stack, which reads the host names from `VICTORIA_LOGS_HOST_LOCAL`, `VICTORIA_METRICS_HOST_LOCAL` and `VICTORIA_GRAFANA_HOST_LOCAL` in `management/.env`. VictoriaLogs and VictoriaMetrics have no login of their own: Authentik is the only access control on the UIs and the query APIs. Grafana relies on the user name that Authentik passes in `X-authentik-username`.

Collectors cannot follow a browser login, so two routers skip Authentik for ingestion only:

- `vector_ingest`: `POST` on exactly `/v1/logs` of the logs host, to `vector`.
- `victoriametrics_ingest`: `POST` on exactly `/opentelemetry/v1/metrics` of the metrics host, to `victoriametrics`.

Both carry only the `victoria-ingest-auth@file` middleware: HTTP Basic auth defined in `management/traefik_dynamic.toml`, which removes the `Authorization` header before the backend.

Two more routers, `victorialogs_health` and `victoriametrics_health`, skip every middleware for `GET` and `HEAD` on exactly `/health`, for the Uptime Kuma HTTP monitors. That endpoint only returns `OK`.

The `*_http` routers only redirect HTTP to HTTPS.

Limits:

- Ports `9428`, `8428` and `4318` have no authentication of their own. Every container on the `traefik_gateway` network can query and write the databases and send logs to Vector. Only the UDP syslog port is published on the host.
- Grafana port `3000` is not published, but a container on `traefik_gateway` that reaches it directly can send its own `X-authentik-username` header and log in as any user, the admin included. Through Traefik, the forward auth replaces that header.
- The SMS webhook of Vector (port `8080`) has no authentication. Vector sits on `traefik_gateway` too, so any container there can make it send an SMS.
- vmalert-logs, vmalert-metrics and Alertmanager have no route and no published port, and sit only on the internal `victoria` network. Their UIs are reachable only from the containers of this stack.
- While Authentik is down, the UIs are unreachable. Ingestion keeps working.
- UDP syslog is unauthenticated, like any syslog: any host that reaches the port can send messages. `host_name` and `device_vendor` only come from the sender table for listed IPs.

## 5. Migration from OpenObserve

- The OpenObserve history is not migrated. Keep the OpenObserve data directory until the retention period has passed if the old logs are still needed.
- The OpenObserve alerts and dashboards are rewritten in this stack (see [Alerting](#alerting) and [Grafana](#grafana)). The `openobserve/` directory and its exports are gone from the repository.
- The collectors deployed by myansible must point to the new endpoints with the new Basic auth credentials: `https://<VICTORIA_LOGS_DOMAIN>/v1/logs` and `https://<VICTORIA_METRICS_DOMAIN>/opentelemetry/v1/metrics`.
- The stack has no backup. Back up the four data directories (`VICTORIA_LOGS_DATA_DIR`, `VICTORIA_METRICS_DATA_DIR`, `ALERTMANAGER_DATA_DIR`, `GRAFANA_DATA_DIR`) with the host tooling if they must survive a disk loss; VictoriaLogs and VictoriaMetrics support file-level copies of a stopped instance and VictoriaMetrics snapshots (`/snapshot/create`).

Switch-over order:

1. Stop OpenObserve before pulling this change, while its compose file is still there (`docker compose down` in `openobserve/`, data kept): both stacks serve `logs.<domain>`. From then until step 5, the collectors get a `401` from the new endpoint and drop what they send, and no alert runs.
2. Replace the hash of the `victoria-ingest-auth` middleware in `management/traefik_dynamic.toml` (step 2 of First Deployment).
3. Set the three `*_HOST_LOCAL` variables (logs, metrics, Grafana), redeploy the management stack (Authentik blueprint), set `FREE_MOBILE_USER` and `FREE_MOBILE_PASS` in `.env`, then start this stack.
4. Check `/health` on both hosts, then log in to the two UIs and to Grafana through Authentik.
5. Put the ingestion password in the myansible vault (`vault_victoria_ingest_auth`), redeploy the collectors (`make logs` in myansible) and check that every host shows up in VictoriaLogs.
6. Run the metric name check of [Alerting](#post-deployment-check-of-the-metric-names) once Proxmox has sent metrics.
7. Delete the OpenObserve data directory once its logs are no longer needed.

## 6. Tests

[`tests/test_stack.sh`](./tests/test_stack.sh) renders the compose file with `.env.example` and checks the exposure without starting anything: forward auth first on the three UI routers, the ingestion and health routers limited to their method, path, middleware and service, forward auth on every other router of the three hosts, no published port except the UDP syslog port, the Grafana auth proxy settings (no login form, Basic auth, anonymous access or `GF_AUTH_DISABLE_LOGIN`), vmalert and Alertmanager on the internal `victoria` network only, and the `victoria-ingest-auth` middleware in `management/traefik_dynamic.toml.example`. It needs Docker Compose 2.23 or later, `jq` and Python 3.11 or later.

[`tests/test_vector.sh`](./tests/test_vector.sh) renders the compose file with `.env.example`, runs `vector validate` on the pipeline, then the Vector unit tests of [`otlp_test.yaml`](./tests/otlp_test.yaml) (normalization, routing, secret masking, HAProxy), [`authentik_test.yaml`](./tests/authentik_test.yaml), [`proxmox_test.yaml`](./tests/proxmox_test.yaml), [`syslog_test.yaml`](./tests/syslog_test.yaml) (syslog, CEF, firewall) and [`sms_test.yaml`](./tests/sms_test.yaml) (SMS text, truncation, missing credentials). It needs Docker, Docker Compose 2.23 or later and `jq`, and makes no network call.

[`tests/test_ingest.sh`](./tests/test_ingest.sh) starts VictoriaLogs and Vector on a throwaway internal network, sends one OTLP/HTTP protobuf record to Vector with a `stream-name` header, then queries VictoriaLogs. It checks what the unit tests cannot: the OTLP source, the sink query string (`_stream_fields`, `_msg_field`, `_time_field`), the stored fields and stream, and the masking of a URL secret. It needs Docker, Docker Compose 2.23 or later, `jq` and Python 3, uses the local images (`CLIENT_IMAGE` overrides the busybox client, `busybox:1.37` by default), and takes about 20 seconds. The Vector OTLP/HTTP source only accepts protobuf: an OTLP JSON request gets an HTTP 500.

[`tests/test_alerting.sh`](./tests/test_alerting.sh) first checks the rules and the routing without starting anything: `vmalert -dryRun` on both rule sets, `amtool check-config`, one Alertmanager route per alert with a `repeat_interval` equal to the `keep_firing_for` of the rule, no route without a rule, and a receiver that targets the Vector webhook. It then starts VictoriaLogs, VictoriaMetrics, vmalert-logs, Alertmanager and Vector on a throwaway internal network, with 5 second rule intervals and the `free_mobile` sink pointed at VictoriaLogs. It sends a failed vzdump, a failed `acmerenew` task and a failed `qmstart` task, and expects one SMS body for `proxmox_backup_failed` and one for `proxmox_task_failed` that names `qmstart` only. It does not cover the Proxmox parsing (see `proxmox_test.yaml`), the metric rules on real data or the Free Mobile API. It needs Docker, Docker Compose 2.23 or later, `jq` and Python 3 with PyYAML, makes no Internet call, and waits at most `ALERTING_TIMEOUT` seconds (120 by default).

[`tests/test_dashboards.sh`](./tests/test_dashboards.sh) starts VictoriaLogs, VictoriaMetrics and Grafana with sample data. It checks that the Grafana API answers `401` without the `X-authentik-username` header, refuses Basic auth and the `admin/admin` login form, and gives a new user the Viewer role and both dashboards. Every query of the two dashboards then goes through the Grafana datasource API, template variables replaced by a test value: each VictoriaLogs query must return data and each VictoriaMetrics query must answer `200`. It also checks the version of the loaded plugin. The plugin is read from `GRAFANA_PLUGIN_DIR` (a `plugins` directory that holds `victoriametrics-logs-datasource`, for example the one of a Grafana that ran this stack) and the test makes no Internet call. It does not cover the browser rendering, the Authentik outpost or the real Proxmox metric names.

```bash
./tests/test_stack.sh
./tests/test_vector.sh
./tests/test_ingest.sh
./tests/test_alerting.sh
GRAFANA_PLUGIN_DIR=/path/to/plugins ./tests/test_dashboards.sh
```
