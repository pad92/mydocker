# Immich Stack

This stack deploys the following services:

## Common Configuration Variables
These environment variables are shared and used by multiple services in this stack:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `DB_DATABASE_NAME` | Configuration settings value for Db database name. | *None (empty)* |
| `DB_PASSWORD` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `DB_USERNAME` | Configuration settings value for Db username. | *None (empty)* |
| `IMMICH_VERSION` | Configuration settings value for Immich version. | `release` |
| `PUBLIC_BASE_URL` | Configuration settings value for Public base url. | *None (empty)* |

---

## 1. Immich-server (`immich-server`)

### Role
Service container running ghcr.io/immich-app/immich-server:${IMMICH_VERSION.

### External Links
- **Official Project**: [https://hub.docker.com/r/ghcr.io/immich-app/immich-server:${IMMICH_VERSION](https://hub.docker.com/r/ghcr.io/immich-app/immich-server:${IMMICH_VERSION)
- **Docker Image Maintainer**: [Official Hub Registry](ghcr.io/immich-app/immich-server:${IMMICH_VERSION)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `TRAEFIK_HOST_LOCAL` | Internal domain routing host rule (e.g. local.home.lan). | *None (empty)* |
| `UPLOAD_LOCATION` | Configuration settings value for Upload location. | *None (empty)* |

---

## 2. Immich-public-proxy (`immich-public-proxy`)

### Role
Service container running alangrainger/immich-public-proxy.

### External Links
- **Official Project**: [https://hub.docker.com/r/alangrainger/immich-public-proxy](https://hub.docker.com/r/alangrainger/immich-public-proxy)
- **Docker Image Maintainer**: [Official Hub Registry](alangrainger/immich-public-proxy)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `IMMICH_URL` | Configuration settings value for Immich url. | *None (empty)* |
| `TRAEFIK_HOST_PUBLIC` | External domain routing host rule (e.g. pub.domain.com). | *None (empty)* |

---

## 3. Immich-machine-learning (`immich-machine-learning`)

### Role
Service container running ghcr.io/immich-app/immich-machine-learning:${IMMICH_VERSION.

### External Links
- **Official Project**: [https://hub.docker.com/r/ghcr.io/immich-app/immich-machine-learning:${IMMICH_VERSION](https://hub.docker.com/r/ghcr.io/immich-app/immich-machine-learning:${IMMICH_VERSION)
- **Docker Image Maintainer**: [Official Hub Registry](ghcr.io/immich-app/immich-machine-learning:${IMMICH_VERSION)

---

## 4. Redis (`redis`)

### Role
Service container running docker.io/valkey/valkey:9.

### External Links
- **Official Project**: [https://hub.docker.com/r/docker.io/valkey/valkey:9](https://hub.docker.com/r/docker.io/valkey/valkey:9)
- **Docker Image Maintainer**: [Official Hub Registry](docker.io/valkey/valkey:9)

---

## 5. Database (`database`)

### Role
Service container running ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0.

### External Links
- **Official Project**: [https://hub.docker.com/r/ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0](https://hub.docker.com/r/ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0)
- **Docker Image Maintainer**: [Official Hub Registry](ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `DB_DATA_LOCATION` | Configuration settings value for Db data location. | *None (empty)* |
| `DB_STORAGE_TYPE` | Configuration settings value for Db storage type. | *None (empty)* |
| `POSTGRES_INITDB_ARGS` | Configuration settings value for Postgres initdb args. | *None (empty)* |

---

