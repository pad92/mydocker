# Todo Stack

This stack deploys the following services:

## 1. Donetick (`donetick`)

### Role
Task list and todo management dashboard.

### External Links
- **Official Project**: [https://github.com/donetick/donetick](https://github.com/donetick/donetick)
- **Docker Image Maintainer**: [Donetick Team](https://github.com/donetick)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `DT_ENV` | Configuration settings value for Dt env. | *None (empty)* |
| `DT_SQLITE_PATH` | Persistent host directory path for volume mount: DT_SQLITE_PATH. | *None (empty)* |
| `TODO_DOMAIN` | Traefik Host rule domain routing address (e.g., service.example.lan). | *None (empty)* |
| `TODO_DONETICK_DATA_DIR` | Persistent host directory path for volume mount: TODO_DONETICK_DATA_DIR. | *None (empty)* |

---

