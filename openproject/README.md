# Openproject Stack

## Role
Collaborative project management and tracking tool.

## External Links
- **Official Project**: [https://www.openproject.org/](https://www.openproject.org/)
- **Docker Image Maintainer**: [OpenProject](https://hub.docker.com/r/openproject/community)

## Configuration Variables
Define the following environment variables in your local `.env` file:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `OPENPROJECT_ASSETS_DATA_DIR` | Persistent host directory path for volume mount: OPENPROJECT_ASSETS_DATA_DIR. | *None (empty)* |
| `OPENPROJECT_DEFAULT__LANGUAGE` | Configuration settings value for Openproject default language. | *None (empty)* |
| `OPENPROJECT_HOST__NAME` | Configuration settings value for Openproject host name. | *None (empty)* |
| `OPENPROJECT_HTTPS` | Configuration settings value for Openproject https. | *None (empty)* |
| `OPENPROJECT_PGDATA_DATA_DIR` | Persistent host directory path for volume mount: OPENPROJECT_PGDATA_DATA_DIR. | *None (empty)* |
| `OPENPROJECT_SECRET_KEY_BASE` | Secret authentication credentials, token, or key value. | `CHANGEME` |

