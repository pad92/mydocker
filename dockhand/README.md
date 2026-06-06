# Dockhand Stack

This stack deploys the following services:

## 1. Dockhand (`dockhand`)

### Role
Service container running fnsys/dockhand.

### External Links
- **Official Project**: [https://hub.docker.com/r/fnsys/dockhand](https://hub.docker.com/r/fnsys/dockhand)
- **Docker Image Maintainer**: [Official Hub Registry](https://hub.docker.com/r/fnsys/dockhand)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `DOCKHAND_COMPOSES_DATA_DIR` | Persistent host directory path for volume mount: DOCKHAND_COMPOSES_DATA_DIR. | *None (empty)* |
| `DOCKHAND_DATA_DIR` | Persistent host directory path for volume mount: DOCKHAND_DATA_DIR. | *None (empty)* |
| `DOCKHAND_DOMAIN` | Traefik Host rule domain routing address (e.g., service.home.lan). | *None (empty)* |
| `DOCKHAND_PORTAINER_DATA_DIR` | Persistent host directory path for volume mount: DOCKHAND_PORTAINER_DATA_DIR. | *None (empty)* |

---

