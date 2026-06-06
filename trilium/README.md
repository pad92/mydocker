# Trilium Stack

This stack deploys the following services:

## 1. Trilium Notes (`trilium`)

### Role
Hierarchical personal note-taking application focusing on large personal knowledge bases.

### External Links
- **Official Project**: [https://github.com/zadam/trilium](https://github.com/zadam/trilium)
- **Docker Image Maintainer**: [triliumnext](https://hub.docker.com/r/triliumnext/trilium)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `NODE_TLS_REJECT_UNAUTHORIZED` | Boolean (0 or 1) to ignore self-signed certificate warnings. | *None (empty)* |
| `TRILIUM_DATA_DIR` | Persistent host directory path for volume mount: TRILIUM_DATA_DIR. | `~/trilium-data` |
| `TRILIUM_DOMAIN` | Traefik Host rule domain routing address (e.g., service.home.lan). | *None (empty)* |

---

