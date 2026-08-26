# Gitea Stack

This stack deploys the following services:

## Common Configuration Variables
These environment variables are shared and used by multiple services in this stack:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `GITEA_DATA_DIR` | Persistent host directory path for volume mount: GITEA_DATA_DIR. | *None (empty)* |

---

## 1. Gitea (`gitea`)

### Role
Super fast, lightweight, and painless self-hosted Git developer service.

### External Links
- **Official Project**: [https://gitea.com/](https://gitea.com/)
- **Docker Image Maintainer**: [Gitea Team](https://hub.docker.com/r/gitea/gitea)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `GITEA_DB_PASSWORD` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `GITEA_DOMAIN` | Traefik Host rule domain routing address (e.g., service.home.lan). | *None (empty)* |
| `GITEA__actions__ENABLED` | Configuration settings value for Gitea actions enabled. | *None (empty)* |
| `GITEA__database__DB_TYPE` | Configuration settings value for Gitea database db type. | *None (empty)* |
| `GITEA__database__HOST` | Configuration settings value for Gitea database host. | *None (empty)* |
| `GITEA__database__NAME` | Configuration settings value for Gitea database name. | *None (empty)* |
| `GITEA__database__USER` | Configuration settings value for Gitea database user. | *None (empty)* |
| `GITEA__packages__DOCKER_V2_ENABLED` | Configuration settings value for Gitea packages docker v2 enabled. | *None (empty)* |
| `GITEA__packages__ENABLED` | Configuration settings value for Gitea packages enabled. | *None (empty)* |
| `GITEA__server__ROOT_URL` | Configuration settings value for Gitea server root url. | *None (empty)* |
| `USER_GID` | Configuration settings value for User gid. | *None (empty)* |
| `USER_UID` | Configuration settings value for User uid. | *None (empty)* |

---

## 2. PostgreSQL Database (`db`)

### Role
Open-source, object-relational SQL database used for persistent storage.

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

## 3. Gitea Act Runner (`runner`)

### Role
Runner daemon to execute Gitea Actions workflows locally.

### External Links
- **Official Project**: [https://gitea.com/gitea/act_runner](https://gitea.com/gitea/act_runner)
- **Docker Image Maintainer**: [Gitea Team](https://hub.docker.com/r/gitea/act_runner)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `GITEA_INSTANCE_URL` | Configuration settings value for Gitea instance url. | *None (empty)* |
| `GITEA_RUNNER_DATA_DIR` | Persistent host directory path for volume mount: GITEA_RUNNER_DATA_DIR. | *None (empty)* |
| `GITEA_RUNNER_LABELS` | Configuration settings value for Gitea runner labels. | *None (empty)* |
| `GITEA_RUNNER_NAME` | Configuration settings value for Gitea runner name. | *None (empty)* |
| `GITEA_RUNNER_REGISTRATION_TOKEN` | Secret authentication credentials, token, or key value. | `CHANGEME` |

---

