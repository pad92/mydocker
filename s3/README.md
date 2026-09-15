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
| `RUSTFS_ACCESS_KEY` | Root access key used by RustFS. | `CHANGEME` |
| `RUSTFS_SECRET_KEY` | Root secret key used by RustFS. | `CHANGEME` |
| `RUSTFS_UID` | Runtime user ID used by RustFS for mounted data. | `10001` |
| `RUSTFS_GID` | Runtime group ID used by RustFS for mounted data. | `10001` |
| `MINIO_S3_DATA_DIR` | Persistent host directory path for volume mount: MINIO_S3_DATA_DIR. | *None (empty)* |
| `MINIO_ACCESS_KEY` | Legacy access key, used only when `RUSTFS_ACCESS_KEY` is unset. | `CHANGEME` |
| `MINIO_SECRET_KEY` | Existing secret key, mapped to RustFS `RUSTFS_SECRET_KEY`. | `CHANGEME` |

The existing `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY`, and `MINIO_S3_DATA_DIR`
variables are intentionally preserved for migration compatibility. The host
data directory is mounted at `/data`, so the existing objects remain available
after switching the stack from MinIO to RustFS. RustFS uses UID/GID `10001` by
default; change `RUSTFS_UID` and `RUSTFS_GID` when the host-mounted directory
requires a different ownership mapping. The legacy credential variables are
used as a fallback when the canonical RustFS variables are not set.

---
