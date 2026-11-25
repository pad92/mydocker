# Ng Stack

This stack deploys the media management and download suite services.

## Stack Resource Allocations

To ensure system stability and host resource protection, resource limits are configured for all services in this stack.

### Global Resource Footprint

*   **Total CPU Limits**: `9.0 Cores` (Maximum capacity across all services)
*   **Total Memory Limits**: `15.75 GB` (Maximum capacity across all services)

### Service-Specific Allocation Table

| Service | CPU Limit | Memory Limit |
| :--- | :---: | :---: |
| `radarr` | `1.0` | `2 GB` |
| `sonarr` | `1.0` | `2 GB` |
| `bazarr` | `0.5` | `512 MB` |
| `lidarr` | `1.0` | `4 GB` |
| `sabnzbd` | `2.0` | `4 GB` |
| `prowlarr` | `1.0` | `1 GB` |
| `recyclarr` | `0.5` | `256 MB` |
| `h5ai` | `1.0` | `1 GB` |
| `seerr` | `1.0` | `1 GB` |

---

This stack deploys the following services:

## Common Configuration Variables
These environment variables are shared and used by multiple services in this stack:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `DOCKER_CONFIG_PATH` | Persistent host directory path for volume mount: DOCKER_CONFIG_PATH. | *None (empty)* |
| `LOCAL_CA_CERT_PATH` | Persistent host directory path for volume mount: LOCAL_CA_CERT_PATH. | `/usr/local/share/ca-certificates/example-root-ca.crt` |
| `PGID` | Group ID matching host permissions to run the container. | *None (empty)* |
| `PUID` | User ID matching host permissions to run the container. | *None (empty)* |
| `SERIES_LOCAL_PATH` | Persistent host directory path for volume mount: SERIES_LOCAL_PATH. | *None (empty)* |
| `TORRENTS_PATH` | Persistent host directory path for volume mount: TORRENTS_PATH. | *None (empty)* |
| `TRAEFIK_FQDN` | Traefik Host rule domain routing address (e.g., service.example.lan). | *None (empty)* |
| `TZ` | Timezone configuration for container operations and logs (e.g. Europe/Paris). | *None (empty)* |

---

## Access control (Authentik forward auth)

Radarr, Sonarr, Bazarr, Lidarr, SABnzbd, and Prowlarr sit behind the `authentik@docker` middleware of the `management` stack. A browser that opens one of them is sent to the Authentik login first; only members of the `media-users` group get through. Add users to that group in Authentik (*Directory > Groups*).

Requirements:
- The `management` stack runs Authentik, and `NG_HOST_LOCAL` in `management/.env` has the same value as `TRAEFIK_FQDN` here. The provider is created by the blueprint `management/authentik/blueprints/20-forward-auth-apps.yaml`. If the two values differ, Authentik does not recognise the host and refuses the request.
- If Authentik is down, Traefik disables the protected routers: these apps answer 404 until it is back.

Not protected:
- **h5ai** (root of `TRAEFIK_FQDN`) stays public.
- **Seerr** keeps its own login (Plex accounts) on `SEERR_DOMAIN`.
- **API paths.** A second router per app (`<app>_api`) serves the paths below without the middleware. Each call still needs the app API key. Its rule is longer, so Traefik gives it a higher priority than the protected router.

| App | Paths without forward auth |
| :--- | :--- |
| Radarr, Sonarr, Lidarr | `/<app>/api`, `/<app>/feed` (iCal feeds) |
| Bazarr, SABnzbd | `/<app>/api` |
| Prowlarr | `/prowlarr/api`, `/prowlarr/<id>/api` and `/prowlarr/<id>/download` (Torznab/Newznab endpoints) |

