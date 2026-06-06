# Code-server Stack

This stack deploys the following services:

## 1. Code-server (`code-server`)

### Role
Service container running lscr.io/linuxserver/code-server.

### External Links
- **Official Project**: [https://hub.docker.com/r/lscr.io/linuxserver/code-server](https://hub.docker.com/r/lscr.io/linuxserver/code-server)
- **Docker Image Maintainer**: [Official Hub Registry](lscr.io/linuxserver/code-server)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `CODE_SERVER_DATA_DIR` | Persistent host directory path for volume mount: CODE_SERVER_DATA_DIR. | *None (empty)* |
| `CODE_SERVER_DOMAIN` | Traefik Host rule domain routing address (e.g., service.home.lan). | *None (empty)* |
| `CODE_SERVER_RECYCLARR_DATA_DIR` | Persistent host directory path for volume mount: CODE_SERVER_RECYCLARR_DATA_DIR. | *None (empty)* |
| `DEFAULT_WORKSPACE` | Configuration settings value for Default workspace. | *None (empty)* |
| `DOCKER_MODS` | Configuration settings value for Docker mods. | *None (empty)* |
| `EXTENSIONS_GALLERY` | Configuration settings value for Extensions gallery. | *None (empty)* |
| `PASSWORD` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `PGID` | Group ID matching host permissions to run the container. | *None (empty)* |
| `PROXY_DOMAIN` | Traefik Host rule domain routing address (e.g., service.home.lan). | *None (empty)* |
| `PUID` | User ID matching host permissions to run the container. | *None (empty)* |
| `SUDO_PASSWORD` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `TZ` | Timezone configuration for container operations and logs (e.g. Europe/Paris). | *None (empty)* |
| `VSCODE_EXTENSION_IDS` | Configuration settings value for Vscode extension ids. | *None (empty)* |

---

