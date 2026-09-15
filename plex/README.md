# Plex Stack

This stack deploys the following services:

## Common Configuration Variables
These environment variables are shared and used by multiple services in this stack:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `PGID` | Group ID matching host permissions to run the container. | *None (empty)* |
| `PUID` | User ID matching host permissions to run the container. | *None (empty)* |
| `TZ` | Timezone configuration for container operations and logs (e.g. Europe/Paris). | *None (empty)* |

---

## 1. Plex Media Server (`plex`)

### Role
Centralized video, TV show, movie, and audio streaming hub server.

### External Links
- **Official Project**: [https://www.plex.tv/](https://www.plex.tv/)
- **Docker Image**: [plexinc/pms-docker](https://github.com/plexinc/pms-docker)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `PLEX_DATA_DIR` | Persistent host directory path for volume mount: PLEX_DATA_DIR. | *None (empty)* |
| `PLEX_CLAIM` | Optional first-run Plex claim token. Keep it outside Git. | *None (empty)* |
| `PLEX_LOCAL_MEDIA_DIR` | Local host media directory mounted in Plex. | *None (empty)* |
| `PLEX_MEDIA_NFS_PATH` | Remote NFS path containing the series and films mounted through `media_nas`. | *None (empty)* |
| `PLEX_MUSIC_NFS_PATH` | Remote NFS path for the music volume. | *None (empty)* |
| `PLEX_PHOTO_NFS_PATH` | Remote NFS path for the photo volume. | *None (empty)* |

---

## 2. Tautulli (`tautulli`)

### Role
Activity monitoring, stats, notifications, and logging helper for Plex Media Server.

### External Links
- **Official Project**: [https://tautulli.com/](https://tautulli.com/)
- **Docker Image Maintainer**: [linuxserver.io](https://hub.docker.com/r/linuxserver/tautulli)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `PLEX_DOMAIN` | Traefik Host rule domain routing address (e.g., service.home.lan). | *None (empty)* |
| `PLEX_MEDIA_SERVER_LOGS_DATA_DIR` | Persistent host directory path for volume mount: PLEX_MEDIA_SERVER_LOGS_DATA_DIR. | *None (empty)* |
| `PLEX_TAUTULLI_DATA_DIR` | Persistent host directory path for volume mount: PLEX_TAUTULLI_DATA_DIR. | *None (empty)* |

---

## Global / Other Variables
The following variables are defined in `.env.example` but are either global configs or not directly referenced in the compose services:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `PLEX_IP` | Network IP address configuration. | *None (empty)* |
