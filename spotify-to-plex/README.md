# Spotify-to-plex Stack

This stack deploys the following services:

## 1. Plexist (`plexist`)

### Role
Service container running gyarbij/plexist:main  # Or: ghcr.io/gyarbij/plexist.

### External Links
- **Official Project**: [https://hub.docker.com/r/gyarbij/plexist:main  # Or: ghcr.io/gyarbij/plexist](https://hub.docker.com/r/gyarbij/plexist:main  # Or: ghcr.io/gyarbij/plexist)
- **Docker Image Maintainer**: [Official Hub Registry](gyarbij/plexist:main  # Or: ghcr.io/gyarbij/plexist)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `ADD_PLAYLIST_DESCRIPTION` | Configuration settings value for Add playlist description. | *None (empty)* |
| `ADD_PLAYLIST_POSTER` | Configuration settings value for Add playlist poster. | *None (empty)* |
| `APPEND_INSTEAD_OF_SYNC` | Configuration settings value for Append instead of sync. | *None (empty)* |
| `LOG_FORMAT` | Configuration settings value for Log format. | *None (empty)* |
| `LOG_LEVEL` | Logging severity filter level (e.g. INFO, WARN, DEBUG). | *None (empty)* |
| `MAX_CONCURRENT_REQUESTS` | Configuration settings value for Max concurrent requests. | *None (empty)* |
| `MAX_REQUESTS_PER_SECOND` | Configuration settings value for Max requests per second. | *None (empty)* |
| `PLEX_TOKEN` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `PLEX_URL` | Configuration settings value for Plex url. | *None (empty)* |
| `SECONDS_TO_WAIT` | Configuration settings value for Seconds to wait. | *None (empty)* |
| `SPOTIFY_CACHE_PATH` | Persistent host directory path for volume mount: SPOTIFY_CACHE_PATH. | *None (empty)* |
| `SPOTIFY_CLIENT_ID` | Configuration settings value for Spotify client id. | *None (empty)* |
| `SPOTIFY_CLIENT_SECRET` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `SPOTIFY_REDIRECT_URI` | Configuration settings value for Spotify redirect uri. | *None (empty)* |
| `SPOTIFY_TO_PLEX_PLEXIST_DATA_DIR` | Persistent host directory path for volume mount: SPOTIFY_TO_PLEX_PLEXIST_DATA_DIR. | *None (empty)* |
| `SPOTIFY_USER_ID` | Configuration settings value for Spotify user id. | *None (empty)* |
| `SYNC_LIKED_TRACKS` | Configuration settings value for Sync liked tracks. | *None (empty)* |
| `SYNC_PAIRS` | Configuration settings value for Sync pairs. | *None (empty)* |
| `WRITE_MISSING_AS_CSV` | Configuration settings value for Write missing as csv. | *None (empty)* |
| `WRITE_MISSING_AS_JSON` | Configuration settings value for Write missing as json. | *None (empty)* |

---

