# Victoria Stack

This stack replaces OpenObserve. It deploys the following services:

- `victorialogs`: log database, UI on `logs.<domain>`.
- `victoriametrics`: metric database, UI on `metrics.<domain>`.
- `vector`: the only writer of `victorialogs`. It receives OTLP logs from the collectors and UDP syslog from network devices, parses them and sends them on.
- `vmalert-logs` and `vmalert-metrics`: alert rules on the logs (LogsQL) and on the metrics (MetricsQL).
- `alertmanager`: groups the alerts and sends them as SMS through Vector and the Free Mobile API. It also pushes a heartbeat to an Uptime Kuma push monitor (see [Watchdog](#watchdog)).
- `grafana` (container `victoria-grafana`): dashboards for hosts, logs, Docker services, DNS, firewall, Authentik, Proxmox, UniFi, Synology, disks, alerts and the stack itself, UI on `grafana.<domain>`.
- `unpoller`: polls the UniFi gateway and exposes its metrics to VictoriaMetrics, which scrapes them.
- `snmp-exporter`: polls the Synology NAS over SNMPv3 when VictoriaMetrics scrapes it.
- `freebox-exporter`: polls the Freebox API (connection, fiber, system) and exposes the metrics to VictoriaMetrics, which scrapes them.
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
| `UNPOLLER_VERSION` | unpoller image tag (`ghcr.io/unpoller/unpoller`). | `v5.9.6` |
| `SNMP_EXPORTER_VERSION` | snmp_exporter image tag (`prom/snmp-exporter`, the compose file adds the `-distroless` suffix). | `v0.31.0` |
| `FREEBOX_EXPORTER_VERSION` | freebox-exporter-rs image tag (`ghcr.io/shackerd/freebox-exporter-rs`). Keep a release tag: the `v0.0.27` and later tags are betas. | `v0.0.26` |
| `GRAFANA_LOGS_PLUGIN_VERSION` | Version of the `victoriametrics-logs-datasource` Grafana plugin. | `0.34.0` |
| `GRAFANA_MCP_VERSION` | mcp-grafana image tag (`grafana/mcp-grafana`, no `v` prefix). | `2.4.0` |
| `VICTORIA_LOGS_DOMAIN` | Host name of the logs UI and of the OTLP logs endpoint. Must equal `VICTORIA_LOGS_HOST_LOCAL` in `management/.env`. | `logs.example.com` |
| `VICTORIA_METRICS_DOMAIN` | Host name of the metrics UI and of the OTLP metrics endpoint. Must equal `VICTORIA_METRICS_HOST_LOCAL` in `management/.env`. | `metrics.example.com` |
| `VICTORIA_LOGS_DATA_DIR` | Host directory of the VictoriaLogs data. | `/srv/victoria/logs` |
| `VICTORIA_GRAFANA_DOMAIN` | Host name of the Grafana UI. Must equal `VICTORIA_GRAFANA_HOST_LOCAL` in `management/.env`. | `grafana.example.com` |
| `VICTORIA_METRICS_DATA_DIR` | Host directory of the VictoriaMetrics data. | `/srv/victoria/metrics` |
| `ALERTMANAGER_DATA_DIR` | Host directory of the Alertmanager notification log and silences. | `/srv/victoria/alertmanager` |
| `GRAFANA_DATA_DIR` | Host directory of the Grafana database (users, preferences) and plugins. | `/srv/victoria/grafana` |
| `VICTORIA_LOGS_RETENTION` | Log retention (`-retentionPeriod`). Older data is deleted. | `30d` |
| `VICTORIA_METRICS_RETENTION` | Metric retention (`-retentionPeriod`). One year keeps the capacity trends (disk, cardinality) for about 1 MB a day of stored points at the current volume. | `1y` |
| `PGID` | Group ID that owns the data directories and runs the databases, vmalert, Alertmanager and Grafana. | *None (empty)* |
| `PUID` | User ID that owns the data directories and runs the databases, vmalert, Alertmanager and Grafana. | *None (empty)* |
| `VECTOR_SYSLOG_PORT` | UDP port published on the host for syslog. Nothing else on the host may listen on it (rsyslog, for example). | `514` |
| `VECTOR_SYSLOG_SENDERS` | Known syslog senders, one JSON line keyed by source IP: `name` (FQDN, the `host_name` field) and `vendor` (`device_vendor`). Empty or invalid JSON means no table. No single quote (`'`): the value goes into a VRL raw string. | `{"192.0.2.1":{"name":"gw.example.com","vendor":"unifi"}}` |
| `VECTOR_SYSLOG_DOMAIN` | Domain added to the short hostname (no dot, not an IP) of a syslog sender missing from `VECTOR_SYSLOG_SENDERS`, so that one device keeps one `host_name`. Empty: the hostname stays as sent. | `example.com` |
| `GRAFANA_ADMIN_USER` | Authentik username that becomes the Grafana server admin. | `admin` |
| `GRAFANA_DEFAULT_ROLE` | Grafana role of the other Authentik users: `Viewer`, `Editor` or `Admin`. | `Viewer` |
| `GRAFANA_MCP_SA_TOKEN` | Token of the Grafana service account that the MCP server uses (see [MCP Server](#mcp-server-grafana-mcp)). Secret: set it only in the environment of the stack. Empty means the MCP server waits and serves nothing. | *None (empty)* |
| `GRAFANA_MCP_SERVER_TOKEN` | Bearer token that MCP clients must send, 32 characters or more (`openssl rand -hex 32`). Secret: set it only in the environment of the stack. Empty or shorter means the MCP server waits and serves nothing. | *None (empty)* |
| `FREE_MOBILE_USER` | Free Mobile account ID for the SMS API. Secret: set it only in the environment of the stack. Empty means no SMS. | *None (empty)* |
| `FREE_MOBILE_PASS` | Free Mobile SMS API key. Secret: set it only in the environment of the stack. Empty means no SMS. | *None (empty)* |
| `VECTOR_WEBHOOK_PASSWORD` | Basic auth password of the SMS webhook of Vector, sent by Alertmanager (user `alertmanager`). Required: Compose refuses to render the stack while it is unset. Compose writes it into the Vector and Alertmanager configs, so use hex only: `openssl rand -hex 32`. Secret: set it only in the environment of the stack. | *None (empty)* |
| `ALERTMANAGER_WATCHDOG_URL` | Push URL of the Uptime Kuma monitor that receives the watchdog, with `?status=up&msg=OK`. Required: Compose refuses to render the stack while it is unset. The token in the URL is a secret: set the real URL only in the environment of the stack. | `https://uptime.example.com/api/push/CHANGE_ME?status=up&msg=OK` |
| `UNIFI_URL` | URL of the UniFi gateway that unpoller polls. Its certificate must chain to a CA of the host bundle. | `https://unifi.home.lan` |
| `UNPOLLER_USER` | Local UniFi account of unpoller, View Only on Network. Empty means unpoller gets `403` and no UniFi metric arrives. | *None (empty)* |
| `UNPOLLER_PASS` | Password of that account. Secret: set it only in the environment of the stack. | *None (empty)* |
| `SYNOLOGY_SNMP_TARGET` | Host name or IP of the Synology NAS. Required: Compose refuses to render the stack while it is unset. | `nas.example.com` |
| `SYNOLOGY_SNMP_USER` | SNMPv3 user set in DSM. | `snmp-victoria` |
| `SYNOLOGY_SNMP_AUTH_PASS` | SNMPv3 authentication password (SHA). Secret: set it only in the environment of the stack. Empty means every scrape of the NAS fails. | *None (empty)* |
| `SYNOLOGY_SNMP_PRIV_PASS` | SNMPv3 privacy password (AES). Secret: set it only in the environment of the stack. | *None (empty)* |
| `FREEBOX_APP_TOKEN` | App token of freebox-exporter, from the one-time registration (see [Freebox Metrics](#freebox-metrics-freebox-exporter)). Secret: set it only in the environment of the stack. Empty means the exporter waits and no Freebox metric arrives. | *None (empty)* |

## First Deployment

1. Fill the environment of the stack from `.env.example`, including `PUID` and `PGID`. Portainer deploys the stack, so the values go into the environment of the Portainer stack (or into `.env` for a manual `docker compose` run).
2. Generate the ingestion password hash with `htpasswd -nB collector` and replace `REPLACE_WITH_HTPASSWD_BCRYPT_HASH` in the `victoria-ingest-auth` middleware of `management/traefik_dynamic.toml`. Store the same password in the myansible vault. Until the hash is replaced, the middleware refuses every ingestion request.
3. Set `VICTORIA_LOGS_HOST_LOCAL`, `VICTORIA_METRICS_HOST_LOCAL` and `VICTORIA_GRAFANA_HOST_LOCAL` in `management/.env` and redeploy the management stack, so that the Authentik blueprint creates the three forward-auth applications.
4. In the Free Mobile customer area, turn on *Mon compte > Mes options > Notifications par SMS*. Put the account ID in `FREE_MOBILE_USER` and the API key shown there in `FREE_MOBILE_PASS`, in the environment of the stack only. Without them the alerts still fire, but no SMS leaves. Set `VECTOR_WEBHOOK_PASSWORD` to the output of `openssl rand -hex 32`: Compose refuses to render the stack without it.
5. In Uptime Kuma, add a monitor of type *Push* with a heartbeat interval of 300 seconds and attach a notification that does not go through this stack (the Free Mobile notification of Kuma, for example). Put its push URL, followed by `?status=up&msg=OK`, in `ALERTMANAGER_WATCHDOG_URL`. Until Alertmanager pushes to it, the monitor stays down.
6. Start the stack, check both databases, then open `https://<VICTORIA_GRAFANA_DOMAIN>/` and log in through Authentik:

```bash
docker compose up -d
curl -fsS "https://$VICTORIA_LOGS_DOMAIN/health"
curl -fsS "https://$VICTORIA_METRICS_DOMAIN/health"
```

The databases, vmalert, Alertmanager and Grafana run as `PUID:PGID`. Before they start, `victoria-init` (busybox, root, no network) gives every file of the four data directories that is not owned by `PUID:PGID` to that user. Docker creates a missing bind-mount source as root, and an earlier root run leaves root-owned files; both would stop the services with `permission denied`. Symlinks are changed themselves, never their targets.

### Configuration Sources

The 25 configuration files of the stack (scrape config, SNMP auth, freebox-exporter config, vmalert rules, Alertmanager config, Vector pipeline, Grafana provisioning and the sixteen dashboards) live under [`config/`](./config/). Edit them there, then regenerate the compose file:

```bash
python3 build.py
```

[`build.py`](./build.py) writes each source into the `content:` block of its entry under `configs:` in [`docker-compose.yml`](./docker-compose.yml), and leaves every other line as written. The compose file stays committed and self-contained because Portainer deploys from its own clone of the repository: outside Swarm, a `file:` config is a bind mount from the host, where that clone does not exist.

A source holds the text that the container reads. `build.py` doubles each `$` for Compose, except the `${VAR}` that Compose must interpolate, listed per config in `INTERPOLATED` (`SYNOLOGY_SNMP_TARGET`, `ALERTMANAGER_WATCHDOG_URL`, `VECTOR_SYSLOG_DOMAIN`, `VECTOR_SYSLOG_SENDERS`, `VECTOR_WEBHOOK_PASSWORD`). The `${...}` that the container expands (the SNMP credentials, the Grafana data link variables) are listed in `LITERAL`. Any other `${NAME}` stops the build with exit code 2, so a new variable must be added to one of the two lists first.

The pre-commit hook of the repository runs `build.py --check` on the staged files and refuses a commit whose `docker-compose.yml` does not match its staged sources. It needs `git config core.hooksPath .githooks` once per clone (see the root README).

### Memory Limits and Health Checks

| Service | `mem_limit` | Health check |
| :--- | :--- | :--- |
| `victorialogs` | `1g` | None: the image has no shell and no `wget`. |
| `victoriametrics` | `1g` | `wget` on `:8428/health` |
| `vmalert-logs`, `vmalert-metrics` | `128m` | `wget` on `:8880/health` |
| `alertmanager` | `128m` | `wget` on `:9093/-/healthy` |
| `vector` | None | None: distroless image, no shell and no `wget`. |

The limits sit well above the memory seen in production. They stop one service from taking the memory of the whole host; VictoriaLogs and VictoriaMetrics also size their caches from the cgroup limit instead of the host memory. A service that reaches its limit is killed by the kernel and restarted, and the `container_oom` alert fires: raise the limit then.

The vmalert instances start once VictoriaMetrics and Alertmanager are healthy (`depends_on` with `service_healthy`), so their first evaluations neither restore an empty state nor lose notifications. VictoriaLogs has no health check, so vmalert-logs only waits for it to be started. The health checks probe every 5 seconds during the first minute (`start_interval`, Docker Engine 25 or later), then every minute.

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
Metric database. It receives OTLP metrics over HTTP on `/opentelemetry/v1/metrics`, in protobuf only (it answers `400` to OTLP JSON), and serves vmui and the PromQL/MetricsQL API on port `8428`, published through Traefik only. A request on `/` is redirected to `/vmui/`.

`-opentelemetry.usePrometheusNaming` turns OTLP names into Prometheus names with unit and type suffixes: `system.cpu.time` becomes `system_cpu_time_seconds_total`. Metric names therefore differ from the ones OpenObserve stored. Check the actual names in vmui after the switch before writing queries or alerts.

### External Links
- **Official Project**: [https://docs.victoriametrics.com/](https://docs.victoriametrics.com/)
- **Source Code**: [https://github.com/VictoriaMetrics/VictoriaMetrics](https://github.com/VictoriaMetrics/VictoriaMetrics) (Apache-2.0)
- **Docker Image**: [victoriametrics/victoria-metrics](https://hub.docker.com/r/victoriametrics/victoria-metrics)
- **OpenTelemetry ingestion**: [https://docs.victoriametrics.com/victoriametrics/integrations/opentelemetry/](https://docs.victoriametrics.com/victoriametrics/integrations/opentelemetry/)

### Proxmox Metric Server Setup
The OpenTelemetry metric server of Proxmox VE sends OTLP in JSON, which VictoriaMetrics refuses. It therefore sends to the OpenTelemetry collector of the Proxmox host, which forwards the points to VictoriaMetrics in protobuf with the ingestion credentials. myansible deploys this local receiver when `otel_collector_otlp_receiver` is `true` for the host.

In the Proxmox UI, *Datacenter > Metric Server*, edit the OpenTelemetry entry:

- Server `127.0.0.1`, port `4318`, protocol HTTP, path `/v1/metrics`.
- No `Authorization` header: the receiver listens on loopback only and has no authentication. The collector adds the credentials when it forwards to `metrics.<domain>`.

Do not point the entry at `metrics.<domain>` directly: VictoriaMetrics answers `400` to every push.

The host pushes node, guest and storage metrics every 10 seconds: `proxmox_node_*` (CPU, memory, ZFS ARC, load, network, uptime), `proxmox_vm_*` (labels `name` and `vmid`) and `proxmox_storage_*` (label `storage`). Their names carry unit suffixes; [`tests/check_metric_names.sh`](./tests/check_metric_names.sh) checks the names used by the rules and the dashboard (see [Post-Deployment Check of the Metric Names](#post-deployment-check-of-the-metric-names)).

### UniFi Metrics (`unpoller`)
VictoriaMetrics pulls the UniFi metrics instead of receiving them. The `victoriametrics_scrape` config, loaded with `-promscrape.config`, has a job `unpoller` that scrapes `unpoller:9130` every 60 seconds (the other jobs are the NAS, see [Synology Metrics](#synology-metrics-snmp-exporter), the Freebox, see [Freebox Metrics](#freebox-metrics-freebox-exporter), and the stack itself, see [Watchdog](#watchdog)). unpoller refreshes its own data once a minute, so a shorter interval adds no point.

unpoller runs as `65534:65534` with no published port and no Traefik route. It is on the internal `victoria` network, where VictoriaMetrics reaches it, and on the `unpoller` network, its only route to the gateway. It verifies the gateway certificate against the host CA bundle (`/etc/ssl/certs/ca-certificates.crt`, mounted read-only), so the internal CA that signs `unifi.home.lan` must be in that bundle. The InfluxDB output and the DPI collection are off.

Setup:

1. In UniFi OS, *Admins & Users*, create a local admin restricted to local access, with the *View Only* role on Network and no access to the other applications.
2. Put its username and password in `UNPOLLER_USER` and `UNPOLLER_PASS`, in the environment of the stack only.
3. Run `docker compose up -d`. Empty or wrong credentials stop unpoller only: it logs a `403` and the rest of the stack runs.

After deployment, check the log and the scrape:

```bash
docker logs --tail 20 unpoller
ssh chataigne.home.lan "docker exec vmalert-logs wget -qO- 'http://victoriametrics:8428/api/v1/query?query=up%7Bjob%3D%22unpoller%22%7D'"
ssh chataigne.home.lan "docker exec vmalert-logs wget -qO- 'http://victoriametrics:8428/api/v1/query?query=count(%7B__name__%3D~%22unpoller_.*%22%7D)'"
```

`up` must be `1` and the count above zero. The metric names start with `unpoller_` (`unpoller_device_*`, `unpoller_client_*`, `unpoller_site_*`).

`up` alone proves nothing: unpoller answers its scrape with `up` at `1` even when it cannot log in to UniFi, and then exports none of these series. The `unpoller_no_unifi_data` alert covers that case. It fires when no `unpoller_device_info` series has reached VictoriaMetrics for 10 minutes, whether the URL, the account or the controller is wrong, or unpoller is down.

The *UniFi* dashboard (uid `victoria-unifi`) shows the scrape state, the device and client counts, the disconnected devices, the pending firmware updates and the Internet latency, then CPU, memory, temperature and clients per device, and the WAN, per-device and top 10 client traffic. Its queries use the names of the unpoller Prometheus exporter source (`unpoller_device_info`, `unpoller_device_cpu_utilization_ratio`, `unpoller_device_wan_receive_bytes_total`, `unpoller_client_receive_bytes_total`, `unpoller_site_disconnected`, `unpoller_site_latency_seconds` and the like). They are not yet checked against real data: when the dashboard was written, unpoller exported only its own `unpoller_prometheus_*` metrics. Once the count above is not zero, check that each panel shows data and fix the names that differ.

### Synology Metrics (`snmp-exporter`)
The Synology NAS answers SNMP only, so VictoriaMetrics scrapes it through `snmp-exporter`. The `synology` job of `victoriametrics_scrape` asks `snmp-exporter:9116/snmp` every 60 seconds, with a 30 second timeout, to poll `SYNOLOGY_SNMP_TARGET` with the `system`, `if_mib` and `synology` modules of the default `snmp.yml` and the `synology_v3` auth. The `instance` label is the NAS name.

The `synology_v3` auth uses SNMPv3 with authentication and encryption (authPriv, SHA and AES). The compose file holds no password: the auth file references `${SNMP_USER}`, `${SNMP_AUTH_PASS}` and `${SNMP_PRIV_PASS}`, which the exporter expands at start (`--config.expand-environment-variables`) from its environment, filled from the `SYNOLOGY_SNMP_*` variables. Its `/config` page shows the user name but masks the passwords.

snmp-exporter runs as `65534:65534` with no published port and no Traefik route. It is on the internal `victoria` network, where VictoriaMetrics reaches it, and on the `snmp` network, its only route to the NAS (UDP 161).

Setup:

1. In DSM, *Control Panel > Terminal & SNMP > SNMP*: enable the SNMP service, turn SNMPv1/v2c off, and enable SNMPv3 with user `snmp-victoria`, protocol SHA, and privacy protocol AES, each with its own password.
2. In the environment of the stack, set `SYNOLOGY_SNMP_TARGET` (for example `pads918.home.lan`), and put the two passwords in `SYNOLOGY_SNMP_AUTH_PASS` and `SYNOLOGY_SNMP_PRIV_PASS`.
3. Redeploy the stack. Wrong passwords make the scrapes of the NAS fail (`up` at `0`); the rest of the stack runs.

After deployment, check the scrape:

```bash
ssh chataigne.home.lan "docker exec vmalert-logs wget -qO- 'http://victoriametrics:8428/api/v1/query?query=up%7Bjob%3D%22synology%22%7D'"
ssh chataigne.home.lan "docker exec vmalert-logs wget -qO- 'http://victoriametrics:8428/api/v1/query?query=systemStatus%7Bjob%3D%22synology%22%7D'"
```

`up` must be `1`. The metric names are the MIB names, without a prefix: `systemStatus` (`1` means normal), `temperature`, `diskStatus`, `diskTemperature`, `raidStatus`, `raidFreeSize`, plus the `ifHCInOctets` family of `if_mib` and `sysUpTime` of `system`. Filter them on `job="synology"`.

The *Synology NAS* dashboard (uid `victoria-synology`) shows the scrape state, the count of failed components (system, power, fans, thermal), failed disks (`diskStatus` or `diskHealthStatus` not `1`) and degraded pools or volumes, the system temperature and the uptime (`sysUpTime` is in hundredths of a second). It then plots CPU and memory use, volume occupancy, disk temperatures, the traffic of the physical interfaces (`eth*` and `bond*`; the loopback and Docker interfaces are left out) and their errors and discards (`ifInErrors`, `ifOutErrors`, `ifInDiscards`, `ifOutDiscards`), the disk I/O per device (`storageIONReadX`, `storageIONWrittenX`) and the UPS battery charge and load. The occupancy panel keeps the volumes only: a storage pool is fully allocated to its volume, so its own free space is always close to zero. These metric names and labels were checked against the NAS in production.

### Freebox Metrics (`freebox-exporter`)
The Freebox Delta runs in bridge mode: UniFi routes, the box only carries the fiber link. [freebox-exporter-rs](https://github.com/shackerd/freebox-exporter-rs) (`v0.0.26`, the last release; later tags are betas) reads the Freebox API every 30 seconds and exposes the result on port 9102. The `freebox` job of `victoriametrics_scrape` scrapes `freebox-exporter:9102` every 60 seconds. The exporter config (`freebox_exporter_config`) enables the `connection` and `system` modules only.

freebox-exporter runs as `65534:65534` with no published port and no Traefik route. It is on the internal `victoria` network, where VictoriaMetrics reaches it, and on the `freebox` network, its only route out to the box (`https://mafreebox.freebox.fr`, 443/tcp). TLS stays verified: the exporter pins the Freebox certificate authorities.

The token is a secret and stays out of the repository. The exporter reads it from `token.dat` in its data directory; the container writes `FREEBOX_APP_TOKEN` to that file on a `tmpfs` (`/data`, mode 0700) at start, then unsets the variable before it starts the exporter. The value still shows in `docker inspect`, like the other secrets of the stack. With `FREEBOX_APP_TOKEN` empty, the container logs `FREEBOX_APP_TOKEN is empty` and waits: the scrape fails and `freebox_scrape_down` fires after 10 minutes.

Setup (once, with physical access to the box):

1. On a Docker host that reaches the box, register the exporter. The Freebox asks for a confirmation on its front screen: press the button to accept within the time shown.

   ```bash
   mkdir -m 700 fbx
   docker run --rm -it --hostname freebox-exporter -v "$PWD/fbx":/data -w /data \
     ghcr.io/shackerd/freebox-exporter-rs:v0.0.26 \
     /usr/bin/freebox-exporter-rs -c /etc/freebox-exporter-rs/config.toml register
   ```

   The command writes the token to `fbx/token.dat`. The app shows up in Freebox OS as *Prometheus Exporter*.
2. In Portainer, put the content of `fbx/token.dat` in `FREEBOX_APP_TOKEN` in the environment of the stack, then delete the file (`rm -r fbx`). Redeploy the stack.
3. In Freebox OS, *Paramètres de la Freebox > Gestion des accès > Applications*, edit *Prometheus Exporter* and untick every right that changes something (settings, calls, contacts, downloads, files, parental control, VMs). The `connection` and `system` modules only read. If the exporter log then shows `insufficient_rights`, tick back only the right it names.

Bridge mode limits:

- The exporter disables its `lan_browser`, `switch`, `wifi` and `dhcp` modules in bridge mode, and the box serves no LAN in that mode anyway: there is no host, Wi-Fi or DHCP data. The `lan`, `nas` and `download` modules stay off here.
- In bridge mode the exporter calls `https://mafreebox.freebox.fr/api/`. That name resolves to a public Free address, which the box answers through UniFi (checked with `GET http://mafreebox.freebox.fr/api_version`). Whether it still answers while the fiber link is down is not checked: the DNS lookup itself may fail, and the scrape then fails too.
- When the Internet connection drops, `freebox_connection_down` fires, but its SMS (Free Mobile API) leaves only once the connection is back.
- `fbx_exporter_connection_ftth_sfp_pwr_rx` and `_pwr_tx` are the raw API values in hundredths of a dBm: the dashboard and `freebox_fiber_signal_low` divide them by 100. The received power read -16.9 dBm at deployment, a usual value for a GPON line.

After deployment, check the scrape:

```bash
ssh <docker-host> "docker exec vmalert-logs wget -qO- 'http://victoriametrics:8428/api/v1/query?query=up%7Bjob%3D%22freebox%22%7D'"
ssh <docker-host> "docker exec vmalert-logs wget -qO- 'http://victoriametrics:8428/api/v1/query?query=fbx_exporter_connection_state%7Bjob%3D%22freebox%22%7D'"
```

`up` must be `1`, and `fbx_exporter_connection_state{state="up"}` too. The other useful metrics are `fbx_exporter_connection_ftth_link`, `fbx_exporter_connection_ftth_sfp_has_signal`, `fbx_exporter_connection_rate_down` and `_rate_up` (current throughput), `fbx_exporter_connection_bandwidth_down` and `_bandwidth_up` (line capacity), `fbx_exporter_system_uptime_val`, `fbx_exporter_system_temp_cpum` and the other temperatures, and `fbx_exporter_system_fan_rpm`. Some metrics carry their value as a label set to `1`: `fbx_exporter_connection_media{media}`, `fbx_exporter_system_box_model_name{model_name}` and `fbx_exporter_connection_ipv4{ipv4}`, which holds the public IP. These names come from the exporter source and are not yet checked against the box. No dashboard uses them yet.

## 3. Vector (`vector`)

### Role
Single entry point of the logs. It receives:

- OTLP/HTTP logs on port `4318`, from the OpenTelemetry collectors deployed by myansible, through `https://<VICTORIA_LOGS_DOMAIN>/v1/logs`. The collector names the stream in the `stream-name` header (`otel_collector_streams` in myansible).
- UDP syslog on container port `5514`, published on the host as `VECTOR_SYSLOG_PORT`. This is the only port the stack publishes.

It also exposes its own metrics (`internal_metrics` source, `prometheus` sink) on port `9598`, which VictoriaMetrics scrapes. Traefik has no route to that port.

It then parses the records and writes them to `http://victorialogs:9428/insert/jsonline` on the Docker network.

```text
otlp -> normalize -> route_streams --docker, traefik--> redact_url_secrets -> route_authentik --authentik_*--> parse_authentik
                                   |--journald--> parse_http -> parse_proxmox
                                   |--other streams--> sink
syslog_udp -> parse_syslog
```

Every branch ends in the `victorialogs` sink.

The pipeline lives in [`config/vector/vector.yaml`](./config/vector/vector.yaml), which `build.py` writes into the `vector_config` entry of [`docker-compose.yml`](./docker-compose.yml), mounted on `/etc/vector/vector.yaml` (see [Configuration Sources](#configuration-sources)). It is inline rather than a `./vector.yaml` bind mount because Portainer resolves relative paths on its own disk: Docker then creates an empty directory on the host and the deployment fails with `mkdirat etc/vector/vector.yaml: file exists`. Inline `configs` need Docker Compose 2.23 or later. Vector 0.61 does not expand `${VAR}` in its configuration, so Compose writes `VECTOR_SYSLOG_SENDERS` and `VECTOR_SYSLOG_DOMAIN` into the pipeline.

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

### Common Level (`normalize_level`)
Records of every stream get a `level` field with one of five values: `debug`, `info`, `warn`, `error` or `crit`. Each source writes its level its own way; `level` lets one query cover all streams (`level:in(error,crit)`). The first source that gives a level wins:

1. `ak_level` (Authentik), then `pve_level` (Proxmox).
2. The journald priority `body_priority`: 0-2 give `crit`, 3 `error`, 4 `warn`, 5-6 `info`, 7 `debug`.
3. The `severity` text, syslog keyword or OTLP severity text, case ignored: `emerg`, `alert`, `crit*`, `fatal`, `panic` give `crit`; `err*` gives `error`; `warn*` gives `warn`; `info` and `notice` give `info`; `debug` and `trace` give `debug`.
4. The OTLP `severity_number`: 21-24 give `crit`, 17-20 `error`, 13-16 `warn`, 9-12 `info`, 1-8 `debug`.
5. The CEF severity `cef_severity` of the UniFi events: 9-10 give `crit`, 7-8 `error`, 4-6 `warn`, 0-3 `info`.
6. The level written in the line (`body`, else `body_message`, else `message`), read in its first 300 characters once the colour codes are removed:

   | Format | Example | Used by |
   | :--- | :--- | :--- |
   | logfmt or JSON key | `level=info`, `"level":"warn"`, `lvl=` | step-ca, Go and Node services |
   | zerolog console token | `<time> ERR ...` (`TRC`, `DBG`, `INF`, `WRN`, `ERR`, `FTL`, `PNC`) | Traefik, Portainer |
   | Go log letter | `...func1() [W] ...` (`T`, `D`, `I`, `W`, `E`, `F`) | Forgejo |
   | NestJS | `[Nest] 59 - <date>    LOG [Context]` (`LOG`, `VERBOSE`, `WARN`...) | Immich |
   | Word in brackets | `[debug][Jobs]` | Seerr |
   | Upper case word and colon | `[MONITOR] INFO: ...` | Uptime Kuma |
   | Redis marker | `1:M 27 Nov 2026 00:00:02.724 * ...` (`.` and `-` debug, `*` info, `#` warn) | Redis |

   A word inside the text (`Sync failed: error while syncing`) is not a level.

A record with none of these is `info`: every record has a `level`, so `level:in(error,crit)` misses only what its source does not mark as an error (a Trilium stack trace, a raw kernel line). The `alerts` stream skips this transform: `alert_rules` gives `error` to a rule that cannot be evaluated, `warn` to a firing or pending one and `info` to the others. The source fields are kept as they are. Records stored before `level` existed have none; the error panels of the *Logs* and *Docker* dashboards filter on `level`, so errors stored before that change do not show there.

### Sink Notes
- The sink sends `Content-Type: application/x-ndjson`. Without it VictoriaLogs answers `200` and stores nothing.
- End-to-end acknowledgements are on: the OTLP source answers the collector only once VictoriaLogs has accepted the batch, so the collector retries on failure. UDP syslog has no such retry: messages sent while Vector is down are lost.
- Batches are sent every 1000 events or 1 second. At home volumes a batch never fills, so an OTLP request waits up to this second for its answer.
- Vector keeps its state on a tmpfs (`/var/lib/vector`); the pipeline has no disk buffer.

### Secret Masking (`redact_url_secrets`)
Records of the `docker` and `traefik` streams have the values of secret-looking parameters (`token`, `code`, `password`, `key`...) replaced by `[REDACTED]` in `body`, `app_msg`, `app_message` and `app_requestpath`. A parameter whose name only contains such a word (`monkey=`) is not masked.

The same step turns the Traefik `app_downstreamstatus` and `app_originstatus` into integers: depending on the collector they arrive as `302.0` or `"302"`.

A Traefik access line without `app_servicename` is a request that never reached a service: a middleware answered it (forward-auth or HTTPS redirect, 301/302), no router matched it (404), or the client left (499). They are not lost records. When most of them come from one client on the same path, that client is misconfigured: for example an OTLP exporter still posting to the old OpenObserve paths `/api/default/v1/logs|traces|metrics`.

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
- `host_name` is the entry of the sender in `VECTOR_SYSLOG_SENDERS`, else its syslog `hostname` in lower case (with `.` and `VECTOR_SYSLOG_DOMAIN` added to a short name), else its IP. `device_vendor` comes from the same entry.
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

Each `key=value` extension also becomes a field of its own, as a string, named `cef_ext_` followed by the key in lower case: `cef_ext_unificategory`, `cef_ext_unifirisk`, `cef_ext_src`, `cef_ext_dst`, `cef_ext_proto`, `cef_ext_spt`, `cef_ext_dpt`, `cef_ext_act`, `cef_ext_msg`, and so on depending on the event type. Characters outside `[a-z0-9_]` become `_`. The prefix keeps an extension from overwriting a field of the event: a CEF `hostname=` lands in `cef_ext_hostname` and `hostname` keeps the syslog value. Records stored before this naming keep the old names (`UNIFIcategory`, `src`...), so panels and rules that filter on `cef_ext_*` miss them until they age out of retention.

#### Firewall Logs
The UniFi gateway also sends the iptables log lines of its firewall rules, without CEF:

```text
[LAN_WAN-D-40001] DESCR="block-dns" IN=br0 OUT=eth6 MAC=... SRC=2001:db8::1 DST=2001:4860:4860::8888 LEN=80 TC=0 HOPLIMIT=63 FLOWLBL=0 PROTO=UDP SPT=41153 DPT=53 LEN=40 MARK=0x21940000
```

The pipeline splits them into fields with a `fw_` prefix, so they never mix with the `cef_ext_src`, `cef_ext_dst` and `cef_ext_proto` of the CEF events. `message` is kept as received.

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

#### Synology Setup
In DSM, *Control Panel > Log Center > Log Sending*: send to the host address, port `514`, UDP, in the IETF format (RFC 5424). Add the NAS to `VECTOR_SYSLOG_SENDERS` with the `synology` vendor, for example `"192.168.69.100":{"name":"pads918.home.lan","vendor":"synology"}`. DSM starts each RFC 5424 message with a byte order mark (U+FEFF); `parse_syslog` removes it from the start of `message` and leaves any other one in place.

#### UniFi Setup
In UniFi Network, *Settings > CyberSecure > Traffic Logging* (or *System > Remote Logging* depending on the version): enable *SIEM Server* or *Syslog*, then set the host address and port `514`.

## Alerting

Two vmalert instances evaluate the rules, both defined in the `configs:` section of the compose file. `vmalert-logs` runs LogsQL rules against VictoriaLogs and `vmalert-metrics` runs MetricsQL rules against VictoriaMetrics. Both send their alerts to `alertmanager`. They keep the alert state (`ALERTS`, `ALERTS_FOR_STATE`) in VictoriaMetrics through `-remoteWrite.url` and read it back at startup through `-remoteRead.url`, so a restart does not reset a pending or firing alert.

The rules carry over the OpenObserve alerts and add alerts on hosts, DNS, UniFi, ZFS, the Synology NAS and the Freebox:

| Alert | Source | Fires when | Repeat |
| :--- | :--- | :--- | :--- |
| `authentik_login_failed_burst` | logs | 5 or more `login_failed` or `invalid_identifier` events in 15 minutes | 80m |
| `authentik_sensitive_event` | logs | a suspicious request, an impersonation, a system or policy exception, or a configuration error in 5 minutes | 70m |
| `authentik_errors` | logs | 3 or more `error` or `critical` records in 15 minutes | 80m |
| `authentik_logs_silent` | logs | no record from `server` or `worker` for 10 minutes, for a component seen in the last 24 hours | 65m |
| `proxmox_backup_failed` | logs | a failed vzdump job or guest in 15 minutes | 80m |
| `proxmox_task_failed` | logs | a failed task in 15 minutes | 1460m |
| `proxmox_auth_failed_burst` | logs | 5 or more failed Proxmox logins in 15 minutes | 80m |
| `proxmox_backup_missing` | logs | no successful vzdump job for 26 hours, once the stream holds records older than 24 hours (checked every hour) | 780m |
| `proxmox_metrics_silent` | metrics | no `proxmox_node_uptime_seconds` sample from a node for 10 minutes | 65m |
| `proxmox_storage_usage_high` | metrics | a storage at 85% or more | 725m |
| `proxmox_node_memory_high` | metrics | node memory at 90% or more, ZFS ARC excluded | 125m |
| `proxmox_node_cpu_high` | metrics | node CPU above 90% on a 15 minute average | 140m |
| `proxmox_guest_restarted` | metrics | a running guest with an uptime under 10 minutes | 45m |
| `unpoller_no_unifi_data` | metrics | no `unpoller_device_info` series from unpoller for 10 minutes | 65m |
| `host_logs_silent` | logs | no `journald`, `files` or `docker` record from a host for 30 minutes, for a host seen in the last 24 hours | 125m |
| `kernel_critical` | logs | a kernel message with `I/O error`, `EXT4-fs error`, `Hardware Error` or `blocked for more than` (hung task) in 15 minutes | 80m |
| `oom_kill` | logs | a kernel `Killed process <pid> (<process>)` message (OOM killer, cgroup included) in 15 minutes, per host and process | 80m |
| `systemd_unit_failed` | logs | a journald `<unit>: Failed with result '<result>'` message from systemd in 15 minutes | 1460m |
| `container_restart_loop` | logs | 5 starts or more of one container in 15 minutes (containerd `connecting to shim <id>`), GitLab runner `-predefined` helpers excluded | 80m |
| `dns_resolver_silent` | logs | no `dns_queries` record from an AdGuard resolver for 1 hour, for a resolver seen in the last 24 hours | 125m |
| `unifi_ips_event` | logs | a UniFi IPS/IDS or honeypot event (CEF, signature 203 excluded) in 15 minutes | 80m |
| `traefik_5xx_burst` | logs | 5 or more 5xx responses of one Traefik service in at least three 5 minute buckets of the last 30 minutes | 65m |
| `unifi_device_down` | metrics | no `unpoller_device_uptime_seconds` sample from a UniFi device for 10 minutes | 65m |
| `host_metrics_silent` | metrics | no `system_cpu_time_seconds_total` sample from a host for 10 minutes | 65m |
| `filesystem_usage_high` | metrics | a file system between 90% and 95% for 15 minutes, `vfat` and `tmpfs` excluded | 725m |
| `filesystem_usage_critical` | metrics | a file system at 95% or more for 15 minutes | 125m |
| `zfs_pool_degraded` | metrics | a ZFS pool not `ONLINE` | 65m |
| `zfs_pool_capacity_high` | metrics | a ZFS pool at 85% or more for 15 minutes | 725m |
| `synology_system_failed` | metrics | a system, power or fan status of the NAS other than normal | 65m |
| `synology_raid_degraded` | metrics | a NAS RAID not normal | 65m |
| `synology_disk_failed` | metrics | a NAS disk not normal, or with bad sectors | 65m |
| `synology_temperature_high` | metrics | the NAS above 60°C or a disk above 55°C for 10 minutes | 125m |
| `synology_scrape_down` | metrics | the `synology` scrape failing for 10 minutes | 65m |
| `freebox_connection_down` | metrics | the Freebox reporting its Internet connection other than `up` for 2 minutes | 65m |
| `freebox_scrape_down` | metrics | the `freebox` scrape failing for 10 minutes | 65m |
| `freebox_fiber_signal_low` | metrics | the optical power received by the Freebox SFP under -26 dBm for 30 minutes, while it still has a signal (GPON receivers lose the link near -28 dBm) | 125m |
| `freebox_temperature_high` | metrics | the hottest Freebox CPU core above 85°C for 15 minutes | 125m |
| `smart_status_failed` | metrics | a host disk with a failed SMART overall status | 65m |
| `smart_attribute_failing` | metrics | a normalized SMART attribute at or under its non-zero threshold | 1445m |
| `smart_sectors_growing` | metrics | reallocated, pending or uncorrectable sectors above their 24 hour minimum | 2885m |
| `smart_crc_errors_growing` | metrics | CRC errors above their 24 hour minimum (cable or connector) | 2885m |
| `smart_temperature_high` | metrics | a host disk above 55°C for 10 minutes | 125m |
| `smart_data_missing` | metrics | no `smartctl_device_smart_status` sample from a host for 30 minutes, for a host seen in the last 24 hours | 125m |
| `zfs_data_missing` | metrics | no `zfs_pool_health` sample from a host for 30 minutes, for a host seen in the last 24 hours | 125m |

The repeat column replaces the OpenObserve silence period. Each alert has its own Alertmanager route. `keep_firing_for` keeps the alert firing for that long after the last match, so an alert that flaps does not send one SMS per flap. A single event therefore keeps an alert firing for the event window of the rule (the `[15m]` of a log rule, the 24 hours of a `lag`), plus its `keep_firing_for`, plus the interval of its group. The `repeat_interval` of each route is at least that lifetime, rounded up to 5 minutes: one event sends one SMS, and a problem that lasts sends one more per interval. A shorter `repeat_interval` would send a second SMS for an event that is already over. Alertmanager groups by `alertname` (one SMS per rule), waits 30 seconds before the first SMS of a group, and sends nothing when an alert resolves. Its notification log and silences live in `ALERTMANAGER_DATA_DIR`, so a restart does not send the SMS of a firing alert again.

Grouping by host as well would send one SMS per host when an outage hits all of them. Alertmanager drops the alerts that a cause already explains instead (`inhibit_rules`):

| Firing alert | Drops | On the same |
| :--- | :--- | :--- |
| `host_metrics_silent` | `host_logs_silent`, `smart_data_missing`, `zfs_data_missing`, `dns_resolver_silent` | `host_name` |
| `unpoller_no_unifi_data` | `unifi_device_down` | (any) |
| `filesystem_usage_critical` | `filesystem_usage_high` | `device`, `type` |
| `smart_status_failed` | `smart_attribute_failing`, `smart_sectors_growing`, `smart_crc_errors_growing` | `host_name`, `device` |

An inhibited alert still shows in vmalert and in the *Alertes* dashboard; only its SMS is dropped.

The file system alerts group by `device` and `type`, without `host_name`: several hosts mount the same NFS share or ZFS dataset, and one full device sends one SMS. The silence alerts (`host_logs_silent`, `dns_resolver_silent`, `unifi_device_down`, `host_metrics_silent`, `smart_data_missing`, `zfs_data_missing`) only know a source seen in the last 24 hours. A source that stays silent longer leaves the window and the alert resolves without an SMS.

The SMART raw counts are gauges that the disk keeps for its whole life, so the growth alerts compare the last value with its 24 hour minimum instead of using `delta`: VictoriaMetrics counts the first value of a new series as a rise, and an old CRC error would send an SMS after each deployment of the exporter. A count that drops, such as a pending sector that gets reallocated, does not fire. The condition holds for 24 hours after a rise and `keep_firing_for` adds 24 hours, so the route repeats after 2885 minutes: a single rise sends one SMS, and a disk that keeps degrading one SMS every two days.

`proxmox_task_failed` includes `acmerenew`: the `proxmox_tls` role of myansible removes the ACME settings of the Proxmox host, so a failed ACME renewal means they came back. A failed `proxmox-tls-renew.service` (or any other unit) fires `systemd_unit_failed`. Certificate expiry itself is not watched here: turn on the certificate expiry notification of the Uptime Kuma HTTPS monitor of the host.

The journald message is in `_msg`: the VictoriaLogs sink of Vector names `body_message` in `_msg_field`, so a log rule reads `_msg` (or a plain word filter), never `body_message`.

`container_restart_loop` reads the containerd journal, as no container metric reaches VictoriaMetrics. containerd logs `connecting to shim <container id>` at every container start. Docker restarts a crashing container with a backoff capped at one minute, so 5 starts in 15 minutes means a loop, while a one-shot init container that Portainer starts again every 5 minutes stays under it. The rule joins the id with the `docker` stream of the last hour to get `container_name`: a container that never logged keeps an empty name, and the SMS shows its short id. `traefik_5xx_burst` needs the errors in three distinct 5 minute buckets, so a single burst during a deployment does not fire.

The SMS carries the context of the alert. The rules keep the useful fields as `by` labels (user and client IP, Proxmox task type, VM and status, authentik component, systemd unit and result), and the summaries print them, with `{{ with }}` for a label that can be empty. A rule with a global threshold, such as 5 failed logins in total, counts per label set and adds them up with `total_stats`: the threshold stays global, and the labels of one matching set go into the summary.

### Alert State

Vector polls `/api/v1/rules` of `vmalert-logs` and `vmalert-metrics` every minute (sources `vmalert_logs_rules` and `vmalert_metrics_rules`) and the `alert_rules` transform writes one record per rule to VictoriaLogs, in the `alerts` stream. The message is the reason of the state:

- `firing` or `pending`: the summaries of the active alerts, joined with ` | `;
- `inactive`: `Condition non remplie : ` and the description of the rule;
- a failed evaluation: `Erreur d'evaluation : ` and the vmalert error, whatever the state.

The other fields are `alert_rule`, `alert_group`, `alert_source` (`logs` or `metrics`), `alert_state`, `alert_health` (`ok`, or `err` when the evaluation failed; a query without result is `ok`), `alert_severity`, `alert_count` (active alerts), `alert_active_since` (the oldest `activeAt`, only while an alert is active), `alert_last_evaluation` and `alert_last_samples`. With 49 rules, that is about 70,000 small records a day.

The *Alertes* dashboard (uid `victoria-alerts`) reads the last poll, within 3 minutes: active, pending and failing rules, the number of rules watched (red at 0, when the polling stops), and a table of every rule with its state, its reason and since when, active rules first. Over the time range, it graphs the active, pending and failing rules and lists each episode of a rule in a state: one row per `alert_active_since` (the real start, even before the time range), its first and last poll and its last reason. Evaluation errors have no start and stay in one row per rule. A rule with several alerts starts a new row when its oldest alert ends while the others go on, since its start moves to the next oldest one. The watchdog fires all the time by design; its severity `none` keeps it out of the active count, and the table shows it in green as *en service*, the healthy state, instead of red.

A rule that vmalert does not return, such as one in a group that failed to load, has no record. A vmalert instance that is down leaves no record either: *Règles surveillées* drops and `up{job="vmalert-logs"}` fires `victoria_component_down`.

### Watchdog

The alerts above only reach a phone if VictoriaLogs, vmalert, Alertmanager, Vector and Free Mobile all work. The `victoria_stack` group of `vmalert-metrics` and an Uptime Kuma push monitor watch that chain.

VictoriaMetrics scrapes every component of the stack every 30 seconds: `victoriametrics:8428`, `victorialogs:9428`, `vmalert-logs:8880`, `vmalert-metrics:8880`, `alertmanager:9093` and `vector:9598` (jobs of the same names). Three more alerts use these series:

| Alert | Fires when | Repeat |
| :--- | :--- | :--- |
| `victoria_component_down` | a component scrape failing for 5 minutes | 65m |
| `vmalert_rule_errors` | two or more failed evaluations of the same rule in 2 hours (a restart of a datasource fails only one) | 245m |
| `alertmanager_notifications_failed` | failed Alertmanager notifications in every 5 minute window for 10 minutes, by receiver (`--enable-feature=receiver-name-in-metrics`) | 70m |
| `vmalert_send_failed` | alerts that a vmalert instance failed to send to Alertmanager in every 10 minute window for 15 minutes | 75m |

These alerts go out by SMS, so they cannot report the failure of the SMS path itself. The `watchdog` alert covers it the other way round: it fires while the path works, and Alertmanager sends it every minute to the `watchdog` receiver, a webhook to `ALERTMANAGER_WATCHDOG_URL` that bypasses Vector. Uptime Kuma marks the monitor down when no push arrives within its interval, and notifies through its own channel. The watchdog stops when:

- `vector`, `victorialogs` or `vmalert-logs` fails its scrape or has no `up` series;
- the `free_mobile` sink of Vector logged an error in the last 30 minutes (`vector_component_errors_total`);
- VictoriaMetrics, `vmalert-metrics`, Alertmanager or the host is down, since nothing evaluates or sends it any more.

The watchdog has no `for` and no `keep_firing_for`, so it stops at the first evaluation that finds a fault. Its route comes first and sends no resolved notification. Alertmanager reaches Kuma through the `alertmanager` network, the only one of the stack that is not internal, with the CA bundle of the host for TLS. When the push itself fails, `alertmanager_notifications_failed` sends an SMS naming the `watchdog` receiver.

Limits: Uptime Kuma runs on the same host. A host outage silences both the stack and Kuma; only an external check of Kuma would catch it. The `free_mobile` error branch is only tested on replayed series (`metrics_rules_unittest.yaml`), not end to end: the counter only appears after a first error, and VictoriaMetrics counts that first value in `increase()`, so the first error after a Vector restart stops the watchdog for 30 minutes. A Free Mobile answer of `403` or `400` is an error for Vector, so wrong credentials stop the watchdog.

### SMS Bridge

Alertmanager posts its webhook to the `alertmanager_webhook` source of Vector (`http://vector:8080/alertmanager`, at most 10 alerts per call), with Basic auth: user `alertmanager`, password `VECTOR_WEBHOOK_PASSWORD`. Vector answers `401` to any other request, so a container on `traefik_gateway` or `victoria` cannot send an SMS. Vector 0.61 no longer expands environment variables in its config, so Compose writes the password in plain text into both config files, like the watchdog URL: whoever reads the stack in Portainer or the files inside the two containers reads it too. The `sms_message` transform writes one line per firing alert, from its `summary` annotation, adds `(+N autres alertes)` when Alertmanager truncated the list, and cuts the text at 900 characters. The `free_mobile` sink posts `{user, pass, msg}` as JSON to `https://smsapi.free-mobile.fr/sendmsg`, one SMS per request, with TLS verification on. It retries 3 times on a `5xx` and gives up on the other errors:

| Free Mobile code | Meaning |
| :--- | :--- |
| `200` | SMS sent. |
| `400` | Missing parameter. |
| `402` | Too many SMS in too little time. |
| `403` | SMS option off in the customer area, or wrong credentials. |
| `500` | Server error, retried. |

With `FREE_MOBILE_USER` or `FREE_MOBILE_PASS` empty, Vector logs `SMS not sent` as an error and drops the message. The alerts still show in vmalert and Alertmanager.

### Post-Deployment Check of the Metric Names

The metric rules and the Proxmox dashboard use the names that VictoriaMetrics holds for the Proxmox VE OpenTelemetry metric server (`proxmox_node_uptime_seconds`, `proxmox_storage_used_bytes`, `proxmox_node_memory_arcsize_bytes`, `proxmox_vm_uptime_seconds`...). They were checked against live data. The unit suffixes come from `-opentelemetry.usePrometheusNaming`: `bytes` adds `_bytes` (`_bytes_total` on a counter), `seconds` adds `_seconds`, `percent` adds `_percent` and `1` adds `_ratio`. CPU values are fractions from 0 to 1 despite the `_percent` suffix. Labels are `host_name` (node), `storage`, `type`, `vmid` and `name` (guest), and `device` (network).

The Proxmox VE plugin picks the unit of `pressurecpusome` at random: the name matches two entries of its unit table (`cpu` in percent, `cpus` in ratio), and the plugin walks that table in Perl hash order, which changes with each process. The series lands as `proxmox_vm_pressurecpusome_percent` or `proxmox_vm_pressurecpusome_ratio`, with the same 0 to 100 values, so the dashboard reads `{__name__=~"proxmox_vm_pressurecpusome_(percent|ratio)"}`.

A wrong name gives a rule that never fires and an empty panel, with no error. After a deployment or a Proxmox VE upgrade, run [`tests/check_metric_names.sh`](./tests/check_metric_names.sh) from `victoria/`:

```bash
ssh chataigne.home.lan "docker exec vmalert-logs wget -qO- http://victoriametrics:8428/api/v1/label/__name__/values" | ./tests/check_metric_names.sh
```

It extracts every `proxmox_node_*`, `proxmox_vm_*` and `proxmox_storage_*` name from `docker-compose.yml` (alert names left out) and fails on each name that VictoriaMetrics does not hold, and on each `__name__=~` regex that matches no name. It needs Python 3.

## Grafana

`victoria-grafana` is separate from the `grafana` stack of this repository. It trusts the `X-authentik-username` header that the Authentik forward auth sets (auth proxy) and creates the user at the first login. No Grafana password works: the login form, Basic auth, anonymous access and the auth proxy login token are off. The Authentik user named in `GRAFANA_ADMIN_USER` is the Grafana server admin. The other users get `GRAFANA_DEFAULT_ROLE` (`Viewer` by default).

`GF_AUTH_DISABLE_LOGIN` stays unset. Grafana 13.2 answers HTTP 500 to every proxied request when it is `true`, and `tests/test_stack.sh` fails if it is set.

Grafana installs the `victoriametrics-logs-datasource` plugin at the pinned version before it starts (`GF_PLUGINS_PREINSTALL_SYNC`), which needs Internet access from the host at the first start. The plugin then stays in `GRAFANA_DATA_DIR`.

The datasources (`victorialogs`, `victoriametrics`) and sixteen dashboards are provisioned from the compose file. Grafana files each dashboard in a folder named after the directory of its file (`foldersFromFilesStructure`):

| Folder | Dashboards |
| --- | --- |
| root (General) | *Services rendus*, *Hosts*, *Logs*, *Alertes*, *Réseau*: the overview and cross-source ones |
| Infrastructure | *Proxmox VE*, *Synology NAS*, *Disques*, *Pile Victoria* |
| Équipements réseau | *UniFi*, *Freebox*, *Firewall*, *DNS* |
| Applications | *Authentik*, *Docker services*, *HTTP* |

The links between dashboards use their uid or their tags, never their folder or URL path, so moving a dashboard to another folder keeps them working. A dashboard provisioned before this layout moves from General to its folder at the next Grafana start.

Query rules shared by the dashboards:

- Every `rate()` of a time series uses the `$__rate_interval` window, which Grafana sizes from the time range and the panel width. A fixed `[5m]` window reads one point in many over 7 days, so a short spike vanishes. The VictoriaMetrics datasource declares `timeInterval: 60s`, the longest scrape interval (UnPoller, Synology and Freebox); `$__rate_interval` is then at least 4 minutes, enough for 4 samples of every job. The instant stats and tables that give a current rate keep `[5m]`.
- A stat without a sparkline shows one value, so its query is instant: it reads the current value at the end of the time range. A range query would fetch about a hundred points to keep only the last one, and its `lastNotNull` would still show the value of a series that stopped hours ago, for example the uptime of a node that no longer reports.
- The age of the last metric of each host comes from the `host_name:metrics_age_seconds:max` record of `vmalert-metrics` (group `host_metrics`), evaluated every minute, instead of a `lag(...[24h])` that each refresh recomputed over 24 hours of raw samples. The *silent hosts* stats of the hosts and services dashboards and the hosts table of *Services rendus* read it. The series only exists once `vmalert-metrics` runs: after a first deployment, these panels stay empty until its first evaluation, and they go empty if `vmalert-metrics` stops. A host gone for more than 24 hours leaves the record, like it leaves the alert.
- The *Logs* dashboard filters `log_stream` as a stream filter (`{log_stream in(...)}`), which VictoriaLogs resolves on its stream index instead of reading every record. The *Erreurs dans les logs* stat of *Services rendus* counts the `docker`, `syslog`, `journald` and `authentik` streams only: the streams that have their own panel (`traefik`, `dns_queries`, `firewall`, `proxmox`) or are not errors stay out. A new stream must be added to that list to count.
- The log dashboards (*Logs*, *Docker services*, *DNS*, *Firewall*, *HTTP*) refresh every 5 minutes, as each refresh scans the log range; the others every minute.

*Services rendus* (uid `victoria-services`) is the global view and the entry point: every other dashboard links back to it. Its stats sum up the services rendered over the selected period (active alerts, HTTP requests, 5xx rate and p95 latency, DNS queries and p95 latency without cache, failed logins, successful and failed backups, Docker errors, error-level logs, blocked packets) and the infrastructure (silent hosts, disconnected UniFi devices, Internet latency, running Proxmox guests, Synology collection, degraded storage). Each stat opens the dashboard that details it. A table lists the web services seen by Traefik with their requests, 4xx and 5xx shares, p95 latency and last request, worst 5xx first, and opens the HTTP dashboard filtered on the service; a table of the hosts gives the age of their last metric, CPU, memory and fullest file system, and opens the hosts dashboard filtered on the host.

Six of them cover every source:

- *Hosts* (uid `victoria-hosts`): the OpenTelemetry host metrics. Hosts reporting and silent for 10 minutes, the fullest file system, degraded ZFS pools, then CPU, memory, load, file systems, disk and network I/O, and a *Système* row: inode use per file system, network errors and drops, major page faults and swap paging, running and blocked processes. Filtered by `host_name`. The file systems are on this dashboard only; the ZFS pools are on *Disques*.
- *Logs* (uid `victoria-logs`): every stream, filtered by `log_stream`, `host_name` and a free LogsQL search. Volume and errors by stream, host and Docker container, and the last 200 records.
- *Docker services* (uid `victoria-docker`): the `docker` stream, filtered by host, Compose project, container and search. Logs and errors by container, stdout against stderr, the most frequent error messages, and the containers that logged in the last 24 hours but not in the last hour.
- *DNS* (uid `victoria-dns`): the AdGuard query log (`dns_queries`), filtered by resolver, client and search. Queries, blocked share, cache hit rate, p95 latency without cache, queries by type, result and upstream, top clients and domains, blocked domains, and the slowest domains with at least 3 queries.
- *Firewall* (uid `victoria-firewall`): the drops of the UniFi gateway (`syslog`), filtered by host, action, rule set and search. Blocked packets, blocks from the WAN, top sources, ports and destinations, triggered rules, and the UniFi CEF events (IPS/IDS, honeypot, policies).
- *HTTP* (uid `victoria-http`): the Traefik access log (`traefik`), so every web service published through Traefik, filtered by host, Traefik service, method, client and search. Requests, 4xx and 5xx rates, p95 latency, bytes sent and distinct clients, then requests, status classes, latency and 5xx by service, the paths in error, the busiest clients, the slowest paths with at least 3 requests, TLS versions and protocols, and the last 4xx and 5xx.

*Alertes* (uid `victoria-alerts`) shows the state of every alert rule and why (see [Alert State](#alert-state)).

*Disques* (uid `victoria-disks`) gathers the hardware state of the disks. At the top: NAS disks in fault (status or health not normal, or a bad sector), failed SMART attributes, degraded Synology and ZFS pools, the hottest disk, the lowest SSD remaining life and the most fragmented ZFS pool. Then a table of the NAS disks with model, type, role, status, health, temperature, remaining life, bad sectors, retries and identify failures; a table of the SMART raw values of the NAS hard disks (power-on hours, start/stop and head load counts, reallocated, pending and uncorrectable sectors, CRC errors, timeouts); the temperature of each NAS disk and the remaining life of the cache SSDs over time; NAS throughput and IOPS per disk; the state of the Synology and ZFS pools and the occupancy of the Synology volume, the ZFS pools and the Proxmox storages, and the free-space fragmentation of each ZFS pool; for the Linux hosts the disk busy time, throughput and mean latency per operation; and the SMART of the host disks: a table per disk (model, capacity, SMART status, temperature, remaining life, power-on hours, reallocated, pending and uncorrectable sectors, CRC errors, logged errors), their temperature, their bad sectors, their remaining life and the SMART error log count over time. The host SMART comes from `smartctl_exporter` (myansible role `smartctl_exporter`, service `smart`), today on chataigne only; a host without it shows occupancy and I/O only. Synology does not publish the SMART of its NVMe cache over SNMP. Crucial SSDs name the pending sectors `Current_Pending_ECC_Cnt`, so the panels and `smart_sectors_growing` read it next to `Current_Pending_Sector`. Seagate encodes `Raw_Error_Rate` and `Seek_Error_Rate` over several fields and caps the lifetime counters, so the dashboard leaves them out. No metric links a NAS `diskID` to its `sdX` device, so the SMART and I/O panels name the device and the status table names the disk.

*Freebox* (uid `victoria-freebox`) shows the fiber link of the Freebox Delta from the `freebox` job (see [Freebox Metrics](#freebox-metrics-freebox-exporter)). At the top: the scrape, the Internet connection, the FTTH link, the optical signal, the received power in dBm and the uptime of the box. Then the download and upload rates (`rate_*`, bytes per second, times 8) against the line bandwidth, the volume received and sent per hour, the received and emitted optical power, the temperatures of the CPU cores and of the internal switch, and the fan speed. The `temp_hdd`, `temp_t1` and `temp_t2` sensors read 0 on this box and are left out.

*Réseau* (uid `victoria-network`) shows at a glance which link of the home network is down. Its Canvas panel draws the tree Internet → Freebox → `gw` → `sw24poe` → the three access points, `chataigne` and the NAS. Each box is green when the device answers, red when its collector answers but the device does not, and grey when no collector answers, so a stopped exporter does not pass for a network outage. The sources are the metrics already collected: the Internet connection, the scrape and the FTTH link of the `freebox` job; the uptime of each UniFi device and the WAN status of the gateway from `unpoller`; the scrape of the `synology` job; and the host metrics of `chataigne` from the OpenTelemetry collector, fresh within 5 minutes. The links from the gateway to the switch and from the switch to the servers are drawn from the known cabling: unpoller only reports the uplink of the access points. Below: the state of each collector, a table of the UniFi devices (uptime, CPU, memory, temperature, clients, pending update), the site latency, the WAN rates of the gateway and of the Freebox, and, from VictoriaLogs, the last syslog line of each UniFi device and its warnings and errors.

*Pile Victoria* (uid `victoria-stack`) watches the stack itself from the metrics that each component exposes (jobs `victoriametrics`, `victorialogs`, `vmalert-logs`, `vmalert-metrics`, `alertmanager`, `vector`). At the top: unreachable components, logs and points ingested per second, and over the last hour the Vector component errors, the vmalert rule errors and the Alertmanager notifications that failed. Then the free disk space and data size of VictoriaLogs and VictoriaMetrics, the rejected rows (VictoriaLogs drops by reason and over-long lines, VictoriaMetrics invalid rows) and the new series per hour, which reveal a cardinality burst; the Vector events received per source and sent per sink, its errors and the utilization of each component; the vmalert evaluation duration per group (quantile 0.9), the firing alerts and the notifications sent and failed; the memory and CPU of each component, and a table with its scrape state, uptime, restarts over 24 hours and version. Vector does not expose the `process_*` metrics, so it has no memory or CPU curve; its uptime and restarts come from `vector_uptime_seconds`, whose `host` label changes with each new container, so each series after the first counts as a restart.

The other four cover one application: *Authentik* (uid `victoria-authentik`), *Proxmox VE* (uid `victoria-proxmox`), *UniFi* (uid `victoria-unifi`, see [UniFi Metrics](#unifi-metrics-unpoller)) and *Synology NAS* (uid `victoria-synology`, see [Synology Metrics](#synology-metrics-snmp-exporter)).

Known gaps of the data behind them: AdGuard does not send the DNS response code, so the DNS dashboard has no NXDOMAIN or SERVFAIL panel. The firewall dashboard only shows the rules that the gateway logs; a WAN rule with logging off leaves *Bloqués depuis le WAN* empty. The HTTP dashboard only sees what goes through Traefik: the Proxmox web UI (`pveproxy`) and HAProxy have no access log in VictoriaLogs. It drops the Traefik lines without a host, such as a request that matched no router. It also drops the ingestion routers (`vector_ingest`, `victoriametrics_ingest`): the collectors leave their own successful requests out of the access log (role `otel_collector` of myansible), so only the `502` of a Vector or VictoriaMetrics restart would remain and show the ingestion as 100 % 5xx. Those `502` still count in the `traefik_5xx_burst` alert. Traefik logs a WebSocket session with status `0` once it ends, so the status class `0xx` is mostly WebSocket traffic, plus clients that left before the response. The latency panels leave out these sessions and the Forgejo event stream (`/user/events`, Server-Sent Events with status `200`), which last as long as the browser tab; the request counts keep them. Traefik logs no header, so a new SSE endpoint is only left out once its path is added to that filter, and a host serving only such streams shows no latency. A failed WebSocket handshake keeps its real status, `502` or `404`, and its latency counts. Requests from a container reach Traefik from the Docker bridge (`172.18.0.1`), which has no UniFi name.

The dashboards are read-only in the UI: an edit cannot be saved, and a change goes into the `grafana_dashboard_*` configs.

Five IP tables add the UniFi name and MAC of each IP: *Clients les plus actifs* and *Clients les plus bloqués* on the DNS dashboard, *Top sources bloquées* and *Top destinations bloquées* on the firewall dashboard, and *Clients les plus actifs* on the HTTP dashboard. A second query reads the UnPoller series `unpoller_client_uptime_seconds` (clients) and `unpoller_device_info` (UniFi devices) over the dashboard time range, and Grafana joins its result to the log rows on the IP. When an IP changed hands during the range, for example a DHCP lease given to another device, the table shows the device seen last. An IP that UniFi does not know, such as a public address, keeps empty *nom UniFi* and *MAC* columns. Grafana runs the join in the browser, so a query sent to the datasource API returns the IPs without names.

The other panels show IPs only: *Requêtes par client* (a time series), *Flux bloqués récents*, *Événements IPS/IDS* and the log panels. *Blocages UniFi par politique et client* already has the client name that the gateway logs (`UNIFIsrcClientAlias`). The OpenObserve Authentik dashboard enriched source IPs with their reverse DNS name (ptr). Neither VictoriaLogs nor Grafana has such a lookup.

### MCP Server (`grafana-mcp`)

`victoria-grafana-mcp` runs [mcp-grafana](https://github.com/grafana/mcp-grafana) so that an MCP client (Claude Code, for example) can search the dashboards, run LogsQL and PromQL queries through the datasources and read the alert rules. It answers on `https://<VICTORIA_GRAFANA_DOMAIN>/mcp` in streamable HTTP, without Authentik: an MCP client cannot follow a browser login. It starts with `--disable-write`, which removes every tool that changes Grafana (dashboards, datasources, folders, annotations, alert rules, silences, plugins, incidents).

Setup:

1. In Grafana, as the admin, open *Administration > Users and access > Service accounts*, create `mcp` with the `Viewer` role, then add a token to it. Put the token in `GRAFANA_MCP_SA_TOKEN`.
2. Generate the client token with `openssl rand -hex 32` and put it in `GRAFANA_MCP_SERVER_TOKEN`.
3. Redeploy the stack. The log of `victoria-grafana-mcp` shows `Caller authentication enabled`.
4. Add the server to the client, in the user scope so that it loads from any directory (without `-s user`, Claude Code uses the local scope, tied to the current directory only). `read -rs` keeps the token off the screen and out of the shell history:

```bash
read -rs GRAFANA_MCP_SERVER_TOKEN
claude mcp add -s user --transport http grafana "https://$VICTORIA_GRAFANA_DOMAIN/mcp" --header "Authorization: Bearer $GRAFANA_MCP_SERVER_TOKEN"
unset GRAFANA_MCP_SERVER_TOKEN
```

`claude mcp list`, run from any directory, then shows `grafana` as connected. Claude Code stores the header in clear in its configuration file (`~/.claude.json`, or `.mcp.json` with `-s project`, which must stay out of Git), and in its backups under `~/.claude/backups/`.

mcp-grafana serves every request without authentication when its server token is empty. The compose file therefore replaces its entrypoint with a shell check: while either token is empty or the server token is shorter than 32 characters, the container logs `... is missing, see the README` and waits without listening, so it neither serves openly nor restarts in a loop.

The server checks the `Host` header against `VICTORIA_GRAFANA_DOMAIN` (`403` otherwise) and refuses any request with an `Origin` header (`403`), so a web page cannot call it from a browser. It keeps no session: each request carries the bearer token.

## 4. Access Control

The three UI routers (`victorialogs`, `victoriametrics`, `victoria_grafana`) go through the `authentik@docker` forward-auth middleware of the management stack, placed first so that the UIs fail closed while `authentik_server` is down. A browser must log in to Authentik as a member of `victorialogs-users`, `victoriametrics-users` or `victoria-grafana-users`. The providers, applications and groups are created by the `20-forward-auth-apps.yaml` blueprint of the management stack, which reads the host names from `VICTORIA_LOGS_HOST_LOCAL`, `VICTORIA_METRICS_HOST_LOCAL` and `VICTORIA_GRAFANA_HOST_LOCAL` in `management/.env`. VictoriaLogs and VictoriaMetrics have no login of their own: Authentik is the only access control on the UIs and the query APIs. Grafana relies on the user name that Authentik passes in `X-authentik-username`.

Collectors cannot follow a browser login, so two routers skip Authentik for ingestion only:

- `vector_ingest`: `POST` on exactly `/v1/logs` of the logs host, to `vector`.
- `victoriametrics_ingest`: `POST` on exactly `/opentelemetry/v1/metrics` of the metrics host, to `victoriametrics`.

Both carry only the `victoria-ingest-auth@file` middleware: HTTP Basic auth defined in `management/traefik_dynamic.toml`, which removes the `Authorization` header before the backend.

Two more routers, `victorialogs_health` and `victoriametrics_health`, skip every middleware for `GET` and `HEAD` on exactly `/health`, for the Uptime Kuma HTTP monitors. That endpoint only returns `OK`.

The `victoria_grafana_mcp` router skips every middleware for `POST`, `GET` and `DELETE` on exactly `/mcp` of the Grafana host, to `grafana-mcp` (see [MCP Server](#mcp-server-grafana-mcp)). The bearer token checked by mcp-grafana is the only access control there.

The `*_http` routers only redirect HTTP to HTTPS.

Limits:

- Ports `9428`, `8428` and `4318` have no authentication of their own. Every container on the `traefik_gateway` network can query and write the databases and send logs to Vector. Only the UDP syslog port is published on the host.
- Grafana port `3000` is not published, but a container on `traefik_gateway` that reaches it directly can send its own `X-authentik-username` header and log in as any user, the admin included. Through Traefik, the forward auth replaces that header.
- vmalert-logs, vmalert-metrics and Alertmanager have no route and no published port. The vmalert instances sit only on the internal `victoria` network. Alertmanager also sits alone on the `alertmanager` network, which is not internal, to reach Uptime Kuma; no other container is on it. Their UIs are reachable only from the containers of this stack.
- The Vector metrics port `9598` has no authentication and no route. Any container on `traefik_gateway` can read it.
- Anyone holding `GRAFANA_MCP_SERVER_TOKEN` reads, through `/mcp`, everything the `mcp` service account sees: every dashboard, log and metric. There is no per-user identity, rate limit or expiry; rotating the token means changing it in the stack and in every client. The service account token has no expiry either unless one is set in Grafana. On `traefik_gateway`, port `8000` asks for the same token.
- While Authentik is down, the UIs are unreachable. Ingestion and `/mcp` keep working.
- UDP syslog is unauthenticated, like any syslog: any host that reaches the port can send messages. `host_name` and `device_vendor` only come from the sender table for listed IPs.

## 5. Migration from OpenObserve

- The OpenObserve history is not migrated. Keep the OpenObserve data directory until the retention period has passed if the old logs are still needed.
- The OpenObserve alerts and dashboards are rewritten in this stack (see [Alerting](#alerting) and [Grafana](#grafana)). The `openobserve/` directory and its exports are gone from the repository.
- The collectors deployed by myansible must point to the new endpoints with the new Basic auth credentials: `https://<VICTORIA_LOGS_DOMAIN>/v1/logs` and `https://<VICTORIA_METRICS_DOMAIN>/opentelemetry/v1/metrics`.
- The stack has no backup. Back up the four data directories (`VICTORIA_LOGS_DATA_DIR`, `VICTORIA_METRICS_DATA_DIR`, `ALERTMANAGER_DATA_DIR`, `GRAFANA_DATA_DIR`) with the host tooling if they must survive a disk loss; VictoriaLogs and VictoriaMetrics support file-level copies of a stopped instance and VictoriaMetrics snapshots (`/snapshot/create`).

Switch-over order:

1. Stop OpenObserve before pulling this change, while its compose file is still there (`docker compose down` in `openobserve/`, data kept): both stacks serve `logs.<domain>`. From then until step 5, the collectors get a `401` from the new endpoint and drop what they send, and no alert runs.
2. Replace the hash of the `victoria-ingest-auth` middleware in `management/traefik_dynamic.toml` (step 2 of First Deployment).
3. Set the three `*_HOST_LOCAL` variables (logs, metrics, Grafana), redeploy the management stack (Authentik blueprint), set `FREE_MOBILE_USER`, `FREE_MOBILE_PASS` and `VECTOR_WEBHOOK_PASSWORD` in the environment of the stack, then start this stack.
4. Check `/health` on both hosts, then log in to the two UIs and to Grafana through Authentik.
5. Put the ingestion password in the myansible vault (`vault_victoria_ingest_auth`), redeploy the collectors (`make logs` in myansible) and check that every host shows up in VictoriaLogs.
6. Run the metric name check of [Alerting](#post-deployment-check-of-the-metric-names) once Proxmox has sent metrics.
7. Delete the OpenObserve data directory once its logs are no longer needed.

## 6. Tests

[`tests/test_build.sh`](./tests/test_build.sh) checks the generator of [Configuration Sources](#configuration-sources) without starting anything: the compose file is up to date, `docker compose config` with `.env.example` renders each of the 25 configs to its source with only the listed variables interpolated (each listed variable must be used), an edited source fails `--check` until `build.py` runs, a `$` becomes `$$`, and an unknown `${VAR}`, a variable in the wrong config, a missing source, a config without source or a trailing blank line stop the build with the compose file untouched. In a throwaway git repository, the pre-commit check must refuse a source staged without its regenerated compose file, and accept it once both are staged. It needs Python 3, Docker Compose 2.23 or later and git.

[`tests/test_stack.sh`](./tests/test_stack.sh) renders the compose file with `.env.example` and checks the exposure without starting anything: forward auth first on the three UI routers, the ingestion and health routers limited to their method, path, middleware and service, forward auth on every other router of the three hosts, no published port except the UDP syslog port, the Grafana auth proxy settings (no login form, Basic auth, anonymous access or `GF_AUTH_DISABLE_LOGIN`), vmalert on the internal `victoria` network only, Alertmanager on `victoria` and alone on the non-internal `alertmanager` network with the host CA bundle read-only, the `ALERTMANAGER_WATCHDOG_URL` placeholder in `.env.example`, the self-scrape jobs of the six components and the Vector metrics sink on port `9598` (a wrong target makes the check fail), unpoller without route or port, as `65534:65534`, with TLS verification, InfluxDB and DPI off, no password in `.env.example` and alone on the `unpoller` network, the scrape config that targets `unpoller:9130`, snmp-exporter without route or port, as `65534:65534`, alone on the `snmp` network, with SNMPv3 authPriv (SHA, AES), no password in `.env.example` and the `${...}` references that the exporter expands, the `synology` job sent to `snmp-exporter:9116`, the `victoria_grafana_mcp` router (no middleware, `POST`, `GET` and `DELETE` on `/mcp` of the Grafana host only, to port `8000`) and grafana-mcp (`--disable-write`, `--allowed-hosts` set to the Grafana host, no `--allowed-origins`, the token length check, no port, empty tokens in `.env.example`), the `victoria-ingest-auth` middleware in `management/traefik_dynamic.toml.example`, the retention defaults (`30d` for logs, `1y` for metrics), the memory limits, healthchecks and `depends_on` conditions of [Memory Limits and Health Checks](#memory-limits-and-health-checks), the drop of `vector_*_bucket` in the `vector` scrape job with no rule or dashboard that reads those buckets, and the SMS webhook auth: `VECTOR_WEBHOOK_PASSWORD` empty in `.env.example`, a render that fails without it, and the same Basic auth on the `sms` receiver and on the `alertmanager_webhook` source. It needs Docker Compose 2.23 or later, `jq` and Python 3.11 or later with PyYAML.

[`tests/test_vector.sh`](./tests/test_vector.sh) renders the compose file with `.env.example`, runs `vector validate` on the pipeline, then the Vector unit tests of [`otlp_test.yaml`](./tests/otlp_test.yaml) (normalization, routing, secret masking, HAProxy), [`authentik_test.yaml`](./tests/authentik_test.yaml), [`proxmox_test.yaml`](./tests/proxmox_test.yaml), [`syslog_test.yaml`](./tests/syslog_test.yaml) (syslog, CEF, firewall, Synology byte order mark), [`level_test.yaml`](./tests/level_test.yaml) (the common `level` of every source), [`alert_rules_test.yaml`](./tests/alert_rules_test.yaml) (the alert state records: reason of a firing, inactive and failing rule, empty answer) and [`sms_test.yaml`](./tests/sms_test.yaml) (SMS text, truncation, missing credentials). It needs Docker, Docker Compose 2.23 or later and `jq`, and makes no network call.

[`tests/test_ingest.sh`](./tests/test_ingest.sh) starts VictoriaLogs and Vector on a throwaway internal network, sends one OTLP/HTTP protobuf record to Vector with a `stream-name` header, then queries VictoriaLogs. It checks what the unit tests cannot: the OTLP source, the sink query string (`_stream_fields`, `_msg_field`, `_time_field`), the stored fields and stream, and the masking of a URL secret. It also expects the answer within 3.5 seconds, which fails if the batch timeout goes back to 5 seconds. It needs Docker, Docker Compose 2.23 or later, `jq` and Python 3, uses the local images (`CLIENT_IMAGE` overrides the busybox client, `busybox:1.37` by default), and takes about 20 seconds. The Vector OTLP/HTTP source only accepts protobuf: an OTLP JSON request gets an HTTP 500.

[`tests/test_alerting.sh`](./tests/test_alerting.sh) first checks the rules and the routing without starting anything: `vmalert -dryRun` on both rule sets, `amtool check-config`, one Alertmanager route per alert with a `repeat_interval` at least equal to the lifetime of one event (event window, `keep_firing_for` and group interval), no route without a rule, `inhibit_rules` that only name existing alerts, a receiver that targets the Vector webhook with the Basic auth that the webhook requires, and no SMS on a single failure: `vmalert_rule_errors` needs two failed evaluations, `alertmanager_notifications_failed` a `for` of at least 10 minutes longer than its `increase` window, the watchdog: no `for` or `keep_firing_for`, its route first with a `repeat_interval` of at most 5 minutes, a `watchdog` receiver with one `/api/push/` webhook and no resolved notification, every other route on `sms` without `continue`. `vmalert-tool unittest` then replays the series of [`metrics_rules_unittest.yaml`](./tests/metrics_rules_unittest.yaml) through the rendered metric rules, at their production intervals: each case checks that an alert fires with its exact labels and annotations, and that the nearby quiet case does not (a host silent for 8 minutes, a SMART count that was already high, a single burst of send errors, one failed evaluation, a stopped guest, unpoller up with devices). It also checks the `host_name:metrics_age_seconds:max` record that the dashboards read: one series per host, at the age of its oldest CPU, so a CPU that stops reporting still shows. It then starts VictoriaLogs, VictoriaMetrics, vmalert-logs, Alertmanager and Vector on a throwaway internal network, with 5 second rule intervals and the `free_mobile` sink pointed at VictoriaLogs. The SMS webhook must answer `401` without a password and with a wrong one. It inserts the records with the `_msg_field` of the Vector sink, as in production, and sends a failed vzdump, a failed `acmerenew` task, a failed `qmstart` task, a journald `Failed with result` message from systemd, a kernel hung task and OOM kill, 5 containerd starts for each of three containers (one with Docker logs, one without, one GitLab runner helper) and three 5 minute buckets of Traefik 502. It expects the SMS lines of `proxmox_backup_failed`, of `proxmox_task_failed` for both tasks (VM and status included), of `systemd_unit_failed`, `kernel_critical`, `oom_kill`, `traefik_5xx_burst` and of `container_restart_loop` for the first two containers only (name, then short id), with an Alertmanager `group_interval` of 5 seconds so that a task alert that joins its group late still arrives in time. It then starts vmalert-metrics with the self-scrape jobs at 5 seconds and the watchdog URL pointed at VictoriaLogs: the six jobs must be up, the series that the `victoria_stack` rules read (`alertmanager_notifications_failed_total` with `receiver_name`, `vmalert_alerting_rules_errors_total`, `vector_component_sent_events_total`, `vmalert_alerts_send_errors_total` of both vmalert instances) must exist, watchdog pushes must arrive as `firing`, the `alerts` stream must hold one record per rule, with `proxmox_backup_failed` firing from the logs with its summary as message and a start time, the watchdog firing from the metrics, and an inactive rule with its condition, and once Vector is stopped the watchdog must leave Alertmanager with no resolved push. It does not cover Uptime Kuma, the `free_mobile` error branch end to end, the inhibitions at runtime, the log rules in the unit tests, the Proxmox parsing (see `proxmox_test.yaml`), the metric rules on real data or the Free Mobile API. It needs Docker, Docker Compose 2.23 or later, `jq` and Python 3 with PyYAML, makes no Internet call, and waits at most `ALERTING_TIMEOUT` seconds (120 by default).

[`tests/test_unpoller.sh`](./tests/test_unpoller.sh) starts VictoriaMetrics with its rendered command and scrape config on a throwaway internal network, next to a busybox HTTP server that answers as `unpoller` on port 9130 with a fixed metric. It expects `up{job="unpoller",instance="unpoller:9130"}` at `1` and the fixed value in VictoriaMetrics, which proves that VictoriaMetrics accepts the scrape config and that the job, host and port match. It checks that the rendered interval is 60 seconds and lowers it to 5 seconds in its copy only. It then starts vmalert with the rendered command and metric rules, the `unifi_metrics` group lowered from 1 minute to 5 seconds in its copy. While the server answers with `unpoller_device_info`, `unpoller_no_unifi_data` must stay inactive for 3 evaluations, with a `for` of 10 minutes. Once the server answers with Go metrics only, the alert must turn pending with `job="unpoller"` and severity `warning`, while `up` stays at `1`. Alertmanager is not started. It does not cover unpoller itself or the UniFi API; use the post-deployment check of [UniFi Metrics](#unifi-metrics-unpoller). It needs Docker, Docker Compose 2.23 or later and `jq`, makes no Internet call, and waits at most `UNPOLLER_TIMEOUT` seconds (60 by default).

[`tests/test_synology.sh`](./tests/test_synology.sh) checks the SNMP path in two parts, on a throwaway internal network. It first runs the real snmp-exporter image with its rendered command and auth file and test values in its environment: `/config` must show the test user name and no test password, a probe with a wrong module or auth name must get `400`, and a probe with the modules and auth of the `synology` job must get `500` (names known, NAS unreachable). It then runs VictoriaMetrics with its rendered scrape config next to a busybox server that answers as `snmp-exporter:9116` with a fixed metric, and expects `up{job="synology"}` at `1` with the NAS as `instance`, the fixed value stored, and a request to `/snmp` with the NAS as target, the three modules and the `synology_v3` auth. It lowers the interval and timeout to 5 seconds in its copy only. It does not cover SNMPv3 against the NAS; use the post-deployment check of [Synology Metrics](#synology-metrics-snmp-exporter). It needs Docker, Docker Compose 2.23 or later and `jq`, makes no Internet call, and waits at most `SYNOLOGY_TIMEOUT` seconds (60 by default).

[`tests/test_dashboards.sh`](./tests/test_dashboards.sh) starts VictoriaLogs, VictoriaMetrics and Grafana with sample data. It checks that the Grafana API answers `401` without the `X-authentik-username` header, refuses Basic auth and the `admin/admin` login form, and gives a new user the Viewer role and the sixteen dashboards, each in its expected folder. The sample data covers every log stream the dashboards read (Authentik, Proxmox, Docker, AdGuard queries, UniFi drops and CEF events, Traefik access logs, alert rule states dated at ingestion), a set of OpenTelemetry host metrics and the `smartctl_exporter` series of two test disks. Before any query, it checks static rules of the dashboards: every `rate()` of a time series uses `$__rate_interval`, the datasource `timeInterval` is at least the longest scrape interval, no LogsQL query filters `log_stream` outside a stream filter, every recording rule a dashboard reads is defined in the `vmalert-metrics` rules, and every VictoriaMetrics stat without a sparkline uses an instant query. The test does not run vmalert: it imports the `host_name:metrics_age_seconds:max` series as vmalert would write it, and the rule itself is unit tested by `tests/test_alerting.sh`. Every query of the sixteen dashboards then goes through the Grafana datasource API twice, once with each template variable set to a test value and once set to *All*, using the `allValue` that the dashboard declares. Each VictoriaLogs query, each query of the hosts dashboard and each query of the four host SMART panels of the disks dashboard must return data, and a numeric result made only of zeros counts as none, except *Hôtes silencieux*, which must return none while the test host reports and count exactly one silent host for *All*; the silent hosts stat and the hosts table of *Services rendus* must return data too, the stat exactly one. The other VictoriaMetrics queries must answer `200`, and each dashboard must have at least one query. In the *État des règles* table of the *Alertes* dashboard, the firing watchdog must read `veille` and a firing rule `firing`. The *Requêtes*, *Taux de 4xx* and *Taux de 5xx* stats of the HTTP dashboard, and the *Requêtes HTTP*, *Taux de 5xx* and *Latence HTTP p95* stats of the *Services rendus* dashboard, must return their exact values, with the status written as a number and as a string, and one line without a host and four `502` of the ingestion routers that they must ignore. The sample also holds WebSocket sessions (status `0`) and SSE requests lasting ten minutes to an hour: *Latence p95* must return the slowest short request, and no number returned by the HTTP or *Services rendus* dashboard, table cells included, may reach a stream's duration. With sample UnPoller series, the five IP tables must be Mixed panels whose UnPoller query is an instant table joined on the IP field of the logs query, with the rows without a count dropped and the *nom UniFi* and *MAC* columns renamed. The UnPoller query must return one MAC and name per IP, and the MAC seen last for an IP that two devices held. It also checks the version of the loaded plugin. The plugin is read from `GRAFANA_PLUGIN_DIR` (a `plugins` directory that holds `victoriametrics-logs-datasource`, for example the one of a Grafana that ran this stack) and the test makes no Internet call. It does not cover the browser rendering (the IP join runs there, so the test checks its definition only), the Authentik outpost, the other UniFi and Synology metrics (their queries only need to answer `200`), or the real Proxmox metric names, which [`tests/check_metric_names.sh`](./tests/check_metric_names.sh) checks against a running VictoriaMetrics (see [Post-Deployment Check of the Metric Names](#post-deployment-check-of-the-metric-names)).

[`tests/test_grafana_mcp.sh`](./tests/test_grafana_mcp.sh) runs the real mcp-grafana image with its rendered entrypoint, command and environment on a throwaway internal network, with test tokens. With an empty server token, a 31 character one or an empty service account token, the container must keep running, log why and leave port `8000` closed. With valid tokens, `POST /mcp` must get `401` without a bearer token or with a wrong one, `200` on `initialize` with the right one, `403` with another `Host` or with an `Origin` header, and `tools/list` must hold the read tools and none of the write tools. It does not cover Grafana itself (no tool is called), the Traefik router (see `test_stack.sh`) or the service account permissions. It needs Docker, Docker Compose 2.23 or later and `jq`, uses `python:3.14-alpine` as client (`CLIENT_IMAGE` overrides it), makes no Internet call, and takes about 20 seconds.

```bash
./tests/test_build.sh
./tests/test_stack.sh
./tests/test_grafana_mcp.sh
./tests/test_vector.sh
./tests/test_ingest.sh
./tests/test_alerting.sh
GRAFANA_PLUGIN_DIR=/path/to/plugins ./tests/test_dashboards.sh
./tests/test_unpoller.sh
./tests/test_synology.sh
```
