# Ollama

This stack runs [Ollama](https://ollama.com/) on the NVIDIA GPU of the host,
and [Open WebUI](https://github.com/open-webui/open-webui) in front of it
behind Traefik. Other stacks, such as Gramps Web, also call the Ollama API.

| Service | Image | Role |
| --- | --- | --- |
| `ollama` | `ollama/ollama:latest` | Model runtime and API (port 11434) |
| `open-webui` | `ghcr.io/open-webui/open-webui:main` | Chat interface (port 8080, through Traefik) |

## Exposure

The Ollama API has no authentication: anyone who reaches port 11434 can run,
pull and delete models. The port is therefore published on one host address
only, `OLLAMA_BIND_ADDRESS`, set to the LAN address of the GPU host that the
other stacks use. The stack does not deploy while it is empty. Never set it
to `0.0.0.0`. A host firewall that only lets the client hosts in is still
worth adding.

Open WebUI does not use that port: it reaches Ollama as
`http://ollama:11434` on the internal `ollama` network.

Open WebUI saves its connection settings in its database. On an instance
that already ran with an older URL, the `OLLAMA_BASE_URL` of the Compose
file may be ignored: check Admin Panel > Settings > Connections and set the
Ollama URL to `http://ollama:11434` if needed.

## Context length

Ollama picks the context window from the free VRAM when nothing sets it,
and a prompt longer than the window is cut without error. The stack sets
`OLLAMA_CONTEXT_LENGTH=8192` tokens by default, which fits next to a 7B model
in Q4 on a 6 GB card. Gramps Web sends up to about 5k tokens of tree context.
A larger window takes more VRAM: if `ollama ps` no longer shows `100% GPU`,
part of the model runs on the CPU and answers slow down a lot.

## Configuration

Copy `.env.example` to `.env`, fill it in and run `chmod 600 .env`.

| Variable | Default | Use |
| --- | --- | --- |
| `OLLAMA_BIND_ADDRESS` | required | Host address port 11434 is published on (see above) |
| `OLLAMA_DOMAIN` | required | Traefik host of Open WebUI |
| `WEBUI_SECRET_KEY` | required | Signs Open WebUI sessions; generate with `openssl rand -hex 32` |
| `OLLAMA_OLLAMA_DATA_DIR` | required | Host directory for Ollama data and pulled models |
| `OLLAMA_MODELS_DATA_DIR` | required | Host directory mounted at `/models` in both services |
| `OLLAMA_OPEN_WEBUI_DATA_DIR` | required | Host directory mounted at `/data` in Open WebUI |
| `OLLAMA_OPEN_WEBUI_BACKEND_DATA_DIR` | required | Open WebUI database and uploads |
| `OLLAMA_CONTEXT_LENGTH` | `8192` | Context window in tokens |
| `OLLAMA_KEEP_ALIVE` | `5m` | How long a model stays in VRAM after the last request |
| `NVIDIA_VISIBLE_DEVICES` | `all` | GPUs given to Ollama; empty would hide them |
| `NVIDIA_DRIVER_CAPABILITIES` | `compute,utility` | Driver features exposed to the container |
| `LOG_LEVEL` | `INFO` | Open WebUI log level |
| `MODEL_DOWNLOAD_DIR` | empty | Passed to Open WebUI as is |

`HOME_OLLAMA` is in `.env.example` but not used by the Compose file.

## Tests

`tests/test_stack.sh` renders the Compose file with test values and checks
the port binding, the internal Open WebUI URL, the context length, the GPU
defaults and the failure without each required variable. It needs Docker
Compose and `jq`.
