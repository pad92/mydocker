# Vaultwarden Stack

This stack deploys the following services:

## 1. Server (`server`)

### Role
Service container running vaultwarden/server.

### External Links
- **Official Project**: [https://hub.docker.com/r/vaultwarden/server](https://hub.docker.com/r/vaultwarden/server)
- **Docker Image Maintainer**: [Official Hub Registry](vaultwarden/server)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `VAULTWARDEN_DATA_DIR` | Persistent host directory path for volume mount: VAULTWARDEN_DATA_DIR. | *None (empty)* |

---

