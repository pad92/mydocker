# Beszel-agent Stack

This stack deploys the following services:

## 1. Beszel Agent (`beszel-agent`)

### Role
Lightweight client metrics agent executing resource monitoring on host system.

### External Links
- **Official Project**: [https://github.com/henrygd/beszel](https://github.com/henrygd/beszel)
- **Docker Image Maintainer**: [henrygd](https://hub.docker.com/r/henrygd/beszel-agent)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `BESZEL_AGENT_DATA_DIR` | Persistent host directory path for volume mount: BESZEL_AGENT_DATA_DIR. | *None (empty)* |
| `BESZEL_AGENT_DBUS_SYSTEM_BUS_SOCKET_DATA_DIR` | Persistent host directory path for volume mount: BESZEL_AGENT_DBUS_SYSTEM_BUS_SOCKET_DATA_DIR. | *None (empty)* |
| `HUB_URL` | Configuration settings value for Hub url. | *None (empty)* |
| `KEY` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `LISTEN` | Configuration settings value for Listen. | *None (empty)* |
| `TOKEN` | Secret authentication credentials, token, or key value. | `CHANGEME` |

---

