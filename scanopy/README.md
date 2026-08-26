# Scanopy Stack

This stack deploys the following services:

## Common Configuration Variables
These environment variables are shared and used by multiple services in this stack:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `SCANOPY_DAEMON_PORT` | Configuration settings value for Scanopy daemon port. | `60073` |
| `SCANOPY_DATA_DIR` | Persistent host directory path for volume mount: SCANOPY_DATA_DIR. | *None (empty)* |
| `SCANOPY_LOG_LEVEL` | Configuration settings value for Scanopy log level. | `info` |
| `SCANOPY_SERVER_PORT` | Configuration settings value for Scanopy server port. | `60072` |

---

## 1. Daemon (`daemon`)

### Role
Service container running ghcr.io/scanopy/scanopy/daemon.

### External Links
- **Official Project**: [https://hub.docker.com/r/ghcr.io/scanopy/scanopy/daemon](https://hub.docker.com/r/ghcr.io/scanopy/scanopy/daemon)
- **Docker Image Maintainer**: [Official Hub Registry](https://hub.docker.com/r/ghcr.io/scanopy/scanopy/daemon)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `SCANOPY_BIND_ADDRESS` | Configuration settings value for Scanopy bind address. | `0.0.0.0` |
| `SCANOPY_DAEMON_DATA_DIR` | Persistent host directory path for volume mount: SCANOPY_DAEMON_DATA_DIR. | *None (empty)* |
| `SCANOPY_HEARTBEAT_INTERVAL` | Configuration settings value for Scanopy heartbeat interval. | `30` |
| `SCANOPY_MODE` | Configuration settings value for Scanopy mode. | `Push` |
| `SCANOPY_NAME` | Configuration settings value for Scanopy name. | `scanopy-daemon` |
| `SCANOPY_SERVER_URL` | Configuration settings value for Scanopy server url. | `http://127.0.0.1:60072` |

---

## 2. PostgreSQL Database (`postgres`)

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

## 3. Server (`server`)

### Role
Service container running ghcr.io/scanopy/scanopy/server.

### External Links
- **Official Project**: [https://hub.docker.com/r/ghcr.io/scanopy/scanopy/server](https://hub.docker.com/r/ghcr.io/scanopy/scanopy/server)
- **Docker Image Maintainer**: [Official Hub Registry](https://hub.docker.com/r/ghcr.io/scanopy/scanopy/server)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `SCANOPY_DATABASE_URL` | Configuration settings value for Scanopy database url. | *None (empty)* |
| `SCANOPY_INTEGRATED_DAEMON_URL` | Configuration settings value for Scanopy integrated daemon url. | *None (empty)* |
| `SCANOPY_PUBLIC_URL` | Configuration settings value for Scanopy public url. | `http://localhost:${SCANOPY_SERVER_PORT:-60072` |
| `SCANOPY_WEB_EXTERNAL_PATH` | Persistent host directory path for volume mount: SCANOPY_WEB_EXTERNAL_PATH. | *None (empty)* |

---

## Global / Other Variables
The following variables are defined in `.env.example` but are either global configs or not directly referenced in the compose services:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `SCANOPY_IP_1` | Network IP address configuration. | *None (empty)* |
| `SCANOPY_IP_2` | Network IP address configuration. | *None (empty)* |

