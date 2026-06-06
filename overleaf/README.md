# Overleaf Stack

## Role
Collaborative real-time LaTeX editor (ShareLaTeX).

## External Links
- **Official Project**: [https://www.overleaf.com/](https://www.overleaf.com/)
- **Docker Image Maintainer**: [Overleaf](https://hub.docker.com/r/sharelatex/sharelatex)

## Configuration Variables
Define the following environment variables in your local `.env` file:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `DOCKER_RUNNER` | Configuration settings value for Docker runner. | *None (empty)* |
| `EMAIL_CONFIRMATION_DISABLED` | Configuration settings value for Email confirmation disabled. | *None (empty)* |
| `ENABLED_LINKED_FILE_TYPES` | Configuration settings value for Enabled linked file types. | *None (empty)* |
| `ENABLE_CONVERSIONS` | Configuration settings value for Enable conversions. | *None (empty)* |
| `MONGO_INITDB_DATABASE` | Configuration settings value for Mongo initdb database. | *None (empty)* |
| `OVERLEAF_APP_NAME` | Configuration settings value for Overleaf app name. | *None (empty)* |
| `OVERLEAF_DATA_DIR` | Persistent host directory path for volume mount: OVERLEAF_DATA_DIR. | *None (empty)* |
| `OVERLEAF_DOMAIN` | Traefik Host rule domain routing address (e.g., service.home.lan). | *None (empty)* |
| `OVERLEAF_MONGO_DATA_DIR` | Persistent host directory path for volume mount: OVERLEAF_MONGO_DATA_DIR. | *None (empty)* |
| `OVERLEAF_MONGO_URL` | Configuration settings value for Overleaf mongo url. | *None (empty)* |
| `OVERLEAF_REDIS_HOST` | Configuration settings value for Overleaf redis host. | *None (empty)* |
| `OVERLEAF_SHARELATEX_DATA_DIR` | Persistent host directory path for volume mount: OVERLEAF_SHARELATEX_DATA_DIR. | *None (empty)* |
| `REDIS_HOST` | Configuration settings value for Redis host. | *None (empty)* |
| `SANDBOXED_COMPILES` | Configuration settings value for Sandboxed compiles. | *None (empty)* |
| `SANDBOXED_COMPILES_HOST_DIR_COMPILES` | Configuration settings value for Sandboxed compiles host dir compiles. | *None (empty)* |
| `SANDBOXED_COMPILES_HOST_DIR_OUTPUT` | Configuration settings value for Sandboxed compiles host dir output. | *None (empty)* |
| `SANDBOXED_COMPILES_SIBLING_CONTAINERS` | Configuration settings value for Sandboxed compiles sibling containers. | *None (empty)* |

