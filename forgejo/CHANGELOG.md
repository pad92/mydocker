# Changelog

## 2026-11-20

- Disable self-registration (`DISABLE_REGISTRATION=true`); it was open.
- Default `FORGEJO_VERSION` to 17, the version of the production database,
  instead of 15, which cannot start on it.
- Add HSTS and `X-Content-Type-Options: nosniff` on the HTTPS router.
- Update `.env.example` to the final domain and SSH port.
- `tests/test_stack.sh` submits the sign-up form and checks that no account
  is created, and checks the default image tag and the Traefik headers. It
  sets `ALLOW_UNENCRYPTED=true` for its own Forgejo, since Forgejo 17 refuses
  to migrate from an `http://` source and the throwaway Gitea has no
  certificate.
- Start the Git LFS server (`LFS_START_SERVER=true`). It was off, so the
  repositories migrated from Gitea lost their LFS objects without an error.
  A repository migrated before this change must be migrated again.
- `tests/test_stack.sh` migrates a repository holding an LFS object and checks
  that Forgejo serves it.

## 2026-11-14

- The Forgejo image tag comes from `FORGEJO_VERSION` (default `15`), the
  runner image tag from `FORGEJO_RUNNER_VERSION` (default `13`).
- The runner example config follows the Gitea runner's `config.yaml`: its
  `runner-images` labels, jobs on the stack network, the host's `docker.sock`
  mounted into jobs and the job image pulled every time. Workflows on
  `debian-latest` need another label.
- The stack network is named `forgejo_forgejo` whatever the Compose project
  name, since the runner puts the job containers on it.

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
