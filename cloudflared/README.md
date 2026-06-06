# Cloudflared Stack

This stack deploys the following services:

## 1. Cloudflare Tunnel (`cloudflare-tunnel`)

### Role
Secure routing tunnel connecting local resources to Cloudflare CDN edge network.

### External Links
- **Official Project**: [https://github.com/cloudflare/cloudflared](https://github.com/cloudflare/cloudflared)
- **Docker Image Maintainer**: [Cloudflare](https://hub.docker.com/r/cloudflare/cloudflared)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `CA_CERT_PATH` | Persistent host directory path for volume mount: CA_CERT_PATH. | *None (empty)* |
| `CLOUDFLARE_TUNNEL_TOKEN` | Cloudflare Tunnel routing token identifier. | `CHANGEME` |
| `DNS_SERVER_1` | Configuration settings value for Dns server 1. | *None (empty)* |
| `DNS_SERVER_2` | Configuration settings value for Dns server 2. | *None (empty)* |

---

