# Immich Stack

This stack deploys the following services:

## Common Configuration Variables
These environment variables are shared and used by multiple services in this stack:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `PUBLIC_BASE_URL` | Configuration settings value for Public base url. | *None (empty)* |

---

## 1. Immich-server (`immich-server`)

### Role
Service container running ghcr.io/immich-app/immich-server:${IMMICH_VERSION.

### External Links
- **Official Project**: [https://hub.docker.com/r/ghcr.io/immich-app/immich-server:${IMMICH_VERSION](https://hub.docker.com/r/ghcr.io/immich-app/immich-server:${IMMICH_VERSION)
- **Docker Image Maintainer**: [Official Hub Registry](https://hub.docker.com/r/ghcr.io/immich-app/immich-server:${IMMICH_VERSION)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `DB_DATABASE_NAME` | Configuration settings value for Db database name. | *None (empty)* |
| `DB_PASSWORD` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `DB_USERNAME` | Configuration settings value for Db username. | *None (empty)* |
| `IMMICH_VERSION` | Configuration settings value for Immich version. | `release` |
| `TRAEFIK_HOST_LOCAL` | Internal domain routing host rule (e.g. local.home.lan). | *None (empty)* |
| `UPLOAD_LOCATION` | Configuration settings value for Upload location. | *None (empty)* |

---

## 2. Immich-public-proxy (`immich-public-proxy`)

### Role
Service container running alangrainger/immich-public-proxy.

### External Links
- **Official Project**: [https://hub.docker.com/r/alangrainger/immich-public-proxy](https://hub.docker.com/r/alangrainger/immich-public-proxy)
- **Docker Image Maintainer**: [Official Hub Registry](https://hub.docker.com/r/alangrainger/immich-public-proxy)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `IMMICH_URL` | Configuration settings value for Immich url. | *None (empty)* |
| `TRAEFIK_HOST_PUBLIC` | External domain routing host rule (e.g. pub.domain.com). | *None (empty)* |

---

## Global / Other Variables
The following variables are defined in `.env.example` but are either global configs or not directly referenced in the compose services:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `DB_DATA_LOCATION` | Configuration settings value for Db data location. | *None (empty)* |
| `DB_STORAGE_TYPE` | Configuration settings value for Db storage type. | *None (empty)* |
| `NFS_SERVER_IP` | Network IP address configuration. | *None (empty)* |
| `PHOTO_NAS_NATH_PATH` | Persistent host directory path for volume mount: PHOTO_NAS_NATH_PATH. | *None (empty)* |
| `PHOTO_NAS_PASCAL_PATH` | Persistent host directory path for volume mount: PHOTO_NAS_PASCAL_PATH. | *None (empty)* |
| `PHOTO_NAS_PATH` | Persistent host directory path for volume mount: PHOTO_NAS_PATH. | *None (empty)* |
| `POSTGRES_INITDB_ARGS` | Configuration settings value for Postgres initdb args. | *None (empty)* |

