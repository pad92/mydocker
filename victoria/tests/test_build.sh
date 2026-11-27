#!/usr/bin/env bash
# Test of build.py, the generator of the content: blocks of docker-compose.yml,
# and of the pre-commit check that keeps them in step with config/.
#   1. docker-compose.yml is up to date with config/.
#   2. Compose renders each config to its source: docker compose config, with
#      .env.example, gives back the source text with only the listed
#      ${VAR} interpolated (independent of the escaping code of build.py).
#   3. Mutations on a copy: an edited source makes --check fail; a $, an
#      unknown ${VAR}, an interpolation in the wrong config, a missing source
#      or an unmapped config each give the expected result.
#   4. The pre-commit check in a throwaway git repository: it reads the index,
#      so a source staged without its regenerated compose file is refused.
# Needs python3, Docker Compose 2.23+ and git; no container is started.
# Usage: ./tests/test_build.sh
# The $ in single quotes are the test data: they must not expand.
# shellcheck disable=SC2016
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_dir="$(cd "$stack_dir/.." && pwd)"
env_file="$stack_dir/.env.example"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

# Copy of the generator, its sources and the compose file, for mutations.
fresh_copy() {
  rm -rf "$work_dir/stack"
  mkdir -p "$work_dir/stack"
  cp -r "$stack_dir/build.py" "$stack_dir/docker-compose.yml" "$stack_dir/config" "$work_dir/stack/"
}
build() { python3 "$work_dir/stack/build.py" "$@"; }
expect_rc() {
  local want="$1" label="$2" rc=0
  shift 2
  "$@" >"$work_dir/out" 2>&1 || rc=$?
  [[ "$rc" == "$want" ]] || { cat "$work_dir/out" >&2; fail "$label: exit $rc, expected $want"; }
}

# 1. Committed compose file matches the sources.
python3 "$stack_dir/build.py" --check || fail "docker-compose.yml is out of date: run python3 build.py"
pass "docker-compose.yml is up to date with config/"

# 2. Compose renders each config to its source.
export PUID=1000 PGID=1000 VECTOR_WEBHOOK_PASSWORD=0123456789abcdef
docker compose --project-directory "$stack_dir" --env-file "$env_file" \
  config --format json > "$work_dir/compose.json"
python3 - "$stack_dir" "$work_dir/compose.json" "$env_file" <<'PY'
import json, os, re, sys
from pathlib import Path

stack, rendered, env_file = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
sys.path.insert(0, str(stack))
import build  # noqa: E402

env = dict(line.split("=", 1) for line in Path(env_file).read_text().splitlines()
           if line and not line.startswith("#") and "=" in line)
env.update({k: os.environ[k] for k in ("PUID", "PGID", "VECTOR_WEBHOOK_PASSWORD")})
configs = json.load(open(rendered))["configs"]
assert set(configs) == set(build.SOURCES), sorted(set(configs) ^ set(build.SOURCES))
interp = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?::[-?][^}]*)?\}")
used = set()
for name, rel in build.SOURCES.items():
    source = (stack / "config" / rel).read_text()
    allowed = build.INTERPOLATED.get(name, frozenset())

    def value(m: re.Match[str]) -> str:
        if m.group(1) not in allowed:
            return m.group(0)
        used.add((name, m.group(1)))
        return env.get(m.group(1), "")

    expected = interp.sub(value, source)
    # docker compose config writes a literal $ as $$ again.
    got = configs[name]["content"].replace("$$", "$")
    if got != expected:
        for i, (a, b) in enumerate(zip(got.splitlines(), expected.splitlines())):
            if a != b:
                sys.exit(f"{name} line {i + 1}:\n  compose: {a}\n  source:  {b}")
        sys.exit(f"{name}: length differs")
listed = {(n, v) for n, vs in build.INTERPOLATED.items() for v in vs}
assert used == listed, f"listed but not used: {sorted(listed - used)}"
PY
pass "Compose renders the 25 configs to their sources, interpolations included"

