#!/bin/bash
# victoria/docker-compose.yml is generated from victoria/config/ by
# victoria/build.py. Fails the commit when the staged compose file differs from
# what build.py makes of the staged sources. It checks the index, not the
# working tree: a source staged without its regenerated compose file fails.
set -euo pipefail

git diff --cached --quiet -- victoria/ && exit 0

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git ls-files -z -- victoria/ | git checkout-index -z --stdin --prefix="$tmp/"
if ! python3 "$tmp/victoria/build.py" --check; then
  echo "pre-commit: run python3 victoria/build.py, then stage victoria/docker-compose.yml" >&2
  exit 1
fi
