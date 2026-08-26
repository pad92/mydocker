# Netbox Stack

This stack deploys the following services:

## Common Configuration Variables
These environment variables are shared and used by multiple services in this stack:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `NETBOX_DATA_DIR` | Persistent host directory path for volume mount: NETBOX_DATA_DIR. | *None (empty)* |

---

## 1. PostgreSQL Database (`netbox_postgres`)

### Role
Open-source object-relational SQL database storage server.

### External Links
- **Official Project**: [https://www.postgresql.org/](https://www.postgresql.org/)
- **Docker Image Maintainer**: [Docker Official](https://hub.docker.com/_/postgres)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `POSTGRES_DB` | Name of the PostgreSQL database schemas. | *None (empty)* |
| `POSTGRES_PASSWORD` | Database administrator password for PostgreSQL. | `CHANGEME` |
| `POSTGRES_USER` | Database administrator username for PostgreSQL. | *None (empty)* |

---

## 2. Redis Cache (`netbox_redis`)

### Role
High speed in-memory caching and key-value database storage service.

### External Links
- **Official Project**: [https://redis.io/](https://redis.io/)
- **Docker Image Maintainer**: [Docker Official](https://hub.docker.com/_/redis)

---

## 3. Netbox (`netbox`)

### Role
Service container running lscr.io/linuxserver/netbox.

### External Links
- **Official Project**: [https://hub.docker.com/r/lscr.io/linuxserver/netbox](https://hub.docker.com/r/lscr.io/linuxserver/netbox)
- **Docker Image Maintainer**: [Official Hub Registry](https://hub.docker.com/r/lscr.io/linuxserver/netbox)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `ALLOWED_HOST` | Configuration settings value for Allowed host. | *None (empty)* |
| `DB_HOST` | Configuration settings value for Db host. | *None (empty)* |
| `DB_NAME` | Configuration settings value for Db name. | *None (empty)* |
| `DB_PASSWORD` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `DB_PORT` | Configuration settings value for Db port. | *None (empty)* |
| `DB_USER` | Configuration settings value for Db user. | *None (empty)* |
| `DOCKER_MODS` | Configuration settings value for Docker mods. | *None (empty)* |
| `INSTALL_PIP_PACKAGES` | Configuration settings value for Install pip packages. | *None (empty)* |
| `NETBOX_DOMAIN` | Traefik Host rule domain routing address (e.g., service.home.lan). | *None (empty)* |
| `PGID` | Group ID matching host permissions to run the container. | *None (empty)* |
| `PUID` | User ID matching host permissions to run the container. | *None (empty)* |
| `REDIS_DB_CACHE` | Configuration settings value for Redis db cache. | *None (empty)* |
| `REDIS_DB_TASK` | Configuration settings value for Redis db task. | *None (empty)* |
| `REDIS_HOST` | Configuration settings value for Redis host. | *None (empty)* |
| `REDIS_PORT` | Configuration settings value for Redis port. | *None (empty)* |
| `SUPERUSER_EMAIL` | Configuration settings value for Superuser email. | *None (empty)* |
| `SUPERUSER_PASSWORD` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `TZ` | Timezone configuration for container operations and logs (e.g. Europe/Paris). | *None (empty)* |

---

