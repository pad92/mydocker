# Karakeep Stack

This stack deploys the following services:

## 1. Web (`web`)

### Role
Service container running ghcr.io/karakeep-app/karakeep:${KARAKEEP_VERSION.

### External Links
- **Official Project**: [https://hub.docker.com/r/ghcr.io/karakeep-app/karakeep:${KARAKEEP_VERSION](https://hub.docker.com/r/ghcr.io/karakeep-app/karakeep:${KARAKEEP_VERSION)
- **Docker Image Maintainer**: [Official Hub Registry](https://hub.docker.com/r/ghcr.io/karakeep-app/karakeep:${KARAKEEP_VERSION)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `BROWSER_WEB_URL` | Configuration settings value for Browser web url. | *None (empty)* |
| `DATA_DIR` | Persistent host directory path for volume mount: DATA_DIR. | *None (empty)* |
| `KARAKEEP_DATA_DIR` | Persistent host directory path for volume mount: KARAKEEP_DATA_DIR. | *None (empty)* |
| `KARAKEEP_VERSION` | Configuration settings value for Karakeep version. | `release` |
| `MEILI_ADDR` | Configuration settings value for Meili addr. | *None (empty)* |
| `TRAEFIK_HOST_PUBLIC` | External domain routing host rule (e.g. pub.domain.com). | *None (empty)* |

---

## 2. Chrome (`chrome`)

### Role
Service container running gcr.io/zenika-hub/alpine-chrome.

### External Links
- **Official Project**: [https://hub.docker.com/r/gcr.io/zenika-hub/alpine-chrome](https://hub.docker.com/r/gcr.io/zenika-hub/alpine-chrome)
- **Docker Image Maintainer**: [Official Hub Registry](https://hub.docker.com/r/gcr.io/zenika-hub/alpine-chrome)

---

## 3. Meilisearch (`meilisearch`)

### Role
Service container running getmeili/meilisearch.

### External Links
- **Official Project**: [https://hub.docker.com/r/getmeili/meilisearch](https://hub.docker.com/r/getmeili/meilisearch)
- **Docker Image Maintainer**: [Official Hub Registry](https://hub.docker.com/r/getmeili/meilisearch)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `KARAKEEP_MEILISEARCH_DATA_DIR` | Persistent host directory path for volume mount: KARAKEEP_MEILISEARCH_DATA_DIR. | *None (empty)* |
| `MEILI_NO_ANALYTICS` | Configuration settings value for Meili no analytics. | *None (empty)* |

---

## Global / Other Variables
The following variables are defined in `.env.example` but are either global configs or not directly referenced in the compose services:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `MEILI_MASTER_KEY` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `NEXTAUTH_SECRET` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `NEXTAUTH_URL` | Secret authentication credentials, token, or key value. | *None (empty)* |

