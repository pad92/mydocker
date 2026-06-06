# Watchtower Stack

This stack deploys the following services:

## 1. Watchtower (`watchtower`)

### Role
Service container running nickfedor/watchtower.

### External Links
- **Official Project**: [https://hub.docker.com/r/nickfedor/watchtower](https://hub.docker.com/r/nickfedor/watchtower)
- **Docker Image Maintainer**: [Official Hub Registry](https://hub.docker.com/r/nickfedor/watchtower)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `TZ` | Timezone configuration for container operations and logs (e.g. Europe/Paris). | *None (empty)* |
| `WATCHTOWER_CLEANUP` | Configuration settings value for Watchtower cleanup. | *None (empty)* |
| `WATCHTOWER_LIFECYCLE_HOOKS` | Configuration settings value for Watchtower lifecycle hooks. | *None (empty)* |
| `WATCHTOWER_NOTIFICATIONS` | Configuration settings value for Watchtower notifications. | *None (empty)* |
| `WATCHTOWER_NOTIFICATION_URL` | Configuration settings value for Watchtower notification url. | *None (empty)* |
| `WATCHTOWER_POLL_INTERVAL` | Configuration settings value for Watchtower poll interval. | *None (empty)* |
| `WATCHTOWER_REMOVE_VOLUMES` | Configuration settings value for Watchtower remove volumes. | *None (empty)* |

---

