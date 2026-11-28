# Uptime Kuma (ns01)

Uptime Kuma monitors the hosts and services of the network. It runs on ns01 so that it keeps alerting when chataigne is down. Traefik on chataigne serves it on `UPTIME_HOST_LOCAL` behind Authentik; see the "Services on ns01" section of [management](../management/README.md#services-on-ns01).

| Variable | Purpose | Example |
| --- | --- | --- |
| `UPTIME_KUMA_BIND_ADDRESS` | Address of ns01 the web port listens on | `192.168.69.1` |
| `UPTIME_KUMA_DATA_DIR` | Data directory (SQLite database, uploads) | `/volume1/docker/uptime-kuma` |
| `UPTIME_KUMA_CA_CERTIFICATES_DIR` | Host directory holding the step-ca root certificate | `/usr/local/share/ca-certificates` |
| `CA_CERT_NAME` | File name of that certificate, given to `NODE_EXTRA_CA_CERTS` | `home-lan-root-ca.crt` |

Port 3001 is reachable on the LAN without Authentik, so keep the built-in login of Uptime Kuma enabled (*Settings > Security*). Do not turn on "Disable Auth".

The Docker monitors of chataigne go through the read-only socket proxy of the management stack: Docker host type *TCP / HTTP*, URL `https://<DOCKER_PROXY_HOST_LOCAL>`. The container has no Docker socket of its own.

Check the configuration with:

```bash
docker compose --env-file .env.example config --quiet
```
