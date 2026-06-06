# Nextcloud Stack

This stack deploys the following services:

## 1. Nextcloud (`nextcloud`)

### Role
Service container running lscr.io/linuxserver/nextcloud.

### External Links
- **Official Project**: [https://hub.docker.com/r/lscr.io/linuxserver/nextcloud](https://hub.docker.com/r/lscr.io/linuxserver/nextcloud)
- **Docker Image Maintainer**: [Official Hub Registry](https://hub.docker.com/r/lscr.io/linuxserver/nextcloud)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `DOCKER_MODS` | Configuration settings value for Docker mods. | *None (empty)* |
| `NEXTCLOUD_ALLOW_INSECURE` | Configuration settings value for Nextcloud allow insecure. | *None (empty)* |
| `NEXTCLOUD_DATA_DIR` | Persistent host directory path for volume mount: NEXTCLOUD_DATA_DIR. | *None (empty)* |
| `NEXTCLOUD_DOMAIN` | Traefik Host rule domain routing address (e.g., service.home.lan). | *None (empty)* |
| `PGID` | Group ID matching host permissions to run the container. | *None (empty)* |
| `PUID` | User ID matching host permissions to run the container. | *None (empty)* |
| `TZ` | Timezone configuration for container operations and logs (e.g. Europe/Paris). | *None (empty)* |

---

## Global / Other Variables
The following variables are defined in `.env.example` but are either global configs or not directly referenced in the compose services:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `MYSQL_DATABASE` | Name of the MySQL/MariaDB database schemas. | *None (empty)* |
| `MYSQL_HOST` | Configuration settings value for Mysql host. | *None (empty)* |
| `MYSQL_PASSWORD` | Database user password for MySQL/MariaDB. | `CHANGEME` |
| `MYSQL_ROOT_PASSWORD` | Root administrator password for MySQL/MariaDB. | `CHANGEME` |
| `MYSQL_USER` | Database user name for MySQL/MariaDB. | *None (empty)* |
| `NEXTCLOUD_IP` | Network IP address configuration. | *None (empty)* |
| `REDIS_HOST` | Configuration settings value for Redis host. | *None (empty)* |

