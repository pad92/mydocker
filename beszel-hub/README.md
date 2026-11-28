# Beszel hub (ns01)

The Beszel hub collects the metrics of the Beszel agents. It runs on ns01 so that it keeps working when chataigne is down. It reaches the agents by IP address, so moving it changed nothing on their side. The agent of chataigne keeps `HUB_URL=http://beszel.home.lan`, which Traefik forwards here. Traefik on chataigne serves it on `BESZEL_HOST_LOCAL`; see the "Services on ns01" section of [management](../management/README.md#services-on-ns01).

| Variable | Purpose | Example |
| --- | --- | --- |
| `BESZEL_BIND_ADDRESS` | Address of ns01 the web port listens on | `192.168.69.1` |
| `BESZEL_DATA_DIR` | Data directory (PocketBase database, hub SSH key) | `/volume1/docker/beszel` |

The hub SSH key lives in the data directory. Copy the whole directory when moving the hub, or every agent would reject the new key.

Port 8090 is reachable on the LAN; the hub has its own login.

The agent of chataigne stays in the [beszel](../beszel/README.md) stack.
