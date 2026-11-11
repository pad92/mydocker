#!/usr/bin/env bash
# Validates the inline Vector pipeline (configs.vector_config) as Compose renders
# it with .env.example, then runs the unit tests of vector_test.yaml against it.
# Needs Docker, Docker Compose 2.23+ and jq. Usage: ./tests/test_vector.sh
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
vector_version="$(sed -n 's/^VECTOR_VERSION=//p' "$stack_dir/.env.example")"
image="timberio/vector:${vector_version}-distroless-libc"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

# PUID/PGID are empty in .env.example but required by the compose file.
PUID="${PUID:-1000}" PGID="${PGID:-1000}" docker compose \
  --project-directory "$stack_dir" --env-file "$stack_dir/.env.example" \
  config --format json | jq -er '.configs.vector_config.content' > "$work_dir/vector.yaml"
cp "$stack_dir/tests/vector_test.yaml" "$work_dir/"
# The pipeline reads its credentials from /run/secrets: give it dummy ones.
mkdir "$work_dir/secrets"
printf 'test' > "$work_dir/secrets/openobserve_ingest_user"
printf 'test' > "$work_dir/secrets/openobserve_ingest_password"
chmod -R a+rX "$work_dir"

run_vector() {
  docker run --rm --network none \
    -v "$work_dir:/cfg:ro" -v "$work_dir/secrets:/run/secrets:ro" \
    "$image" "$@"
}

# --no-environment: skips the checks that need the network (sink healthcheck,
# DNS of the openobserve service).
run_vector validate --no-environment /cfg/vector.yaml
run_vector test /cfg/vector.yaml /cfg/vector_test.yaml
