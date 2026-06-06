# Ng Stack

This stack deploys the following services:

## Common Configuration Variables
These environment variables are shared and used by multiple services in this stack:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `DOCKER_CONFIG_PATH` | Persistent host directory path for volume mount: DOCKER_CONFIG_PATH. | *None (empty)* |
| `LOCAL_CA_CERT_PATH` | Persistent host directory path for volume mount: LOCAL_CA_CERT_PATH. | *None (empty)* |
| `PGID` | Group ID matching host permissions to run the container. | *None (empty)* |
| `PUID` | User ID matching host permissions to run the container. | *None (empty)* |
| `SERIES_LOCAL_PATH` | Persistent host directory path for volume mount: SERIES_LOCAL_PATH. | *None (empty)* |
| `TORRENTS_PATH` | Persistent host directory path for volume mount: TORRENTS_PATH. | *None (empty)* |
| `TRAEFIK_FQDN` | Traefik Host rule domain routing address (e.g., service.home.lan). | *None (empty)* |
| `TZ` | Timezone configuration for container operations and logs (e.g. Europe/Paris). | *None (empty)* |

---

## 1. Radarr (`radarr`)

### Role
Movie collection manager, parser, and downloader organizer.

### External Links
- **Official Project**: [https://radarr.video/](https://radarr.video/)
- **Docker Image Maintainer**: [linuxserver.io](https://hub.docker.com/r/linuxserver/radarr)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `RADARR_PORT` | Configuration settings value for Radarr port. | *None (empty)* |

---

## 2. Sonarr (`sonarr`)

### Role
TV show episode downloader organizer and calendar parser.

### External Links
- **Official Project**: [https://sonarr.tv/](https://sonarr.tv/)
- **Docker Image Maintainer**: [linuxserver.io](https://hub.docker.com/r/linuxserver/sonarr)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `SONARR_PORT` | Configuration settings value for Sonarr port. | *None (empty)* |

---

## 3. Bazarr (`bazarr`)

### Role
Subtitles downloader and sync tool complementing Radarr and Sonarr.

### External Links
- **Official Project**: [https://www.bazarr.media/](https://www.bazarr.media/)
- **Docker Image Maintainer**: [linuxserver.io](https://hub.docker.com/r/linuxserver/bazarr)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `BAZARR_PORT` | Configuration settings value for Bazarr port. | *None (empty)* |

---

## 4. Lidarr (`lidarr`)

### Role
Music library parser, album tracker, and manager.

### External Links
- **Official Project**: [https://lidarr.audio/](https://lidarr.audio/)
- **Docker Image Maintainer**: [linuxserver.io](https://hub.docker.com/r/linuxserver/lidarr)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `LIDARR_PORT` | Configuration settings value for Lidarr port. | *None (empty)* |

---

## 5. SABnzbd (`sabnzbd`)

### Role
High-speed Usenet NZB downloader and newsreader.

### External Links
- **Official Project**: [https://sabnzbd.org/](https://sabnzbd.org/)
- **Docker Image Maintainer**: [linuxserver.io](https://hub.docker.com/r/linuxserver/sabnzbd)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `SABNZBD_PORT` | Configuration settings value for Sabnzbd port. | *None (empty)* |

---

## 6. Prowlarr (`prowlarr`)

### Role
Service container running linuxserver/prowlarr.

### External Links
- **Official Project**: [https://hub.docker.com/r/linuxserver/prowlarr](https://hub.docker.com/r/linuxserver/prowlarr)
- **Docker Image Maintainer**: [Official Hub Registry](linuxserver/prowlarr)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `PROWLARR_PORT` | Configuration settings value for Prowlarr port. | *None (empty)* |

---

## 7. Recyclarr (`recyclarr`)

### Role
Service container running recyclarr/recyclarr.

### External Links
- **Official Project**: [https://hub.docker.com/r/recyclarr/recyclarr](https://hub.docker.com/r/recyclarr/recyclarr)
- **Docker Image Maintainer**: [Official Hub Registry](recyclarr/recyclarr)

---

## Global / Other Variables
The following variables are defined in `.env.example` but are either global configs or not directly referenced in the compose services:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `BACKUPS_PATH` | Persistent host directory path for volume mount: BACKUPS_PATH. | *None (empty)* |
| `BAZARR_API_KEY` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `DOWNLOAD_PATH` | Persistent host directory path for volume mount: DOWNLOAD_PATH. | *None (empty)* |
| `LIDAR_POSTGRES_DB` | Configuration settings value for Lidar postgres db. | *None (empty)* |
| `LIDAR_POSTGRES_PASSWORD` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `LIDAR_POSTGRES_USER` | Configuration settings value for Lidar postgres user. | *None (empty)* |
| `MEDIA_BASE_PATH` | Persistent host directory path for volume mount: MEDIA_BASE_PATH. | *None (empty)* |
| `MUSIC_PATH` | Persistent host directory path for volume mount: MUSIC_PATH. | *None (empty)* |
| `NFS_CLIENT_IP` | Network IP address configuration. | *None (empty)* |
| `NFS_SERVER_IP` | Network IP address configuration. | *None (empty)* |
| `PROWLARR_API_KEY` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `RADARR_API_KEY` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `SABNZBD_API_KEY` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `SABNZBD_DOWNLOAD_PATH` | Persistent host directory path for volume mount: SABNZBD_DOWNLOAD_PATH. | *None (empty)* |
| `SONARR_API_KEY` | Secret authentication credentials, token, or key value. | `CHANGEME` |

