# Grafana Stack

This stack deploys the following services:

## 1. Prometheus (`prometheus`)

### Role
Time-series monitoring metrics scraping database.

### External Links
- **Official Project**: [https://prometheus.io/](https://prometheus.io/)
- **Docker Image Maintainer**: [Prometheus Team](https://hub.docker.com/r/prom/prometheus)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `GRAFANA_PROMETHEUS_DATA_DIR` | Persistent host directory path for volume mount: GRAFANA_PROMETHEUS_DATA_DIR. | *None (empty)* |

---

## 2. Grafana (`grafana`)

### Role
Service container running grafana/grafana-oss.

### External Links
- **Official Project**: [https://hub.docker.com/r/grafana/grafana-oss](https://hub.docker.com/r/grafana/grafana-oss)
- **Docker Image Maintainer**: [Official Hub Registry](https://hub.docker.com/r/grafana/grafana-oss)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `GF_SECURITY_ADMIN_PASSWORD` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `GF_SECURITY_ADMIN_USER` | Configuration settings value for Gf security admin user. | *None (empty)* |
| `GRAFANA_GRAFANA_DATA_DIR` | Persistent host directory path for volume mount: GRAFANA_GRAFANA_DATA_DIR. | *None (empty)* |

---

