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
| `LIBRESPEED_NEW_DESIGN` | `true` shows the modern design by default, `false` the classic one. Only `true` or `false`: the value is written as-is into a JSON file. | `true` |
| `PGID` | Group ID matching host permissions to run the container. Required. | *None (empty)* |
| `PUID` | User ID matching host permissions to run the container. Required. | *None (empty)* |
| `TZ` | Timezone of the container and its logs. | `Etc/UTC` |

### Classic or Modern Design

The LinuxServer image has no environment variable for the design. The upstream `USE_NEW_DESIGN` variable only exists in the `ghcr.io/librespeed/speedtest` image. This one reads `useNewDesign` from `/config/www/config.json`.

The compose file sets it from `LIBRESPEED_NEW_DESIGN` through the inline `design_config` entry under `configs:`. Compose writes this file into the container each time it creates it, over the copy in `${LIBRESPEED_DATA_DIR}/www/config.json`, so edit the variable rather than the file. Inline `configs` need Docker Compose 2.23 or later.

A visitor can still force a design with `?design=new` or `?design=classic`.

The switch only works if `index.html` loads `design-switch.js`. The image copies `index.html` into `${LIBRESPEED_DATA_DIR}/www/` only when it is missing, so a data directory created by an older image keeps a classic page that ignores `useNewDesign`. The `migrate_index` script under `configs:`, run by the image from `/custom-cont-init.d`, handles this on start: it moves such a page to `index.html.old` and installs the current switcher. A page that already loads `design-switch.js` is left alone, so customise that one rather than the old page.

### Client IP Detection

The backend reads the client IP from `Client-IP`, then `X-Real-Ip`, then `X-Forwarded-For`. Traefik sets the last two itself, but forwards `Client-IP` as sent by the client. The `librespeed-drop-client-ip` middleware removes it, so the IP shown and stored is the one Traefik saw.

### Tests

`tests/test_stack.sh` renders the compose file with `.env.example` and checks the HTTPS routing, the required password, `no-new-privileges` and the `config.json` content. It then starts the stack with `docker compose` on a throwaway network, over a data directory that already holds a classic `config.json` and `index.html`. It checks that the old page is replaced once by the switcher and kept as `index.html.old`, that the modern design is served and that the stats page refuses an empty password and accepts the configured one. It needs Docker, Docker Compose 2.23+, `jq` and `curl`.

```bash
./tests/test_stack.sh
```

---
