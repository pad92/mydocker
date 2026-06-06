# Management Stack

This stack deploys the following services:

## Common Configuration Variables
These environment variables are shared and used by multiple services in this stack:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `CA_CERT_NAME` | Configuration settings value for Ca cert name. | *None (empty)* |
| `MANAGEMENT_SHARE_CA_CERTIFICATES_DATA_DIR` | Persistent host directory path for volume mount: MANAGEMENT_SHARE_CA_CERTIFICATES_DATA_DIR. | *None (empty)* |

---

## 1. Traefik (`traefik`)

### Role
Service container running traefik.

### External Links
- **Official Project**: [https://hub.docker.com/r/traefik](https://hub.docker.com/r/traefik)
- **Docker Image Maintainer**: [Official Hub Registry](traefik)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `ACME_CA_SERVER` | Configuration settings value for Acme ca server. | *None (empty)* |
| `ACME_EMAIL` | Configuration settings value for Acme email. | *None (empty)* |
| `TRAEFIK_HOST_LOCAL` | Internal domain routing host rule (e.g. local.home.lan). | *None (empty)* |

---

## 2. Portainer (`portainer`)

### Role
Service container running portainer/portainer-ee.

### External Links
- **Official Project**: [https://hub.docker.com/r/portainer/portainer-ee](https://hub.docker.com/r/portainer/portainer-ee)
- **Docker Image Maintainer**: [Official Hub Registry](portainer/portainer-ee)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `MANAGEMENT_PORTAINER_DATA_DIR` | Persistent host directory path for volume mount: MANAGEMENT_PORTAINER_DATA_DIR. | *None (empty)* |
| `PORTAINER_HOST_LOCAL` | Configuration settings value for Portainer host local. | *None (empty)* |

---

## 3. Uptime Kuma (`uptime-kuma`)

### Role
Self-hosted network host ping monitor and service status monitor.

### External Links
- **Official Project**: [https://github.com/louislam/uptime-kuma](https://github.com/louislam/uptime-kuma)
- **Docker Image Maintainer**: [Louis Lam](https://hub.docker.com/r/louislam/uptime-kuma)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `MANAGEMENT_UPTIME_KUMA_DATA_DIR` | Persistent host directory path for volume mount: MANAGEMENT_UPTIME_KUMA_DATA_DIR. | *None (empty)* |
| `UPTIME_HOST_LOCAL` | Configuration settings value for Uptime host local. | *None (empty)* |

---

## Global / Other Variables
The following variables are defined in `.env.example` but are either global configs or not directly referenced in the compose services:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `HOMARR_HOST_LOCAL` | Configuration settings value for Homarr host local. | *None (empty)* |
| `HOMARR_SECRET_ENCRYPTION_KEY` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `HOMEPAGE_HOST_LOCAL` | Configuration settings value for Homepage host local. | *None (empty)* |
| `MIRROR_HOST_LOCAL` | Configuration settings value for Mirror host local. | *None (empty)* |

