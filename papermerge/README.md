# Papermerge Stack

This stack deploys the Papermerge document management system.

## Services

### 1. Web App (`papermerge`)
- Image: `papermerge/papermerge:3.5.3`
- Role: Main application UI and FastAPI backend.

### 2. Worker (`worker`)
- Image: `papermerge/papermerge:3.5.3` (running as `worker`)
- Role: Background task queue for CPU-intensive document processing and OCR.

### 3. Database (`db`)
- Image: `postgres:17-alpine`
- Role: Main persistence database for application state.

### 4. Broker (`redis`)
- Image: `redis:7-alpine`
- Role: Redis broker/message queue for Celery.

---

## Configuration Variables

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `PAPERMERGE_DOMAIN` | Target Traefik domain address. | `papermerge.home.lan` |
| `PAPERMERGE_SECRET_KEY` | Django/FastAPI security key. | *(Required)* |
| `PAPERMERGE_ADMIN_USER` | Initial administrative username. | `admin` |
| `PAPERMERGE_ADMIN_PASSWORD` | Initial administrative user password. | *(Required)* |
| `PAPERMERGE_MEDIA_DATA_DIR` | Persistent path on host for documents. | `/rpool/docker/papermerge/media` |
| `PAPERMERGE_DB_DATA_DIR` | Persistent path on host for Postgres data. | `/rpool/docker/papermerge/db` |
| `POSTGRES_DB` | Postgres database name. | `papermerge` |
| `POSTGRES_USER` | Postgres username. | `papermerge` |
| `POSTGRES_PASSWORD` | Postgres password. | *(Required)* |

---

## Secret and Password Generation

You can generate strong, secure random values for `PAPERMERGE_SECRET_KEY`, `PAPERMERGE_ADMIN_PASSWORD`, and `POSTGRES_PASSWORD` using any of the following commands in your terminal:

### Option A: Using OpenSSL (Standard on Linux)
```bash
openssl rand -hex 32
```

### Option B: Using Python (Cross-platform)
```bash
python3 -c "import secrets; print(secrets.token_hex(32))"
```

### Option C: Using `/dev/urandom`
```bash
tr -dc 'A-Za-z0-9!?%=' </dev/urandom | head -c 32; echo ""
```
