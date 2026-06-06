# Openproject Stack

This stack deploys the following services:

## 1. Openproject (`openproject`)

### Role
Service container running openproject/openproject.

### External Links
- **Official Project**: [https://hub.docker.com/r/openproject/openproject](https://hub.docker.com/r/openproject/openproject)
- **Docker Image Maintainer**: [Official Hub Registry](https://hub.docker.com/r/openproject/openproject)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `OPENPROJECT_ASSETS_DATA_DIR` | Persistent host directory path for volume mount: OPENPROJECT_ASSETS_DATA_DIR. | *None (empty)* |
| `OPENPROJECT_DEFAULT__LANGUAGE` | Configuration settings value for Openproject default language. | *None (empty)* |
| `OPENPROJECT_HOST__NAME` | Configuration settings value for Openproject host name. | *None (empty)* |
| `OPENPROJECT_HTTPS` | Configuration settings value for Openproject https. | *None (empty)* |
| `OPENPROJECT_PGDATA_DATA_DIR` | Persistent host directory path for volume mount: OPENPROJECT_PGDATA_DATA_DIR. | *None (empty)* |
| `OPENPROJECT_SECRET_KEY_BASE` | Secret authentication credentials, token, or key value. | `CHANGEME` |

---

