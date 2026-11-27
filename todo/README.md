# Todo Stack

This stack deploys the following services:

## 1. Donetick (`donetick`)

### Role
Task list and todo management dashboard.

### External Links
- **Official Project**: [https://github.com/donetick/donetick](https://github.com/donetick/donetick)
- **Docker Image Maintainer**: [Donetick Team](https://github.com/donetick)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `DT_ENV` | Configuration settings value for Dt env. | *None (empty)* |
| `DT_SQLITE_PATH` | Persistent host directory path for volume mount: DT_SQLITE_PATH. | *None (empty)* |
| `TODO_DOMAIN` | Traefik Host rule domain routing address (e.g., service.example.lan). | *None (empty)* |
| `TODO_DONETICK_DATA_DIR` | Persistent host directory path for volume mount: TODO_DONETICK_DATA_DIR. | *None (empty)* |

---


### Sign-in with Authentik (OpenID Connect)

Donetick has its own OAuth2 login. The stack points it at the `donetick`
application that the management blueprint creates in Authentik. The local
accounts keep working, and the Traefik router has no forward auth: the
mobile app and the external API (`/eapi`) talk to Donetick directly.

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `AUTHENTIK_DOMAIN` | Host name of Authentik (`AUTHENTIK_HOST_LOCAL` of the management stack). | *None (required)* |
| `DONETICK_OIDC_CLIENT_SECRET` | Client secret of the `Donetick` provider in Authentik. Set it in Portainer, never in Git. | *None (required)* |

Setup:

1. In the management stack, set `DONETICK_HOST_LOCAL` to the same value as
   `TODO_DOMAIN`. The blueprint builds the redirect URI
   `https://<TODO_DOMAIN>/auth/oauth2` from it; the mobile app uses
   `donetick://auth/oauth2`, which the provider also accepts.
2. In Authentik, open Applications > Providers > Donetick, copy the client
   secret into `DONETICK_OIDC_CLIENT_SECRET`, and redeploy this stack.
3. Add the people who may sign in to the `donetick-users` group. Authentik
   refuses everybody else.
4. Sign in once with "Authentik" before relying on it. Keep password login
   enabled (do not set `DT_DISABLE_PASSWORD_AUTH`): it is the way back in if
   Authentik is down.

Things to know:

- Donetick links an Authentik login to the local account with the same email
  address, and creates an account on the first login otherwise. It does not
  check `email_verified`, so only let users who cannot choose their own email
  address in Authentik into `donetick-users`.
- `DT_OAUTH2_ADMIN_GROUPS` and `DT_OAUTH2_MANAGER_GROUPS` stay unset on
  purpose. Once either is set, every Authentik login rewrites the user's
  circle role, and anyone outside those groups, the circle owner included,
  drops to member.
- Authentik's certificate comes from the internal CA. The host CA bundle is
  mounted read-only over the image's, so the token and userinfo calls trust it.
