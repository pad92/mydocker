# Overleaf Stack

This stack deploys the following services:

## 1. Overleaf (`sharelatex`)

### Role
Collaborative browser-based LaTeX compiler and doc editor.

### External Links
- **Official Project**: [https://www.overleaf.com/](https://www.overleaf.com/)
- **Docker Image Maintainer**: [Overleaf Team](https://hub.docker.com/r/sharelatex/sharelatex)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `DOCKER_RUNNER` | Configuration settings value for Docker runner. | *None (empty)* |
| `EMAIL_CONFIRMATION_DISABLED` | Configuration settings value for Email confirmation disabled. | *None (empty)* |
| `ENABLED_LINKED_FILE_TYPES` | Configuration settings value for Enabled linked file types. | *None (empty)* |
| `ENABLE_CONVERSIONS` | Configuration settings value for Enable conversions. | *None (empty)* |
| `OVERLEAF_APP_NAME` | Configuration settings value for Overleaf app name. | *None (empty)* |
| `OVERLEAF_DOMAIN` | Traefik Host rule domain routing address (e.g., service.home.lan). | *None (empty)* |
| `OVERLEAF_MONGO_URL` | Configuration settings value for Overleaf mongo url. | *None (empty)* |
| `OVERLEAF_REDIS_HOST` | Configuration settings value for Overleaf redis host. | *None (empty)* |
| `OVERLEAF_SHARELATEX_DATA_DIR` | Persistent host directory path for volume mount: OVERLEAF_SHARELATEX_DATA_DIR. | *None (empty)* |
| `REDIS_HOST` | Configuration settings value for Redis host. | *None (empty)* |
| `SANDBOXED_COMPILES` | Configuration settings value for Sandboxed compiles. | *None (empty)* |
| `SANDBOXED_COMPILES_HOST_DIR_COMPILES` | Configuration settings value for Sandboxed compiles host dir compiles. | *None (empty)* |
| `SANDBOXED_COMPILES_HOST_DIR_OUTPUT` | Configuration settings value for Sandboxed compiles host dir output. | *None (empty)* |
| `SANDBOXED_COMPILES_SIBLING_CONTAINERS` | Configuration settings value for Sandboxed compiles sibling containers. | *None (empty)* |

---

## 2. MongoDB Database (`mongo`)

### Role
NoSQL document database storage server.

### External Links
- **Official Project**: [https://www.mongodb.com/](https://www.mongodb.com/)
- **Docker Image Maintainer**: [Docker Official](https://hub.docker.com/_/mongo)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `MONGO_INITDB_DATABASE` | Configuration settings value for Mongo initdb database. | *None (empty)* |
| `OVERLEAF_MONGO_DATA_DIR` | Persistent host directory path for volume mount: OVERLEAF_MONGO_DATA_DIR. | *None (empty)* |

---

## 3. MongoDB Database (`mongo-init`)

### Role
NoSQL document database storage server.

### External Links
- **Official Project**: [https://www.mongodb.com/](https://www.mongodb.com/)
- **Docker Image Maintainer**: [Docker Official](https://hub.docker.com/_/mongo)

---

## 4. Redis Cache (`redis`)

### Role
High speed in-memory caching and key-value database storage service.

### External Links
- **Official Project**: [https://redis.io/](https://redis.io/)
- **Docker Image Maintainer**: [Docker Official](https://hub.docker.com/_/redis)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `OVERLEAF_DATA_DIR` | Persistent host directory path for volume mount: OVERLEAF_DATA_DIR. | *None (empty)* |

---

