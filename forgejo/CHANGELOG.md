# Changelog

## 2026-11-14

- The Forgejo image tag comes from `FORGEJO_VERSION` (default `15`), the
  runner image tag from `FORGEJO_RUNNER_VERSION` (default `13`).

## 2026-11-13

- Add the Forgejo 15 (LTS) stack with PostgreSQL 17 and Forgejo Runner 13,
  behind Traefik, to replace Gitea. The web installer is disabled.
- Add `migrate_repos.py` to import the Gitea repositories through Forgejo's
  migration tool, since Forgejo cannot reuse the data of Gitea 28.
- Document the import, the switch to the production domain and the rollback.
- `migrate_repos.py` creates the missing owners itself: organisations as in
  Gitea, user accounts with the same name and email and a random password to
  reset. The `--create-orgs` option is gone.
- `migrate_repos.py --insecure` skips the TLS certificate check of the Forgejo
  target only, for a temporary self-signed certificate. A warning is printed.
