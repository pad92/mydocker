# Photoprism Stack

This stack deploys the following services:

## 1. PhotoPrism (`photoprism`)

### Role
AI-powered digital photo aggregation catalog manager.

### External Links
- **Official Project**: [https://photoprism.app/](https://photoprism.app/)
- **Docker Image Maintainer**: [PhotoPrism Team](https://hub.docker.com/r/photoprism/photoprism)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `PHOTOPRISM_ADMIN_PASSWORD` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `PHOTOPRISM_ADMIN_USER` | Configuration settings value for Photoprism admin user. | *None (empty)* |
| `PHOTOPRISM_AUTH_MODE` | Secret authentication credentials, token, or key value. | *None (empty)* |
| `PHOTOPRISM_AUTO_IMPORT` | Configuration settings value for Photoprism auto import. | *None (empty)* |
| `PHOTOPRISM_AUTO_INDEX` | Configuration settings value for Photoprism auto index. | *None (empty)* |
| `PHOTOPRISM_BACKUP_ALBUMS` | Configuration settings value for Photoprism backup albums. | *None (empty)* |
| `PHOTOPRISM_BACKUP_DATABASE` | Configuration settings value for Photoprism backup database. | *None (empty)* |
| `PHOTOPRISM_BACKUP_SCHEDULE` | Configuration settings value for Photoprism backup schedule. | *None (empty)* |
| `PHOTOPRISM_DATABASE_DRIVER` | Configuration settings value for Photoprism database driver. | *None (empty)* |
| `PHOTOPRISM_DATABASE_NAME` | Configuration settings value for Photoprism database name. | *None (empty)* |
| `PHOTOPRISM_DATABASE_PASSWORD` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `PHOTOPRISM_DATABASE_SERVER` | Configuration settings value for Photoprism database server. | *None (empty)* |
| `PHOTOPRISM_DATABASE_USER` | Configuration settings value for Photoprism database user. | *None (empty)* |
| `PHOTOPRISM_DATA_DIR` | Persistent host directory path for volume mount: PHOTOPRISM_DATA_DIR. | *None (empty)* |
| `PHOTOPRISM_DEFAULT_TLS` | Configuration settings value for Photoprism default tls. | *None (empty)* |
| `PHOTOPRISM_DETECT_NSFW` | Configuration settings value for Photoprism detect nsfw. | *None (empty)* |
| `PHOTOPRISM_DISABLE_CHOWN` | Configuration settings value for Photoprism disable chown. | *None (empty)* |
| `PHOTOPRISM_DISABLE_CLASSIFICATION` | Configuration settings value for Photoprism disable classification. | *None (empty)* |
| `PHOTOPRISM_DISABLE_FACES` | Configuration settings value for Photoprism disable faces. | *None (empty)* |
| `PHOTOPRISM_DISABLE_RAW` | Configuration settings value for Photoprism disable raw. | *None (empty)* |
| `PHOTOPRISM_DISABLE_SETTINGS` | Configuration settings value for Photoprism disable settings. | *None (empty)* |
| `PHOTOPRISM_DISABLE_TENSORFLOW` | Configuration settings value for Photoprism disable tensorflow. | *None (empty)* |
| `PHOTOPRISM_DISABLE_TLS` | Configuration settings value for Photoprism disable tls. | *None (empty)* |
| `PHOTOPRISM_DISABLE_VECTORS` | Configuration settings value for Photoprism disable vectors. | *None (empty)* |
| `PHOTOPRISM_DISABLE_WEBDAV` | Configuration settings value for Photoprism disable webdav. | *None (empty)* |
| `PHOTOPRISM_DOMAIN` | Traefik Host rule domain routing address (e.g., service.home.lan). | *None (empty)* |
| `PHOTOPRISM_EXPERIMENTAL` | Configuration settings value for Photoprism experimental. | *None (empty)* |
| `PHOTOPRISM_HTTP_COMPRESSION` | Configuration settings value for Photoprism http compression. | *None (empty)* |
| `PHOTOPRISM_LOG_LEVEL` | Configuration settings value for Photoprism log level. | *None (empty)* |
| `PHOTOPRISM_ORIGINALS_LIMIT` | Configuration settings value for Photoprism originals limit. | *None (empty)* |
| `PHOTOPRISM_PHOTOS_DATA_DIR` | Persistent host directory path for volume mount: PHOTOPRISM_PHOTOS_DATA_DIR. | *None (empty)* |
| `PHOTOPRISM_RAW_PRESETS` | Configuration settings value for Photoprism raw presets. | *None (empty)* |
| `PHOTOPRISM_READONLY` | Configuration settings value for Photoprism readonly. | *None (empty)* |
| `PHOTOPRISM_SIDECAR_YAML` | Configuration settings value for Photoprism sidecar yaml. | *None (empty)* |
| `PHOTOPRISM_SITE_CAPTION` | Configuration settings value for Photoprism site caption. | *None (empty)* |
| `PHOTOPRISM_SITE_URL` | Configuration settings value for Photoprism site url. | *None (empty)* |
| `PHOTOPRISM_UPLOAD_NSFW` | Configuration settings value for Photoprism upload nsfw. | *None (empty)* |

---

## 2. MariaDB Database (`mariadb`)

### Role
Fast relational SQL database server clone of MySQL.

### External Links
- **Official Project**: [https://mariadb.org/](https://mariadb.org/)
- **Docker Image Maintainer**: [Docker Official](https://hub.docker.com/_/mariadb)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `CONF_DIR` | Persistent host directory path for volume mount: CONF_DIR. | *None (empty)* |
| `MARIADB_AUTO_UPGRADE` | Configuration settings value for Mariadb auto upgrade. | *None (empty)* |
| `MARIADB_DATABASE` | Name of the MariaDB database schemas. | *None (empty)* |
| `MARIADB_INITDB_SKIP_TZINFO` | Configuration settings value for Mariadb initdb skip tzinfo. | *None (empty)* |
| `MARIADB_PASSWORD` | Database user password for MariaDB server. | `CHANGEME` |
| `MARIADB_ROOT_PASSWORD` | Root administrator password for MariaDB server. | `CHANGEME` |
| `MARIADB_USER` | Database user name for MariaDB server. | *None (empty)* |

---

