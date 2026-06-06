# Crowdsec Stack

This stack deploys the following services:

## 1. CrowdSec (`crowdsec`)

### Role
Collaborative behavior detection engine blocking scanner IP logs and malicious activities.

### External Links
- **Official Project**: [https://www.crowdsec.net/](https://www.crowdsec.net/)
- **Docker Image Maintainer**: [CrowdSec](https://hub.docker.com/r/crowdsecurity/crowdsec)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `COLLECTIONS` | Configuration settings value for Collections. | *None (empty)* |
| `CROWDSEC_LOG_AUTH_LOG_DATA_DIR` | Persistent host directory path for volume mount: CROWDSEC_LOG_AUTH_LOG_DATA_DIR. | *None (empty)* |
| `CROWDSEC_LOG_CROWDSEC_DATA_DIR` | Persistent host directory path for volume mount: CROWDSEC_LOG_CROWDSEC_DATA_DIR. | *None (empty)* |
| `CROWDSEC_OPT_CROWDSEC_DATA_DIR` | Persistent host directory path for volume mount: CROWDSEC_OPT_CROWDSEC_DATA_DIR. | *None (empty)* |
| `CROWDSEC_OPT_CROWDSEC_DB_DATA_DIR` | Persistent host directory path for volume mount: CROWDSEC_OPT_CROWDSEC_DB_DATA_DIR. | *None (empty)* |
| `PGID` | Group ID matching host permissions to run the container. | *None (empty)* |

---

