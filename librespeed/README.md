# Librespeed Stack

This stack deploys the following services:

## 1. Librespeed (`librespeed`)

### Role
Self-hosted speed test (download, upload, ping, jitter) for the LAN, using the LinuxServer image of LibreSpeed. Test results are stored in a SQLite database under `/config` and can be browsed on `/results/stats.php`.

The web server listens on port `80` and is published through Traefik only, over HTTPS with a `stepca` certificate. Plain HTTP is redirected to HTTPS. No host port is exposed.

### External Links
- **Official Project**: [https://github.com/librespeed/speedtest](https://github.com/librespeed/speedtest) (LGPL-3.0)
- **Docker Image Maintainer**: [LinuxServer.io](https://docs.linuxserver.io/images/docker-librespeed/)
- **Image Source**: [https://github.com/linuxserver/docker-librespeed](https://github.com/linuxserver/docker-librespeed)

### Service-Specific Configuration Variables

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `LIBRESPEED_DOMAIN` | Hostname routed by Traefik. Required. | `speed.home.lan` |
| `LIBRESPEED_DATA_DIR` | Host directory mounted on `/config` (nginx and PHP config, web files, SQLite results). Required. | `/srv/librespeed/config` |
| `LIBRESPEED_STATS_PASSWORD` | Password of `/results/stats.php`, passed to the image as `PASSWORD`. Required: with an empty value the image accepts an empty password and the results, client IPs included, are open to anyone. Letters and digits only, because the image writes it into a `sed` command without escaping. Generate one with `openssl rand -hex 24`. | `CHANGEME` |
| `CUSTOM_RESULTS` | `true` moves the results page to `/config/www/results/index.php` so it can be edited. | `false` |
| `DB_TYPE` | Results database: `sqlite`, `mysql` or `postgresql`. The other two also need `DB_HOSTNAME`, `DB_NAME`, `DB_USERNAME`, `DB_PASSWORD` (and `DB_PORT` for MySQL), which this compose file does not pass. | `sqlite` |
| `PGID` | Group ID matching host permissions to run the container. Required. | *None (empty)* |
| `PUID` | User ID matching host permissions to run the container. Required. | *None (empty)* |
| `TZ` | Timezone of the container and its logs. | `Etc/UTC` |

### Classic or Modern Design

The LinuxServer image has no environment variable for the design. The upstream `USE_NEW_DESIGN` variable only exists in the `ghcr.io/librespeed/speedtest` image. Here the default comes from `useNewDesign` in `${LIBRESPEED_DATA_DIR}/www/config.json`, created with `false` on first start:

```json
{
  "useNewDesign": true
}
```

A visitor can still force a design with `?design=new` or `?design=classic`.

### Client IP Detection

The backend reads the client IP from `Client-IP`, then `X-Real-Ip`, then `X-Forwarded-For`. Traefik sets the last two itself, but forwards `Client-IP` as sent by the client. The `librespeed-drop-client-ip` middleware removes it, so the IP shown and stored is the one Traefik saw.

### Tests

`tests/test_stats_password.sh` renders the compose file with `.env.example`, checks the HTTPS routing, the required password and `no-new-privileges`, then starts the image on the default Docker bridge and checks that the stats page refuses an empty password and accepts the configured one. It needs Docker, Docker Compose, `jq` and `curl`.

```bash
./tests/test_stats_password.sh
```

---
