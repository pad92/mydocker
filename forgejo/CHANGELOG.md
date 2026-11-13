# Changelog

## 2026-11-13

- Add the Forgejo 15 (LTS) stack with PostgreSQL 17 and Forgejo Runner 13,
  behind Traefik, to replace Gitea. The web installer is disabled.
- Add `migrate_repos.py` to import the Gitea repositories through Forgejo's
  migration tool, since Forgejo cannot reuse the data of Gitea 28.
- Document the import, the switch to the production domain and the rollback.
