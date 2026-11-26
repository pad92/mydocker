# OpenObserve exports (pending)

The OpenObserve stack has been replaced by the [victoria stack](../victoria/README.md). This directory only keeps the alert and dashboard exports that a later change will rewrite for VictoriaLogs and VictoriaMetrics:

| File | Content |
| :--- | :--- |
| `authentik/alerts_authentik.json` | Four Authentik alerts: failed login burst, sensitive event, errors, server or worker silent for 10 minutes. |
| `authentik/dashboard_authentik.json` | Dashboard *Sécurité — Authentik*. |
| `proxmox/alerts_proxmox.json` | Nine Proxmox VE alerts. |
| `proxmox/dashboard_proxmox.json` | Dashboard *Infrastructure — Proxmox*. |

Their queries use the OpenObserve SQL syntax and the field names that the victoria Vector pipeline still produces (`ak_*`, `pve_*`). Delete this directory once the rewrite is merged.
