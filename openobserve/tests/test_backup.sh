#!/usr/bin/env bash
# Runs the backup script of openobserve-backup (configs.backup_script, as
# Compose renders it with .env.example) against a throwaway SQLite database in
# WAL mode, in the same image and with the same user as the service.
# Needs Docker, Docker Compose 2.23+ and jq. Usage: ./tests/test_backup.sh
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="python:3.13-alpine3.22"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$work_dir/data/db" "$work_dir/backup"

# PUID/PGID are empty in .env.example but required by the compose file.
PUID="${PUID:-1000}" PGID="${PGID:-1000}" docker compose \
  --project-directory "$stack_dir" --env-file "$stack_dir/.env.example" \
  config --format json > "$work_dir/compose.json"
jq -er '.configs.backup_script.content' "$work_dir/compose.json" > "$work_dir/backup.py"

run() {
  docker run --rm --network none --read-only --user "$(id -u):$(id -g)" \
    -e BACKUP_INTERVAL_HOURS=24 -e BACKUP_KEEP_DAYS=14 \
    -v "$work_dir/backup.py:/opt/openobserve-backup.py:ro" \
    -v "$work_dir/data:/data" -v "$work_dir/backup:/backup" \
    "$image" "$@"
}
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok - $*"; }

# Compose refuses to start a read_only service that receives an inline
# (content:) config: "`file` is the sole supported option".
conflicts="$(jq -r '.configs as $c | .services | to_entries[]
  | select(.value.read_only == true)
  | .key as $s | (.value.configs // [])[]
  | select($c[.source].content != null) | "\($s) <- \(.source)"' "$work_dir/compose.json")"
[ -z "$conflicts" ] || fail "inline config in a read_only service: $conflicts"
pass "no inline config in a read_only service"

run python /opt/openobserve-backup.py --once 2>/dev/null && fail "missing source must fail"
[ ! -e "$work_dir/data/db/metadata.sqlite" ] || fail "missing source was created"
[ -z "$(ls -A "$work_dir/backup")" ] || fail "failed backup left files"
pass "missing database: error, nothing created"

run python /opt/openobserve-backup.py --check && fail "check must fail without backup"
pass "healthcheck fails without backup"

# Source in WAL mode with a row still in the -wal file (no checkpoint), as
# OpenObserve leaves it while running. The writer stays open during the backup.
cat > "$work_dir/writer.py" <<'PY'
import sqlite3, subprocess, sys
db = sqlite3.connect("/data/db/metadata.sqlite")
db.execute("PRAGMA journal_mode=WAL")
db.execute("PRAGMA wal_autocheckpoint=0")
db.execute("CREATE TABLE meta (k TEXT, v TEXT)")
db.execute("INSERT INTO meta VALUES ('alert', 'unifi_high_risk_security_event')")
db.commit()
sys.exit(subprocess.call(["python", "/opt/openobserve-backup.py", "--once"]))
PY
# Stale backups: one past the retention, one recent, one file of another tool.
touch -d '20 days ago' "$work_dir/backup/metadata-20000101T000000Z.sqlite.gz"
touch -d '1 day ago' "$work_dir/backup/metadata-20000102T000000Z.sqlite.gz"
touch -d '20 days ago' "$work_dir/backup/other-tool.tar.gz"
docker run --rm --network none --user "$(id -u):$(id -g)" \
  -e BACKUP_INTERVAL_HOURS=24 -e BACKUP_KEEP_DAYS=14 \
  -v "$work_dir/backup.py:/opt/openobserve-backup.py:ro" -v "$work_dir/writer.py:/w.py:ro" \
  -v "$work_dir/data:/data" -v "$work_dir/backup:/backup" \
  "$image" python /w.py

new_backup="$(ls "$work_dir/backup"/metadata-2*.sqlite.gz | grep -v 2000010 )"
[ -n "$new_backup" ] || fail "no new backup"
gunzip -c "$new_backup" > "$work_dir/restored.sqlite"
value="$(docker run --rm --network none --user "$(id -u):$(id -g)" -v "$work_dir:/w" "$image" python -c \
  "import sqlite3; print(sqlite3.connect('/w/restored.sqlite').execute('SELECT v FROM meta').fetchone()[0])")"
[ "$value" = "unifi_high_risk_security_event" ] || fail "row of the -wal file missing from the backup: '$value'"
pass "backup of a WAL database contains the uncheckpointed rows"

[ ! -e "$work_dir/backup/metadata-20000101T000000Z.sqlite.gz" ] || fail "old backup not pruned"
[ -e "$work_dir/backup/metadata-20000102T000000Z.sqlite.gz" ] || fail "recent backup pruned"
[ -e "$work_dir/backup/other-tool.tar.gz" ] || fail "foreign file pruned"
[ -z "$(ls -A "$work_dir/backup" | grep '^\.')" ] || fail "temporary files left"
pass "retention: old backup deleted, recent one and foreign file kept"

run python /opt/openobserve-backup.py --check || fail "check must pass after a backup"
pass "healthcheck passes after a backup"

run sh -c 'BACKUP_KEEP_DAYS=0 python /opt/openobserve-backup.py --once' >/dev/null 2>&1 \
  && fail "invalid retention must be refused"
pass "invalid setting refused"
