# Changelog

## 2026-11-14

- Document that the runner declares the labels of `runner.labels` in
  `config.yaml` (the `runner-images` Ubuntu images), not those of
  `GITEA_RUNNER_LABELS`, which only applies at registration.

## 2026-10-22

- Align the database mount with the existing production PostgreSQL directory.
- Use the existing Gitea database variables for both services and reject missing
  required settings during Compose validation.
- Wait for PostgreSQL readiness and advertise SSH port 2222.
- Restore the production runner configuration path, CA mount, name and labels.
- Preserve production image references and restart policies. Document the
  remaining runner isolation and image pinning work separately.
