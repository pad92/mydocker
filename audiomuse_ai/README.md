# Audiomuse_ai Stack

This stack deploys the following services:

## Common Configuration Variables
These environment variables are shared and used by multiple services in this stack:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `AI_MODEL_PROVIDER` | Configuration settings value for Ai model provider. | *None (empty)* |
| `CLAP_ENABLED` | Configuration settings value for Clap enabled. | `true` |
| `GEMINI_API_KEY` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `MEDIASERVER_TYPE` | Configuration settings value for Mediaserver type. | *None (empty)* |
| `MISTRAL_API_KEY` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `OPENAI_API_KEY` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `OPENAI_MODEL_NAME` | Configuration settings value for Openai model name. | *None (empty)* |
| `OPENAI_SERVER_URL` | Configuration settings value for Openai server url. | *None (empty)* |
| `POSTGRES_DB` | Name of the PostgreSQL database schemas. | `audiomusedb` |
| `POSTGRES_HOST` | Network hostname or address of the PostgreSQL server. | *None (empty)* |
| `POSTGRES_PASSWORD` | Database administrator password for PostgreSQL. | `CHANGEME` |
| `POSTGRES_PORT` | Port number of the PostgreSQL server. | `5432` |
| `POSTGRES_USER` | Database administrator username for PostgreSQL. | `audiomuse` |
| `REDIS_URL` | Caching and job queue Redis connection URL. | `redis://redis:6379/0` |
| `SERVICE_TYPE` | Configuration settings value for Service type. | *None (empty)* |
| `TEMP_DIR` | Persistent host directory path for volume mount: TEMP_DIR. | *None (empty)* |
| `TZ` | Timezone configuration for container operations and logs (e.g. Europe/Paris). | `UTC` |

---

## 1. Redis Cache (`redis`)

### Role
High speed in-memory caching and key-value database storage service.

### External Links
- **Official Project**: [https://redis.io/](https://redis.io/)
- **Docker Image Maintainer**: [Docker Official](https://hub.docker.com/_/redis)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `AUDIOMUSE_AI_AUDIOMUSE_DATA_DIR` | Persistent host directory path for volume mount: AUDIOMUSE_AI_AUDIOMUSE_DATA_DIR. | *None (empty)* |
| `REDIS_PORT` | Configuration settings value for Redis port. | `6379` |

---

## 2. PostgreSQL Database (`postgres`)

### Role
Powerful, open-source object-relational SQL database storage server.

### External Links
- **Official Project**: [https://www.postgresql.org/](https://www.postgresql.org/)
- **Docker Image Maintainer**: [Docker Official](https://hub.docker.com/_/postgres)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `AUDIOMUSE_AI_AUDIOMUSE_POSTGRESQL_DATA_DIR` | Persistent host directory path for volume mount: AUDIOMUSE_AI_AUDIOMUSE_POSTGRESQL_DATA_DIR. | *None (empty)* |

---

## 3. Audiomuse-ai-flask (`audiomuse-ai-flask`)

### Role
Service container running ghcr.io/neptunehub/audiomuse-ai.

### External Links
- **Official Project**: [https://hub.docker.com/r/ghcr.io/neptunehub/audiomuse-ai](https://hub.docker.com/r/ghcr.io/neptunehub/audiomuse-ai)
- **Docker Image Maintainer**: [Official Hub Registry](https://hub.docker.com/r/ghcr.io/neptunehub/audiomuse-ai)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `AUDIOMUSE_AI_DOMAIN` | Traefik Host rule domain routing address (e.g., service.home.lan). | *None (empty)* |
| `FRONTEND_PORT` | Configuration settings value for Frontend port. | `8000` |
| `JELLYFIN_TOKEN` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `JELLYFIN_URL` | Configuration settings value for Jellyfin url. | *None (empty)* |
| `JELLYFIN_USER_ID` | Configuration settings value for Jellyfin user id. | *None (empty)* |

---

## 4. Audiomuse-ai-worker (`audiomuse-ai-worker`)

### Role
Service container running ghcr.io/neptunehub/audiomuse-ai.

### External Links
- **Official Project**: [https://hub.docker.com/r/ghcr.io/neptunehub/audiomuse-ai](https://hub.docker.com/r/ghcr.io/neptunehub/audiomuse-ai)
- **Docker Image Maintainer**: [Official Hub Registry](https://hub.docker.com/r/ghcr.io/neptunehub/audiomuse-ai)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `AUDIOMUSE_PASSWORD` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `AUDIOMUSE_URL` | Configuration settings value for Audiomuse url. | *None (empty)* |
| `AUDIOMUSE_USER` | Configuration settings value for Audiomuse user. | *None (empty)* |
| `NVIDIA_DRIVER_CAPABILITIES` | Configuration settings value for Nvidia driver capabilities. | *None (empty)* |
| `NVIDIA_VISIBLE_DEVICES` | Configuration settings value for Nvidia visible devices. | *None (empty)* |
| `USE_GPU_CLUSTERING` | Configuration settings value for Use gpu clustering. | `true` |

---

## Global / Other Variables
The following variables are defined in `.env.example` but are either global configs or not directly referenced in the compose services:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `API_TOKEN` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `EMBY_TOKEN` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `EMBY_URL` | Configuration settings value for Emby url. | *None (empty)* |
| `EMBY_USER_ID` | Configuration settings value for Emby user id. | *None (empty)* |
| `JWT_SECRET` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `LYRION_URL` | Configuration settings value for Lyrion url. | *None (empty)* |
| `NAVIDROME_PASSWORD` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `NAVIDROME_URL` | Configuration settings value for Navidrome url. | *None (empty)* |
| `NAVIDROME_USER` | Configuration settings value for Navidrome user. | *None (empty)* |
| `OPENAI_API_CALL_DELAY_SECONDS` | Configuration settings value for Openai api call delay seconds. | *None (empty)* |
| `WORKER_PORT` | Configuration settings value for Worker port. | *None (empty)* |

