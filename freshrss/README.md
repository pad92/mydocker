# Freshrss Stack

This stack deploys the following services:

## 1. Freshrss (`freshrss`)

### Role
Service container running lscr.io/linuxserver/freshrss.

### External Links
- **Official Project**: [https://hub.docker.com/r/lscr.io/linuxserver/freshrss](https://hub.docker.com/r/lscr.io/linuxserver/freshrss)
- **Docker Image Maintainer**: [Official Hub Registry](lscr.io/linuxserver/freshrss)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `FRESHRSS_DATA_DIR` | Persistent host directory path for volume mount: FRESHRSS_DATA_DIR. | *None (empty)* |
| `FRESHRSS_DOMAIN` | Traefik Host rule domain routing address (e.g., service.home.lan). | *None (empty)* |
| `PGID` | Group ID matching host permissions to run the container. | *None (empty)* |
| `PUID` | User ID matching host permissions to run the container. | *None (empty)* |
| `TZ` | Timezone configuration for container operations and logs (e.g. Europe/Paris). | *None (empty)* |

---

