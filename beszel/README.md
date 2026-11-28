# Beszel Stack

The hub runs on ns01: see [beszel-hub](../beszel-hub/README.md). This stack keeps the agent of chataigne. `HUB_URL` can stay `http://beszel.home.lan`: Traefik on chataigne forwards that name to ns01.

## Beszel-agent (`beszel-agent`)

### Role
Service container running henrygd/beszel-agent-nvidia.

### External Links
- **Official Project**: [https://hub.docker.com/r/henrygd/beszel-agent-nvidia](https://hub.docker.com/r/henrygd/beszel-agent-nvidia)
- **Docker Image Maintainer**: [Official Hub Registry](https://hub.docker.com/r/henrygd/beszel-agent-nvidia)

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

