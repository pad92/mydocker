# Omni-tools Stack

This stack deploys the following services:

## 1. Omni-tools (`omni-tools`)

### Role
Service container running iib0011/omni-tools.

### External Links
- **Official Project**: [https://hub.docker.com/r/iib0011/omni-tools](https://hub.docker.com/r/iib0011/omni-tools)
- **Docker Image Maintainer**: [Official Hub Registry](https://hub.docker.com/r/iib0011/omni-tools)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `TRAEFIK_HOST_LOCAL` | Internal domain routing host rule (e.g. local.example.lan). | *None (empty)* |
| `TRAEFIK_HOST_PUBLIC` | External domain routing host rule (e.g. pub.domain.com). | *None (empty)* |

---

