# RustFS Stack

This stack deploys the following services:

## 1. RustFS (`s3`)

### Role
High-performance, S3-compatible object storage server written in Rust.

### External Links
- **Official Project**: [https://rustfs.com/](https://rustfs.com/)
- **Documentation**: [https://docs.rustfs.com/](https://docs.rustfs.com/)
- **Docker Image Maintainer**: [RustFS](https://hub.docker.com/r/rustfs/rustfs)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `MINIO_ACCESS_KEY` | Existing access key, mapped to RustFS `RUSTFS_ACCESS_KEY`. | `CHANGEME` |
| `MINIO_S3_DATA_DIR` | Persistent host directory path for volume mount: MINIO_S3_DATA_DIR. | *None (empty)* |
| `MINIO_SECRET_KEY` | Existing secret key, mapped to RustFS `RUSTFS_SECRET_KEY`. | `CHANGEME` |

The existing `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY`, and `MINIO_S3_DATA_DIR`
variables are intentionally preserved for migration compatibility. The host
data directory is mounted at `/data`, so the existing objects remain available
after switching the stack from MinIO to RustFS. RustFS's canonical credential
variables are populated from these existing variables at container startup.

---
