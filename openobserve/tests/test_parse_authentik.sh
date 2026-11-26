#!/usr/bin/env bash
# Runs the OpenObserve function authentik/parse_authentik.vrl in a Vector remap
# transform against sample Authentik, outpost and PostgreSQL records.
# OpenObserve and Vector share the VRL language; the same image as
# test_vector.sh is used. Needs Docker. Usage: ./tests/test_parse_authentik.sh
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
vector_version="$(sed -n 's/^VECTOR_VERSION=//p' "$stack_dir/.env.example")"
image="timberio/vector:${vector_version}-distroless-libc"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

cp "$stack_dir/authentik/parse_authentik.vrl" "$stack_dir/tests/parse_authentik_test.yaml" "$work_dir/"
chmod -R a+rX "$work_dir"

docker run --rm --network none -v "$work_dir:/cfg:ro" "$image" \
  test /cfg/parse_authentik_test.yaml
