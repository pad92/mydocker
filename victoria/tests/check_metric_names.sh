#!/usr/bin/env bash
# Checks the Proxmox metric names used by the vmalert-metrics rules and the
# Proxmox VE dashboard against the names that VictoriaMetrics really holds.
# A wrong name gives no error: the rule never fires and the panel stays empty.
# The names depend on the Proxmox VE OpenTelemetry plugin and on
# -opentelemetry.usePrometheusNaming (unit suffixes), so only live data can
# confirm them. Run it after deployment and after a Proxmox VE upgrade.
#
# Reads the JSON answer of /api/v1/label/__name__/values on stdin:
#   ssh <docker-host> "docker exec vmalert-logs wget -qO- \
#     http://victoriametrics:8428/api/v1/label/__name__/values" \
#     | ./tests/check_metric_names.sh [docker-compose.yml]
# Each name must exist; each __name__=~"..." regex must match at least one
# name. Needs python3.
set -euo pipefail

compose="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/docker-compose.yml}"

script="$(cat <<'EOF'
import json, re, sys

text = open(sys.argv[1]).read()
known = set(json.load(sys.stdin)["data"])

# Alert names share the proxmox_ prefix (rules and Alertmanager routes).
alerts = set(re.findall(r"alert: (\S+)", text))
regexes = set(re.findall(r'__name__=~\\?"([^"\\]+)', text))
text = re.sub(r'__name__=~\\?"[^"\\]+', "", text)
names = set(re.findall(r"\bproxmox_(?:node|vm|storage)_[a-z0-9_]+", text)) - alerts

# Guard against an extraction that silently finds nothing.
if len(names) < 20:
    sys.exit(f"FAIL: only {len(names)} metric names found in {sys.argv[1]}")

errors = [f"missing metric: {n}" for n in sorted(names - known)]
errors += [f"regex matches no metric: {r}" for r in sorted(regexes)
           if not any(re.fullmatch(r, k) for k in known)]
for e in errors:
    print(f"FAIL: {e}", file=sys.stderr)
if errors:
    sys.exit(1)
print(f"OK: {len(names)} names and {len(regexes)} regexes found in VictoriaMetrics")
EOF
)"
# The heredoc holds the script, so stdin stays the JSON answer.
python3 -I -c "$script" "$compose"
