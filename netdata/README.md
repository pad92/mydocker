# Netdata Stack

This stack deploys the following services:

## 1. Netdata (`netdata`)

### Role
Service container running netdata/netdata.

### External Links
- **Official Project**: [https://hub.docker.com/r/netdata/netdata](https://hub.docker.com/r/netdata/netdata)
- **Docker Image Maintainer**: [Official Hub Registry](https://hub.docker.com/r/netdata/netdata)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `DIR_DATAS` | Configuration settings value for Dir datas. | *None (empty)* |
| `NETDATA_ETC_GROUP_DATA_DIR` | Persistent host directory path for volume mount: NETDATA_ETC_GROUP_DATA_DIR. | *None (empty)* |
| `NETDATA_ETC_OS_RELEASE_DATA_DIR` | Persistent host directory path for volume mount: NETDATA_ETC_OS_RELEASE_DATA_DIR. | *None (empty)* |
| `NETDATA_ETC_PASSWD_DATA_DIR` | Persistent host directory path for volume mount: NETDATA_ETC_PASSWD_DATA_DIR. | *None (empty)* |
| `NETDATA_RUN_DBUS_DATA_DIR` | Persistent host directory path for volume mount: NETDATA_RUN_DBUS_DATA_DIR. | *None (empty)* |
| `NETDATA_VAR_LOG_DATA_DIR` | Persistent host directory path for volume mount: NETDATA_VAR_LOG_DATA_DIR. | *None (empty)* |
| `TRAEFIK_FQDN` | Traefik Host rule domain routing address (e.g., service.example.lan). | *None (empty)* |

---

