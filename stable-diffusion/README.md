# Stable-diffusion Stack

This stack deploys the following services:

## 1. Sd-webui (`sd-webui`)

### Role
Service container running goolashe/automatic1111-sd-webui.

### External Links
- **Official Project**: [https://hub.docker.com/r/goolashe/automatic1111-sd-webui](https://hub.docker.com/r/goolashe/automatic1111-sd-webui)
- **Docker Image Maintainer**: [Official Hub Registry](https://hub.docker.com/r/goolashe/automatic1111-sd-webui)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `CLI_ARGS` | Configuration settings value for Cli args. | *None (empty)* |
| `STABLE_DIFFUSION_SD_DATA_DIR` | Persistent host directory path for volume mount: STABLE_DIFFUSION_SD_DATA_DIR. | *None (empty)* |

---

