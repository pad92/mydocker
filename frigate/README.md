# Frigate Stack

This stack deploys the following services:

## 1. Frigate (`frigate`)

### Role
Service container running ghcr.io/blakeblackshear/frigate.

### External Links
- **Official Project**: [https://hub.docker.com/r/ghcr.io/blakeblackshear/frigate](https://hub.docker.com/r/ghcr.io/blakeblackshear/frigate)
- **Docker Image Maintainer**: [Official Hub Registry](https://hub.docker.com/r/ghcr.io/blakeblackshear/frigate)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `FRIGATE_DATA_DIR` | Persistent host directory path for volume mount: FRIGATE_DATA_DIR. | *None (empty)* |
| `FRIGATE_RTSP_PASSWORD` | Secret authentication credentials, token, or key value. | `CHANGEME` |

---

