# Minio Stack

This stack deploys the following services:

## 1. MinIO (`s3`)

### Role
High-performance Amazon S3-compatible object storage server.

### External Links
- **Official Project**: [https://min.io/](https://min.io/)
- **Docker Image Maintainer**: [MinIO](https://hub.docker.com/r/minio/minio)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `MINIO_ACCESS_KEY` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `MINIO_S3_DATA_DIR` | Persistent host directory path for volume mount: MINIO_S3_DATA_DIR. | *None (empty)* |
| `MINIO_SECRET_KEY` | Secret authentication credentials, token, or key value. | `CHANGEME` |

---

