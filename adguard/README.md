# Adguard Stack

This stack deploys the following services:

## 1. AdGuard Home Sync (`adguardhome-sync`)

### Role
Synchronization tool to replicate settings and blocklists between multiple AdGuard Home instances.

### External Links
- **Official Project**: [https://github.com/itsmartin/adguardhome-sync](https://github.com/itsmartin/adguardhome-sync)
- **Docker Image Maintainer**: [linuxserver.io](https://hub.docker.com/r/linuxserver/adguardhome-sync)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `ADGUARD_PASSWD` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `ADGUARD_USER` | Configuration settings value for Adguard user. | *None (empty)* |
| `CRON` | Configuration settings value for Cron. | *None (empty)* |
| `LOG_LEVEL` | Logging severity filter level (e.g. INFO, WARN, DEBUG). | *None (empty)* |
| `ORIGIN_URL` | Configuration settings value for Origin url. | *None (empty)* |
| `REPLICA1_DHCP_SERVER_ENABLED` | Configuration settings value for Replica1 dhcp server enabled. | *None (empty)* |
| `REPLICA1_URL` | Configuration settings value for Replica1 url. | *None (empty)* |
| `RUN_ON_START` | Configuration settings value for Run on start. | *None (empty)* |

---

## Global / Other Variables
The following variables are defined in `.env.example` but are either global configs or not directly referenced in the compose services:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `PASSWD` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `USER` | Configuration settings value for User. | *None (empty)* |

