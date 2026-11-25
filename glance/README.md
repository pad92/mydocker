# Glance Stack

This stack deploys the following services:

## 1. Glance Dashboard (`glance`)

### Role
Personal startpage aggregation dashboard page.

### External Links
- **Official Project**: [https://github.com/glance-tcg/glance](https://github.com/glance-tcg/glance)
- **Docker Image Maintainer**: [glance-tcg](https://hub.docker.com/r/glanceapp/glance)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `TRAEFIK_HOST_LOCAL` | Internal domain routing host rule (e.g. local.example.lan). | *None (empty)* |

---

## Global / Other Variables
The following variables are defined in `.env.example` but are either global configs or not directly referenced in the compose services:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `MY_SECRET_TOKEN` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `UNIFI_API_KEY` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `UNIFI_CONSOLE_IP` | Network IP address configuration. | *None (empty)* |

