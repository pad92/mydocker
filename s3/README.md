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
| `RUSTFS_DATA_DIR` | Host directory mounted at `/data`. | *None (empty)* |
| `RUSTFS_UID` | Runtime user ID used by RustFS for mounted data. | `10001` |
| `RUSTFS_GID` | Runtime group ID used by RustFS for mounted data. | `10001` |

Set `RUSTFS_DATA_DIR` to the host data directory. The stack mounts it at `/data`.
RustFS uses UID/GID `10001` by default; change them if the host directory needs
a different ownership mapping.

Traefik routes the S3 API and web console using `RUSTFS_S3_HOST` and
`RUSTFS_CONSOLE_HOST`, on ports `9000` and `9001`. Set both hostnames in the
stack environment and point their DNS records at Traefik. Its external Docker
network `traefik_gateway` must already exist. The service ports are not
published directly on the Docker host.

## Migrate MinIO to RustFS with Portainer

This procedure covers a single-node MinIO stack on Docker Standalone. RustFS
can reuse its data directory, but some MinIO settings need separate migration.
See the [RustFS migration notes](https://rustfs.com/blog/binary-replacement-a-simple-way-to-migrate-from-minio-to-rustfs/).
Do not use this procedure for Swarm or multi-disk deployments. Never run both
servers against the same directory.

### 1. Record and check the data path

In Portainer, open **Stacks**, select MinIO, inspect its container mounts, and
record the host **Source** for MinIO's data directory. Use that path for
`RUSTFS_DATA_DIR` in the RustFS stack.

On the Docker host, check the local Compose file:

```sh
cd /path/to/mydocker/s3
docker compose config --quiet
docker compose config --format json | jq -r '.services.s3.volumes[] | select(.target == "/data") | .source'
```

`cd` selects this stack directory. `docker compose config --quiet` validates
the file without printing environment values; the `jq` command prints the
host path mounted at `/data`. Confirm it matches MinIO's path. In Portainer,
set `RUSTFS_DATA_DIR` to `/volume1/docker/s3/`, enter the RustFS credentials,
and set `RUSTFS_S3_HOST` and `RUSTFS_CONSOLE_HOST` to the two DNS names used for
Traefik. Do not share the full Compose output; it may contain secrets.

### 2. Stop writes and make an offline backup

Pause applications that write to S3, then stop the MinIO stack in Portainer.
Wait for its container to stop before copying data. On the Docker host, archive
the data directory to a different disk. The example matches
`/volume1/docker/s3/`; replace the backup path with a location on another disk:

```sh
sudo tar -cpf /path/to/backup/minio-s3-before-rustfs.tar -C /volume1/docker s3
sudo tar -tf /path/to/backup/minio-s3-before-rustfs.tar >/dev/null
```

The first command archives the stopped MinIO data tree while preserving file
ownership in the archive. The second reads the archive and fails if it cannot
be listed. Keep this backup unchanged until migration verification is complete.
If there is not enough space for a separate backup, stop here and arrange one
before deploying RustFS.

### 3. Deploy RustFS

Update the stack through Portainer:

- **Git stack:** point the stack to `s3/docker-compose.yml` in this repository,
  then choose **Pull and redeploy** and enable **Re-pull image**. If Portainer
  does not let you change the Compose path, update the file configured for that
  stack in the repository to match this RustFS Compose file.
- **Web Editor or uploaded stack:** replace its Compose file with this
  directory's `docker-compose.yml`, set the environment variables, and choose
  **Update the stack** with image pulling enabled.

Git stack files must be changed in the repository. Portainer's stack variables
are separate from this checkout's `.env` file. Keep the old MinIO Compose file
available for rollback. Keep `RUSTFS_DATA_DIR` set to `/volume1/docker/s3/`
and confirm the external `traefik_gateway` network exists before redeploying.

### 4. Verify the migration

In Portainer, confirm the `s3` container is running and check its **Logs**. Or
run these commands on the Docker host:

```sh
docker ps --filter name=s3
docker logs --tail=100 s3
```

The first lists the RustFS container; the second shows its latest logs. Check
for startup or permission errors before resuming writes. Check the S3 API and
web console at the hostnames configured in `RUSTFS_S3_HOST` and
`RUSTFS_CONSOLE_HOST`.

If `mc` is installed, check that RustFS can list the buckets:

```sh
mc alias set rustfs-new http://S3_HOST:9000 ACCESS_KEY SECRET_KEY
mc ls rustfs-new
```

The first command saves a local alias; replace the host and credential
placeholders. The second should list the expected buckets. Check sample objects
and the applications that use them. Avoid putting real credentials in shared
shell history. Once these checks pass, resume the applications paused above.

### 5. Roll back before resuming writes

If verification fails, keep applications paused and stop RustFS in Portainer.
Do not start MinIO against the directory RustFS has opened. On the Docker host,
move that directory aside, then restore the original backup:

```sh
sudo mv /volume1/docker/s3 /volume1/docker/s3-rustfs-failed-migration
sudo tar -xpf /path/to/backup/minio-s3-before-rustfs.tar -C /volume1/docker
```

The first command preserves RustFS's current files for investigation; make sure
`/volume1/docker/s3-rustfs-failed-migration` does not already exist. The second
restores the archived `s3` directory. After the restore completes, restore the
old MinIO Compose configuration in Portainer and redeploy/start that stack.
Verify MinIO before allowing applications to write again.

This rollback restores the pre-migration state and therefore discards any
writes made by RustFS. If applications have already written to RustFS, preserve
and reconcile those objects separately before restoring the MinIO backup.

---
