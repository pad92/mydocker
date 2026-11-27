# Tududi Stack

This stack deploys the following services:

## 1. Tududi (`tududi`)

### Role
Service container running chrisvel/tududi.

### External Links
- **Official Project**: [https://hub.docker.com/r/chrisvel/tududi](https://hub.docker.com/r/chrisvel/tududi)
- **Docker Image Maintainer**: [Official Hub Registry](https://hub.docker.com/r/chrisvel/tududi)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `TUDUDI_ALLOWED_ORIGINS` | Configuration settings value for Tududi allowed origins. | *None (empty)* |
| `TUDUDI_DATA_DIR` | Persistent host directory path for volume mount: TUDUDI_DATA_DIR. | *None (empty)* |
| `TUDUDI_DOMAIN` | Traefik Host rule domain routing address (e.g., service.example.lan). | *None (empty)* |
| `TUDUDI_INTERNAL_SSL_ENABLED` | Configuration settings value for Tududi internal ssl enabled. | *None (empty)* |
| `TUDUDI_SESSION_SECRET` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `TUDUDI_UPLOADS_DATA_DIR` | Persistent host directory path for volume mount: TUDUDI_UPLOADS_DATA_DIR. | *None (empty)* |
| `TUDUDI_USER_EMAIL` | Configuration settings value for Tududi user email. | *None (empty)* |
| `TUDUDI_USER_PASSWORD` | Secret authentication credentials, token, or key value. | `CHANGEME` |

---

