# Ollama

This stack runs [Ollama](https://ollama.com/) on the NVIDIA GPU of the host,
and [Open WebUI](https://github.com/open-webui/open-webui) in front of it
behind Traefik. Other stacks, such as Gramps Web, also call the Ollama API.

| Service | Image | Role |
| --- | --- | --- |
| `ollama` | `docker.io/ollama/ollama:0.24.0` | Model runtime and API (port 11434) |
| `open-webui` | `ghcr.io/open-webui/open-webui:v0.13.5` | Chat interface (port 8080, through Traefik) |

Traefik serves Open WebUI on `https://${OLLAMA_DOMAIN}` (entrypoint
`websecure`, certificate from `stepca`) and redirects plain HTTP to it.

## GPU and versions

Ollama gets the GPU from the `deploy.resources` device reservation, through
the NVIDIA Container Toolkit; the image sets the `NVIDIA_*` variables itself.

Both images are pinned, and Watchtower only pulls a newer build of the same
tag. The GTX 1060 is a Pascal card (compute capability 6.1) with driver 550
(CUDA 12.4).

Ollama is held at `0.24.0`, the last release that uses this card with
driver 550. From `0.30.0`, Ollama wants driver 570 or newer. With an older
driver it does not fail: it logs `NVIDIA driver too old` and runs every
model on the CPU. Tested on the host in November 2026:

| Ollama | Result with driver 550 |
| --- | --- |
| `0.22.1`, `0.24.0` | GPU (`library=CUDA`) |
| `0.30.0` to `0.40.18` | CPU, `required_driver="570 or newer"` |

With `0.24.0`, `qwen2.5:7b` and an 8192-token context, `ollama ps` shows
`100% GPU`, 29 of 29 layers offloaded and about 5 GB of VRAM used.

A newer Ollama needs a newer driver first. Driver 580 is the last branch
that supports Pascal cards, and nothing says the Ollama CUDA build of that
time still runs on compute capability 6.1. To upgrade, set
`OLLAMA_VERSION`, redeploy, load a model, then check that
`docker logs ollama` shows `inference compute` with `library=CUDA` and that
`ollama ps` shows `100% GPU`. Go back to `0.24.0` otherwise.

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

## Sign-in through Authentik

Open WebUI signs users in through Authentik with OpenID Connect. The
*Open WebUI* provider, its application and the groups `open-webui-admins`
and `open-webui-users` come from the management blueprint
`20-forward-auth-apps.yaml`. Only the web interface is concerned: the Ollama
API on port 11434 does not go through Traefik or Authentik, and Immich,
Gramps Web and the other clients keep calling it as before.

The role is set from the Authentik groups at each sign-in:
`open-webui-admins` gives admin, `open-webui-users` gives user. A user in
neither group gets a 403, and a role changed in Open WebUI is overwritten at
the next sign-in: change the group in Authentik instead. The first Authentik
sign-in creates the Open WebUI account, or attaches it to the local account
that has the same e-mail address, with its chats and settings.

Be careful with the existing admin account: if its owner signs in through
Authentik without being in `open-webui-admins`, the account becomes a plain
user. Add that person to the group before the first sign-in.

Setup:

1. Set `OLLAMA_HOST_LOCAL` in the `.env` of the `management` stack to the
   value of `OLLAMA_DOMAIN`, then redeploy it. The redirect URI
   `https://<OLLAMA_DOMAIN>/oauth/oidc/login/callback` is built from it.
2. In Authentik, add the admin to `open-webui-admins` and the other users
   to `open-webui-users` (Directory > Groups).
3. Copy the client secret of the *Open WebUI* provider (Applications >
   Providers) into `OPEN_WEBUI_OIDC_CLIENT_SECRET`, and the Authentik host
   into `AUTHENTIK_DOMAIN`, in the Portainer stack variables. The stack does
   not deploy while either is empty.
4. Redeploy this stack, open `https://<OLLAMA_DOMAIN>` and use
   *Continue with Authentik*.

The local login form stays available as a fallback. Once the Authentik
sign-in works for the admin, it can be turned off from the admin settings
(`ENABLE_LOGIN_FORM`). That setting is kept in the Open WebUI database, not in
the Compose file.

Why OpenID Connect and not the Authentik forward auth of the other stacks:
Open WebUI would have to trust a user header set by the proxy, and any
container on `traefik_gateway` could send it directly. Forward auth would
also block the Open WebUI API keys, which carry no Authentik session.

Authentik uses a certificate of the internal CA: the host bundle
`/etc/ssl/certs/ca-certificates.crt` is mounted read-only, and
`SSL_CERT_FILE`, `AIOHTTP_CLIENT_SSL_CERT_FILE` and `REQUESTS_CA_BUNDLE`
point at it, so the host must trust that CA.

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
| `AUTHENTIK_DOMAIN` | required | Authentik host, for the OpenID Connect discovery URL |
| `OPEN_WEBUI_OIDC_CLIENT_SECRET` | required | Client secret of the *Open WebUI* provider in Authentik |
| `OLLAMA_OLLAMA_DATA_DIR` | required | Host directory for Ollama data and pulled models |
| `OLLAMA_OPEN_WEBUI_BACKEND_DATA_DIR` | required | Open WebUI database and uploads |
| `OLLAMA_VERSION` | `0.24.0` | Ollama image tag (see GPU and versions) |
| `OPEN_WEBUI_VERSION` | `v0.13.5` | Open WebUI image tag |
| `OLLAMA_CONTEXT_LENGTH` | `8192` | Context window in tokens |
| `OLLAMA_KEEP_ALIVE` | `5m` | How long a model stays in VRAM after the last request |
| `LOG_LEVEL` | `INFO` | Open WebUI log level |

Older versions of the stack also mounted `OLLAMA_MODELS_DATA_DIR` at `/models`
and `OLLAMA_OPEN_WEBUI_DATA_DIR` at `/data`. Neither service read them: the
variables can go from Portainer, and the host directories can be removed
once checked to be empty.

## Tests

`tests/test_stack.sh` renders the Compose file with test values and checks
the port binding, the internal Open WebUI URL, the Authentik sign-in
settings (OIDC, roles, CA bundle, no forward auth, nothing on the Ollama
service), the context length, the GPU reservation, the pinned images, the
mounts, the Traefik routers and the failure without each required variable.
The blueprint side is checked by `management/tests/test_blueprints.sh`. It needs Docker
Compose and `jq`.
