#!/usr/bin/env bash
# Validates the inline Vector pipeline (configs.vector_config) as Compose renders
# it with .env.example, then runs the unit tests of tests/*_test.yaml against it.
# Needs Docker, Docker Compose 2.23+ and jq. Usage: ./tests/test_vector.sh
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
vector_version="$(sed -n 's/^VECTOR_VERSION=//p' "$stack_dir/.env.example")"
image="timberio/vector:${vector_version}-distroless-libc"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

# PUID/PGID are empty in .env.example but required by the compose file.
# "compose config" escapes every literal $ as $$ again in its output; the gsub
# gives back the file the container really receives.
PUID="${PUID:-1000}" PGID="${PGID:-1000}" docker compose \
  --project-directory "$stack_dir" --env-file "$stack_dir/.env.example" \
  config --format json | jq -er '.configs.vector_config.content | gsub("\\$\\$"; "$")' > "$work_dir/vector.yaml"
cp "$stack_dir"/tests/*_test.yaml "$work_dir/"
chmod -R a+rX "$work_dir"

# Dummy Free Mobile credentials: sms_test.yaml checks they reach the body.
run_vector() {
  docker run --rm --network none -e FREE_MOBILE_USER=test-user -e FREE_MOBILE_PASS=test-pass \
    -v "$work_dir:/cfg:ro" "$image" "$@"
}

# --no-environment: skips the checks that need the network (sink healthcheck,
# DNS of the victorialogs service).
run_vector validate --no-environment /cfg/vector.yaml
# The test files are merged with the pipeline: every test of every file runs.
tests=()
for file in "$work_dir"/*_test.yaml; do
  tests+=("/cfg/$(basename "$file")")
done
run_vector test /cfg/vector.yaml "${tests[@]}"
