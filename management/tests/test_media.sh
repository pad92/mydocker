#!/usr/bin/env bash
# Static checks on the Authentik branding files (authentik/media/), served by
# the server from the Authentik origin. Opened directly, an SVG runs as a
# page of that origin, so a script in one would run with the user's session.
# - every file is a well-formed SVG with no script, event handler, embedded
#   document, entity, external reference (href, url(), @import) or image;
# - every "homelab/..." file named in the blueprints exists, and every file
#   is named by a blueprint (no forgotten or orphan file).
# Needs python3. Usage: ./tests/test_media.sh
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 -I - "$stack_dir/authentik/media" "$stack_dir/authentik/blueprints" <<'EOF'
import pathlib, re, sys
import xml.etree.ElementTree as ET

media, blueprints = (pathlib.Path(p) for p in sys.argv[1:3])
errors = []

files = sorted(p for p in media.rglob("*") if p.is_file())
forbidden = re.compile(
    r"<script|<foreignObject|<iframe|<embed|<object|<image|<!ENTITY|<!DOCTYPE"
    r"|\son[a-z]+\s*=|javascript:|@import", re.I)
reference = re.compile(r"""(?:href\s*=\s*["']|url\(\s*["']?)([^"')\s]*)""", re.I)
for p in files:
    rel = p.relative_to(media)
    if p.suffix != ".svg":
        errors.append(f"{rel}: not an SVG")
        continue
    text = p.read_text(encoding="utf-8")
    try:
        root = ET.fromstring(text)
    except ET.ParseError as e:
        errors.append(f"{rel}: not well-formed XML ({e})")
        continue
    if root.tag != "{http://www.w3.org/2000/svg}svg":
        errors.append(f"{rel}: root element is {root.tag}, not svg")
    errors += [f"{rel}: forbidden {m!r}" for m in forbidden.findall(text)]
    errors += [f"{rel}: external reference {r!r}"
               for r in reference.findall(text) if not r.startswith("#")]

named = set()
for bp in sorted(blueprints.glob("*.yaml")):
    named |= set(re.findall(r":\s*homelab/(\S+)\s*$", bp.read_text(encoding="utf-8"), re.M))
present = {str(p.relative_to(media)) for p in files}
errors += [f"homelab/{n}: named in a blueprint, missing from authentik/media"
           for n in sorted(named - present)]
errors += [f"{n}: in authentik/media, named by no blueprint" for n in sorted(present - named)]
if not named:
    errors.append("no homelab/... file named in the blueprints")

for e in errors:
    print("FAIL:", e, file=sys.stderr)
sys.exit(1 if errors else 0)
EOF

echo "OK"