# 3. Mutations.
dash="$work_dir/stack/config/grafana/dashboards/hosts.json"

fresh_copy
sed -i 's/"uid": "victoria-hosts"/"uid": "victoria-hosts-mutated"/' "$dash"
grep -q 'victoria-hosts-mutated' "$dash" || fail "mutation not applied"
expect_rc 1 "--check after a source edit" build --check
expect_rc 0 "build after a source edit" build
grep -q '"uid": "victoria-hosts-mutated"' "$work_dir/stack/docker-compose.yml" || fail "edit not written"
expect_rc 0 "--check after build" build --check
pass "an edited source fails --check until build.py runs"

fresh_copy
printf '%s\n' '{"x": "$var ${__data.fields.x} $$"}' > "$dash"
expect_rc 0 "build with literal dollars" build
grep -qxF '      {"x": "$$var $${__data.fields.x} $$$$"}' "$work_dir/stack/docker-compose.yml" \
  || fail "literal \$ not escaped as \$\$"
pass "a literal \$ becomes \$\$"

fresh_copy
cp "$work_dir/stack/docker-compose.yml" "$work_dir/before.yml"
printf '%s\n' '{"x": "${NOT_LISTED}"}' > "$dash"
expect_rc 2 "unknown \${VAR}" build
grep -q 'unknown ${NOT_LISTED}' "$work_dir/out" || fail "unknown \${VAR}: wrong message"
cmp -s "$work_dir/before.yml" "$work_dir/stack/docker-compose.yml" || fail "compose written on error"
pass "an unknown \${VAR} stops the build, compose untouched"

fresh_copy
printf '%s\n' '{"x": "${VECTOR_WEBHOOK_PASSWORD}"}' > "$dash"
expect_rc 2 "interpolation in the wrong config" build
pass "an interpolation outside its config stops the build"

fresh_copy
rm "$dash"
expect_rc 2 "missing source" build
pass "a missing source stops the build"

fresh_copy
printf '  extra_config:\n    content: |\n      x\n' >> "$work_dir/stack/docker-compose.yml"
expect_rc 2 "unmapped config" build
grep -q "extra_config" "$work_dir/out" || fail "unmapped config: wrong message"
pass "a config without source stops the build"

fresh_copy
printf '%s\n\n' '{}' > "$dash"
expect_rc 2 "trailing blank line" build
pass "a trailing blank line, lost by content: |, stops the build"

# 4. Pre-commit check on the index.
git_dir="$work_dir/repo"
mkdir -p "$git_dir/.githooks"
cp "$repo_dir/.githooks/victoria-build-check.sh" "$git_dir/.githooks/"
fresh_copy
cp -r "$work_dir/stack" "$git_dir/victoria"
hook() { (cd "$git_dir" && .githooks/victoria-build-check.sh); }
git -C "$git_dir" init -q
git -C "$git_dir" add -A
expect_rc 0 "hook on a clean tree" hook

sed -i 's/"uid": "victoria-hosts"/"uid": "victoria-hosts-staged"/' "$git_dir/victoria/config/grafana/dashboards/hosts.json"
git -C "$git_dir" add victoria/config
expect_rc 1 "hook with a source staged alone" hook

python3 "$git_dir/victoria/build.py" >/dev/null
expect_rc 1 "hook with the compose file regenerated but not staged" hook

git -C "$git_dir" add victoria/docker-compose.yml
expect_rc 0 "hook with source and compose staged" hook

git -C "$git_dir" -c user.name=t -c user.email=t@t -c commit.gpgsign=false \
  -c core.hooksPath=/dev/null commit -qm base
echo '# unrelated' > "$git_dir/README.md"
git -C "$git_dir" add README.md
sed -i 's/victoria-hosts-staged/victoria-hosts-unstaged/' "$git_dir/victoria/config/grafana/dashboards/hosts.json"
expect_rc 0 "hook when victoria/ has no staged change" hook
pass "the pre-commit check reads the index: a source staged without its compose file fails"
