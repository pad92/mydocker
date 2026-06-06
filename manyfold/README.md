# Manyfold Stack

This stack deploys the following services:

## 1. Manyfold (`manyfold`)

### Role
Service container running ghcr.io/manyfold3d/manyfold.

### External Links
- **Official Project**: [https://hub.docker.com/r/ghcr.io/manyfold3d/manyfold](https://hub.docker.com/r/ghcr.io/manyfold3d/manyfold)
- **Docker Image Maintainer**: [Official Hub Registry](ghcr.io/manyfold3d/manyfold)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `DATABASE_ADAPTER` | Configuration settings value for Database adapter. | *None (empty)* |
| `DATABASE_HOST` | Configuration settings value for Database host. | *None (empty)* |
| `DATABASE_NAME` | Configuration settings value for Database name. | *None (empty)* |
| `DATABASE_PASSWORD` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `DATABASE_PORT` | Configuration settings value for Database port. | *None (empty)* |
| `DATABASE_USER` | Configuration settings value for Database user. | *None (empty)* |
| `MANYFOLD_DOMAIN` | Traefik Host rule domain routing address (e.g., service.home.lan). | *None (empty)* |
| `MANYFOLD_MODELS_DATA_DIR` | Persistent host directory path for volume mount: MANYFOLD_MODELS_DATA_DIR. | *None (empty)* |
| `PGID` | Group ID matching host permissions to run the container. | *None (empty)* |
| `PUID` | User ID matching host permissions to run the container. | *None (empty)* |
| `REDIS_URL` | Caching and job queue Redis connection URL. | *None (empty)* |
| `SECRET_KEY_BASE` | Secret authentication credentials, token, or key value. | `CHANGEME` |

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
| `MANYFOLD_DATA_DIR` | Persistent host directory path for volume mount: MANYFOLD_DATA_DIR. | *None (empty)* |
| `POSTGRES_PASSWORD` | Database administrator password for PostgreSQL. | `CHANGEME` |
| `POSTGRES_USER` | Database administrator username for PostgreSQL. | *None (empty)* |

---

## 3. Redis Cache (`redis`)

### Role
High speed in-memory caching and key-value database storage service.

### External Links
- **Official Project**: [https://redis.io/](https://redis.io/)
- **Docker Image Maintainer**: [Docker Official](https://hub.docker.com/_/redis)

---