Notes:
- The apps should reach each other by container name on the `ng` network (for example `http://radarr:7878/radarr`), not through Traefik. Calls through Traefik only work on the API paths above.
- The native login of each app stays enabled for now. Switching it to *External* (trust the proxy) is a later step, once forward auth is validated.
- Uptime Kuma monitors that probe the UI through Traefik get a 302 to the login page. Probe the `/<app>/api` path with the API key, or the container on the internal network.

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
- **Docker Image Maintainer**: [Official Hub Registry](https://hub.docker.com/r/linuxserver/prowlarr)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `PROWLARR_PORT` | Configuration settings value for Prowlarr port. | *None (empty)* |

---

## 7. Recyclarr (`recyclarr`)

### Role
Service container running ghcr.io/recyclarr/recyclarr:8.

### External Links
- **Official Project**: [https://github.com/recyclarr/recyclarr](https://github.com/recyclarr/recyclarr)
- **Docker Image Maintainer**: [GitHub Container Registry](https://github.com/recyclarr/recyclarr/pkgs/container/recyclarr)

---

## 8. Seerr (`seerr`)

### Role
User-facing request manager for movies and TV shows: end users browse and request content, which is forwarded to Radarr/Sonarr for automatic download. Requires Plex for authentication and library sync. (Project formerly known as Overseerr.)

### External Links
- **Official Project**: [https://seerr.dev/](https://seerr.dev/)
- **Docker Image Maintainer**: [seerr-team (GHCR)](https://github.com/orgs/seerr-team/packages/container/package/seerr)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `SEERR_DOMAIN` | Dedicated FQDN routed to Seerr (e.g. `requests.example.lan`). | *None (empty)* |
| `SEERR_PORT` | Configuration settings value for Seerr port. | `5055` |

### Notes
- Radarr/Sonarr connections and the Plex link are configured from the Seerr web UI after first boot (no API key variable needed here).
- Unlike the other services in this stack, the Seerr image runs as a fixed `node` user (UID/GID 1000) — it does not honor `PUID`/`PGID`. `chown 1000:1000` the `${DOCKER_CONFIG_PATH}/seerr` host directory before first start, or the container will fail to write its config.
- Seerr does not support being served from a subpath (its client-side routing always navigates to root-relative paths, e.g. `/setup` instead of `/seerr/setup`). It is therefore routed on its own dedicated subdomain (`SEERR_DOMAIN`) rather than a `PathPrefix` under `TRAEFIK_FQDN`, consistent with other single-purpose stacks in this repo (e.g. `gitea`, `trilium`). Point `SEERR_DOMAIN` at the host via DNS before deploying.

---

## 9. h5ai (`h5ai`)

### Role
Read-only web file browser for the media and photo folders, served at the root of `TRAEFIK_FQDN`.

### External Links
- **Docker Image**: [pad92/docker-h5ai](https://hub.docker.com/r/pad92/docker-h5ai)

### Service-Specific Configuration Variables

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `H5AI_ADMIN_PASSWORD` | Admin page password, hashed at each start. Empty keeps the stored hash. | `CHANGEME` |
| `H5AI_SHARE_01` ... `H5AI_SHARE_20` | One folder under `/share` each, as `<source>:/share/<name>`. Unset slots show nothing. | *None (empty)* |
| `H5AI_NFS_01` ... `H5AI_NFS_05` | Path exported by `NFS_SERVER_IP`, mounted by a slot through the volume `h5ai_nfs_01` ... `h5ai_nfs_05`. | *None (empty)* |

### Shared folders
Compose cannot loop over a list, so `docker-compose.yml` holds 20 fixed slots, and each one takes its whole value from a variable. Adding, moving or removing a share only means changing a variable in `.env` or in the Portainer/Dockhand stack, then redeploying: the compose file and the git repository stay unchanged.

```text
H5AI_SHARE_01=movies:/share/movies
H5AI_SHARE_02=/volume1/data/subvol-101-disk-0/downloads/Games:/share/games
H5AI_SHARE_03=h5ai_nfs_01:/share/music
H5AI_NFS_01=/volume1/music/library
```

The value is `<source>:<target>`, without options: the compose file appends `:ro`, so every share is read-only (adding `:ro` yourself makes the mount invalid). The target starts with `/share/`. The source is one of:

| Source | Meaning |
| :--- | :--- |
| A path on the Docker host | Bind mount of that folder |
| `h5ai_nfs_01` ... `h5ai_nfs_05` | The NFS path set in `H5AI_NFS_01` ... `H5AI_NFS_05` |
| A volume of the stack (`movies`, `series`, `download`, `backups`...) | The same folder as the service that uses it |

An unset slot mounts the empty volume `h5ai_unused` at `/.h5ai-unused/<slot>`, outside `/share`, so it never shows in h5ai. A `h5ai_nfs_*` volume that no slot uses is not created. A volume name with a typo stops the deploy with `refers to undefined volume`. Paths cannot contain spaces or `:`.

More than 20 shares or 5 NFS paths needs new lines in `docker-compose.yml`, following the same pattern.

After an NFS path changes, Docker keeps the old options of the existing volume: remove the volume (`docker volume rm <project>_h5ai_nfs_01`) once the container is stopped, then redeploy.

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

