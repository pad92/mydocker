# Beszel Stack

This stack deploys the following services:

## 1. Beszel Hub (`beszel`)

### Role
Lightweight server performance dashboard and alerting dashboard gateway.

### External Links
- **Official Project**: [https://github.com/henrygd/beszel](https://github.com/henrygd/beszel)
- **Docker Image Maintainer**: [henrygd](https://hub.docker.com/r/henrygd/beszel)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `BESZEL_DATA_DIR` | Persistent host directory path for volume mount: BESZEL_DATA_DIR. | *None (empty)* |
| `BESZEL_DOMAIN` | Traefik Host rule domain routing address (e.g., service.home.lan). | *None (empty)* |

---

## 2. Beszel-agent (`beszel-agent`)

### Role
Service container running henrygd/beszel-agent-nvidia.

### External Links
- **Official Project**: [https://hub.docker.com/r/henrygd/beszel-agent-nvidia](https://hub.docker.com/r/henrygd/beszel-agent-nvidia)
- **Docker Image Maintainer**: [Official Hub Registry](henrygd/beszel-agent-nvidia)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `BESZEL_AGENT_DATA_DIR` | Persistent host directory path for volume mount: BESZEL_AGENT_DATA_DIR. | *None (empty)* |
| `BESZEL_DBUS_SYSTEM_BUS_SOCKET_DATA_DIR` | Persistent host directory path for volume mount: BESZEL_DBUS_SYSTEM_BUS_SOCKET_DATA_DIR. | *None (empty)* |
| `HUB_URL` | Configuration settings value for Hub url. | *None (empty)* |
| `KEY` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `LISTEN` | Configuration settings value for Listen. | *None (empty)* |
| `TOKEN` | Secret authentication credentials, token, or key value. | `CHANGEME` |

---

