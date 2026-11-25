# Ollama Stack

This stack deploys the following services:

## Common Configuration Variables
These environment variables are shared and used by multiple services in this stack:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `OLLAMA_MODELS_DATA_DIR` | Persistent host directory path for volume mount: OLLAMA_MODELS_DATA_DIR. | *None (empty)* |

---

## 1. Open WebUI (`open-webui`)

### Role
Chat interface client for local Ollama and OpenAI API model endpoints.

### External Links
- **Official Project**: [https://github.com/open-webui/open-webui](https://github.com/open-webui/open-webui)
- **Docker Image Maintainer**: [Open WebUI](https://github.com/open-webui)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `LOG_LEVEL` | Logging severity filter level (e.g. INFO, WARN, DEBUG). | *None (empty)* |
| `MODEL_DOWNLOAD_DIR` | Persistent host directory path for volume mount: MODEL_DOWNLOAD_DIR. | *None (empty)* |
| `OLLAMA_API_BASE_URL` | Configuration settings value for Ollama api base url. | *None (empty)* |
| `OLLAMA_API_URL` | Configuration settings value for Ollama api url. | *None (empty)* |
| `OLLAMA_DOMAIN` | Traefik Host rule domain routing address (e.g., service.example.lan). | *None (empty)* |
| `OLLAMA_OPEN_WEBUI_BACKEND_DATA_DIR` | Persistent host directory path for volume mount: OLLAMA_OPEN_WEBUI_BACKEND_DATA_DIR. | *None (empty)* |
| `OLLAMA_OPEN_WEBUI_DATA_DIR` | Persistent host directory path for volume mount: OLLAMA_OPEN_WEBUI_DATA_DIR. | *None (empty)* |
| `WEBUI_SECRET_KEY` | Secret authentication credentials, token, or key value. | `CHANGEME` |

---

## 2. Ollama (`ollama`)

### Role
Hardware-accelerated LLM models local execution engine.

### External Links
- **Official Project**: [https://ollama.com/](https://ollama.com/)
- **Docker Image Maintainer**: [Ollama Team](https://hub.docker.com/r/ollama/ollama)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `NVIDIA_DRIVER_CAPABILITIES` | Configuration settings value for Nvidia driver capabilities. | *None (empty)* |
| `NVIDIA_VISIBLE_DEVICES` | Configuration settings value for Nvidia visible devices. | *None (empty)* |
| `OLLAMA_HOST` | Configuration settings value for Ollama host. | *None (empty)* |
| `OLLAMA_KEEP_ALIVE` | Configuration settings value for Ollama keep alive. | *None (empty)* |
| `OLLAMA_OLLAMA_DATA_DIR` | Persistent host directory path for volume mount: OLLAMA_OLLAMA_DATA_DIR. | *None (empty)* |

---

## Global / Other Variables
The following variables are defined in `.env.example` but are either global configs or not directly referenced in the compose services:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `HOME_OLLAMA` | Configuration settings value for Home ollama. | *None (empty)* |

