# Bookmarks Stack

This stack deploys the following services:

## 1. Shaarli (`shaarli`)

### Role
Service container running shaarli/shaarli.

### External Links
- **Official Project**: [https://hub.docker.com/r/shaarli/shaarli](https://hub.docker.com/r/shaarli/shaarli)
- **Docker Image Maintainer**: [Official Hub Registry](https://hub.docker.com/r/shaarli/shaarli)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `BOOKMARKS_SHAARLI_CACHE_DATA_DIR` | Persistent host directory path for volume mount: BOOKMARKS_SHAARLI_CACHE_DATA_DIR. | *None (empty)* |
| `BOOKMARKS_SHAARLI_DATA_DIR` | Persistent host directory path for volume mount: BOOKMARKS_SHAARLI_DATA_DIR. | *None (empty)* |
| `TRAEFIK_HOST_LOCAL` | Internal domain routing host rule (e.g. local.example.lan). | *None (empty)* |
| `TRAEFIK_HOST_PUBLIC` | External domain routing host rule (e.g. pub.domain.com). | *None (empty)* |

---

