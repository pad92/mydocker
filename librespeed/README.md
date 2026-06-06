# Librespeed Stack

This stack deploys the following services:

## 1. Librespeed (`librespeed`)

### Role
Service container running lscr.io/linuxserver/librespeed.

### External Links
- **Official Project**: [https://hub.docker.com/r/lscr.io/linuxserver/librespeed](https://hub.docker.com/r/lscr.io/linuxserver/librespeed)
- **Docker Image Maintainer**: [Official Hub Registry](https://hub.docker.com/r/lscr.io/linuxserver/librespeed)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `CUSTOM_RESULTS` | Configuration settings value for Custom results. | *None (empty)* |
| `DB_TYPE` | Configuration settings value for Db type. | *None (empty)* |
| `LIBRESPEED_DATA_DIR` | Persistent host directory path for volume mount: LIBRESPEED_DATA_DIR. | *None (empty)* |
| `LIBRESPEED_DOMAIN` | Traefik Host rule domain routing address (e.g., service.home.lan). | *None (empty)* |
| `PGID` | Group ID matching host permissions to run the container. | *None (empty)* |
| `PUID` | User ID matching host permissions to run the container. | *None (empty)* |
| `TZ` | Timezone configuration for container operations and logs (e.g. Europe/Paris). | *None (empty)* |
| `USE_NEW_DESIGN` | Configuration settings value for Use new design. | *None (empty)* |

---

