# Homeassistant Stack

This stack deploys the following services:

## 1. Home Assistant (`homeassistant`)

### Role
Central home automation router putting local privacy and local controls first.

### External Links
- **Official Project**: [https://www.home-assistant.io/](https://www.home-assistant.io/)
- **Docker Image Maintainer**: [Home Assistant Team](https://hub.docker.com/r/homeassistant/home-assistant)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `HOMEASSISTANT_DATA_DIR` | Persistent host directory path for volume mount: HOMEASSISTANT_DATA_DIR. | *None (empty)* |
| `TZ` | Timezone configuration for container operations and logs (e.g. Europe/Paris). | *None (empty)* |

---

