# Management Stack

This stack runs Traefik, Portainer, and Uptime Kuma.

## Shared settings

| Variable | Purpose | Default |
| --- | --- | --- |
| `CA_CERT_NAME` | CA certificate filename mounted into Traefik and Uptime Kuma | `home-lan-root-ca.crt` |
| `MANAGEMENT_SHARE_CA_CERTIFICATES_DATA_DIR` | Host directory containing the CA certificate | `/usr/local/share/ca-certificates` |

## Traefik

Traefik routes HTTP and HTTPS traffic for the other Docker stacks. Its ACME resolver uses the step-ca endpoint and email configured by `ACME_CA_SERVER` and `ACME_EMAIL`. The dashboard host is set by `TRAEFIK_HOST_LOCAL`.

The active dynamic configuration is `traefik_dynamic.toml`. Start from `traefik_dynamic.toml.example` and keep host-specific addresses and authentication data in the ignored active file.

## Portainer

Portainer manages the Docker environment. Set `MANAGEMENT_PORTAINER_DATA_DIR` to its existing data directory and `PORTAINER_HOST_LOCAL` to its host name.

## Uptime Kuma

Uptime Kuma monitors hosts and services. Set `MANAGEMENT_UPTIME_KUMA_DATA_DIR` to its existing data directory and `UPTIME_HOST_LOCAL` to its host name.

## Other example settings

The `.env.example` file also contains host names and settings for optional services kept commented out in the Compose file, including Homarr, Homepage, and the mirror.
