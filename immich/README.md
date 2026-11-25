# Immich Stack

This stack deploys the following services:

## Common Configuration Variables
These environment variables are shared and used by multiple services in this stack:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `PUBLIC_BASE_URL` | Configuration settings value for Public base url. | *None (empty)* |

---

## 1. Immich-server (`immich-server`)

### Role
Service container running ghcr.io/immich-app/immich-server:${IMMICH_VERSION.

### External Links
- **Official Project**: [https://hub.docker.com/r/ghcr.io/immich-app/immich-server:${IMMICH_VERSION](https://hub.docker.com/r/ghcr.io/immich-app/immich-server:${IMMICH_VERSION)
- **Docker Image Maintainer**: [Official Hub Registry](https://hub.docker.com/r/ghcr.io/immich-app/immich-server:${IMMICH_VERSION)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `DB_DATABASE_NAME` | Configuration settings value for Db database name. | *None (empty)* |
| `DB_PASSWORD` | Secret authentication credentials, token, or key value. | `CHANGEME` |
| `DB_USERNAME` | Configuration settings value for Db username. | *None (empty)* |
| `IMMICH_VERSION` | Configuration settings value for Immich version. | `release` |
| `TRAEFIK_HOST_LOCAL` | Internal domain routing host rule (e.g. local.example.lan). | *None (empty)* |
| `UPLOAD_LOCATION` | Configuration settings value for Upload location. | *None (empty)* |

---

## 2. Immich-public-proxy (`immich-public-proxy`)

### Role
Service container running alangrainger/immich-public-proxy.

### External Links
- **Official Project**: [https://hub.docker.com/r/alangrainger/immich-public-proxy](https://hub.docker.com/r/alangrainger/immich-public-proxy)
- **Docker Image Maintainer**: [Official Hub Registry](https://hub.docker.com/r/alangrainger/immich-public-proxy)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `IMMICH_URL` | Configuration settings value for Immich url. | *None (empty)* |
| `TRAEFIK_HOST_PUBLIC` | External domain routing host rule (e.g. pub.domain.com). | *None (empty)* |

---

## Global / Other Variables
The following variables are defined in `.env.example` but are either global configs or not directly referenced in the compose services:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `DB_DATA_LOCATION` | Configuration settings value for Db data location. | *None (empty)* |
| `DB_STORAGE_TYPE` | Configuration settings value for Db storage type. | *None (empty)* |
| `NFS_SERVER_IP` | Network IP address configuration. | *None (empty)* |
| `PHOTO_NAS_NATH_PATH` | Persistent host directory path for volume mount: PHOTO_NAS_NATH_PATH. | *None (empty)* |
| `PHOTO_NAS_PASCAL_PATH` | Persistent host directory path for volume mount: PHOTO_NAS_PASCAL_PATH. | *None (empty)* |
| `PHOTO_NAS_PATH` | Persistent host directory path for volume mount: PHOTO_NAS_PATH. | *None (empty)* |
| `POSTGRES_INITDB_ARGS` | Configuration settings value for Postgres initdb args. | *None (empty)* |


---

## Sign-in with Authentik

Immich signs users in with OAuth (OpenID Connect) against the `immich`
application that the blueprint of the `management` stack creates. The
login page shows an "Authentik" button; the local login stays on, so the
admin account keeps working when Authentik is down. Traefik applies no
forward auth to this host: the mobile app, the OAuth callback and the
public proxy must reach Immich directly.

Only members of the Authentik group `immich-users` can sign in. Immich
creates the account at the first sign-in (auto register), with the
Authentik username as storage label.

Setup:

1. Set `IMMICH_HOST_LOCAL` in the `.env` of the `management` stack to the
   value of `TRAEFIK_HOST_LOCAL`, then redeploy it:
   `docker compose up -d authentik_worker`, then
   `docker compose exec authentik_worker ak apply_blueprint custom/20-forward-auth-apps.yaml`.
   The redirect URIs `app.immich:///oauth-callback`,
   `https://<TRAEFIK_HOST_LOCAL>/auth/login` and
   `https://<TRAEFIK_HOST_LOCAL>/user-settings` are built from it.
2. Add the users to `immich-users` (Directory > Groups).
3. Redeploy this stack (it adds `NODE_EXTRA_CA_CERTS`, see below).
4. In Immich, Administration > Settings > Authentication Settings > OAuth:

   | Setting | Value |
   | --- | --- |
   | Issuer URL | `https://<Authentik host>/application/o/immich/` |
   | Client ID | `immich` |
   | Client secret | copied from the *Immich* provider in Authentik (Applications > Providers) |
   | Scope | `openid email profile` |
   | ID token signed response algorithm | `RS256` |
   | Storage label claim | `preferred_username` |
   | Button text | `Authentik` |
   | Auto register | on |
   | Auto launch | off, so the local login stays reachable |

   `<Authentik host>` is `AUTHENTIK_HOST_PUBLIC` of the management stack
   when set, else `AUTHENTIK_HOST_LOCAL`.

The settings live in the Immich database, not in this repository: an
Immich config file (`IMMICH_CONFIG_FILE`) would lock every setting of the
admin UI, and the client secret would have to be in a file on the host.

Link every existing local account before its first Authentik sign-in:
sign in locally, then Account Settings > OAuth (`/user-settings`) > Link
to OAuth. Immich then finds the account by its Authentik ID. Otherwise,
when Immich does not recognise the account (here the Authentik and
Immich e-mails differed), auto register tries to create a new one with
the Authentik username as storage label. That label already belongs to
the existing account, so the sign-in fails with "Failed to finish
oauth", and the server log shows `duplicate key value violates unique
constraint "user_storageLabel_uq"`. Do not clear the storage label claim
to get past it: that creates a second, empty account.

Authentik uses a certificate of the internal CA, and Node trusts only the
roots it ships. `NODE_EXTRA_CA_CERTS` adds the host bundle
`/etc/ssl/certs/ca-certificates.crt`, mounted read-only, so the host must
trust that CA. If saving the OAuth settings or signing in fails with
"fetch failed" or "unable to get local issuer certificate", check that
bundle first.

`tests/test_stack.sh` renders the Compose file with test values and
checks this configuration (CA variable, read-only bundle mount, no forward
auth on the router). It needs Docker Compose and `jq`.
