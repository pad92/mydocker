#!/usr/bin/env python3
"""Generate the h5ai share mounts of ng/docker-compose.yml from ng/h5ai-shares.conf.

Compose cannot loop over a list, so the h5ai mounts under /share are written
between BEGIN/END markers in docker-compose.yml by this script. The generated
part is committed: Portainer/Dockhand deploy the file from git as is.

Usage (from anywhere):
    python3 -I ng/scripts/h5ai_shares.py          # rewrite docker-compose.yml
    python3 -I ng/scripts/h5ai_shares.py --check  # exit 1 if it is out of date

Stdlib only.
"""

import argparse
import pathlib
import re
import sys

NG_DIR = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_CONF = NG_DIR / "h5ai-shares.conf"
DEFAULT_COMPOSE = NG_DIR / "docker-compose.yml"

SHARE_ROOT = "/share"
NFS_VOLUME_PREFIX = "h5ai_share_"
TYPES = ("volume", "nfs", "bind")

MOUNTS_BLOCK = "h5ai-shares mounts"
VOLUMES_BLOCK = "h5ai-shares volumes"
GENERATED_NOTE = (
    "generated from h5ai-shares.conf by scripts/h5ai_shares.py, do not edit"
)

NAME_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]*")
# A path, or a path built from ${VAR} references. No whitespace, no colon
# (it separates the parts of a short volume spec), no YAML/quoting specials.
PATH_RE = re.compile(r"(/|\$\{[A-Za-z_][A-Za-z0-9_]*\})[A-Za-z0-9_./${}#@+,=-]*")
TOP_LEVEL_VOLUME_RE = re.compile(r"  ([A-Za-z0-9][A-Za-z0-9_.-]*):\s*$")


class ShareError(Exception):
    """Invalid share list or compose file."""


def parse_conf(text):
    """Return the shares of the config as (name, type, source) tuples."""
    shares = []
    seen = set()
    for lineno, raw in enumerate(text.splitlines(), 1):
        # Full-line and trailing ("  # ...") comments. A '#' inside a path is kept.
        line = (
            ""
            if raw.lstrip().startswith("#")
            else re.split(r"\s#", raw, maxsplit=1)[0].strip()
        )
        if not line:
            continue
        fields = line.split()
        if len(fields) != 3:
            raise ShareError(
                f"line {lineno}: expected '<name> <type> <source>', got {raw.strip()!r}"
            )
        name, kind, source = fields
        if not NAME_RE.fullmatch(name):
            raise ShareError(f"line {lineno}: invalid share name {name!r}")
        if name in seen:
            raise ShareError(f"line {lineno}: duplicate share name {name!r}")
        if kind not in TYPES:
            raise ShareError(
                f"line {lineno}: unknown type {kind!r} (expected one of {', '.join(TYPES)})"
            )
        if kind == "volume":
            if not NAME_RE.fullmatch(source):
                raise ShareError(f"line {lineno}: invalid volume name {source!r}")
            if source.startswith(NFS_VOLUME_PREFIX):
                raise ShareError(
                    f"line {lineno}: {source!r} is reserved for generated nfs volumes"
                )
        elif not PATH_RE.fullmatch(source) or "//" in source:
            raise ShareError(
                f"line {lineno}: invalid path {source!r} (absolute path or ${{VAR}}/..., no ':' or spaces)"
            )
        seen.add(name)
        shares.append((name, kind, source))
    return shares


def _find_block(lines, label):
    """Return (begin, end) indexes of the marker lines of a generated block."""
    begins = [
        i for i, line in enumerate(lines) if line.strip().startswith(f"# BEGIN {label}")
    ]
    ends = [i for i, line in enumerate(lines) if line.strip() == f"# END {label}"]
    if len(begins) != 1 or len(ends) != 1 or ends[0] < begins[0]:
        raise ShareError(
            f"docker-compose.yml must contain exactly one '# BEGIN {label}' ... '# END {label}' block"
        )
    return begins[0], ends[0]


def _declared_volumes(lines):
    """Top-level named volumes declared outside the generated block."""
    begin, end = _find_block(lines, VOLUMES_BLOCK)
    kept = lines[:begin] + lines[end + 1 :]
    names = set()
    in_volumes = False
    for line in kept:
        if line and not line[0].isspace() and not line.startswith("#"):
            in_volumes = line.rstrip() == "volumes:"
            continue
        match = TOP_LEVEL_VOLUME_RE.match(line) if in_volumes else None
        if match:
            names.add(match.group(1))
    return names


def _replace_block(lines, label, body):
    begin, end = _find_block(lines, label)
    indent = lines[begin][: len(lines[begin]) - len(lines[begin].lstrip())]
    header = f"{indent}# BEGIN {label} ({GENERATED_NOTE})"
    footer = f"{indent}# END {label}"
    return (
        lines[:begin]
        + [header]
        + [indent + row if row else "" for row in body]
        + [footer]
        + lines[end + 1 :]
    )


def render(compose_text, conf_text):
    """Return docker-compose.yml with both generated blocks rebuilt from the config."""
    shares = parse_conf(conf_text)
    lines = compose_text.split("\n")
    declared = _declared_volumes(lines)

    mounts = []
    volumes = []
    for name, kind, source in shares:
        if kind == "volume":
            if source not in declared:
                raise ShareError(
                    f"share {name!r}: volume {source!r} is not declared in docker-compose.yml"
                )
            mounts.append(f"- {source}:{SHARE_ROOT}/{name}:ro")
        elif kind == "bind":
            mounts.append(f"- {source}:{SHARE_ROOT}/{name}:ro")
        else:
            volume = NFS_VOLUME_PREFIX + name
            if volume in declared:
                raise ShareError(
                    f"share {name!r}: volume {volume!r} already exists outside the generated block"
                )
            mounts.append(f"- {volume}:{SHARE_ROOT}/{name}:ro")
            volumes += [
                f"{volume}:",
                "  driver: local",
                "  driver_opts:",
                "    <<: *nfs-driver-opts",
                f"    device: :{source}",
            ]

    lines = _replace_block(lines, MOUNTS_BLOCK, mounts)
    lines = _replace_block(lines, VOLUMES_BLOCK, volumes)
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--check", action="store_true", help="fail if docker-compose.yml is out of date"
    )
    parser.add_argument("--conf", type=pathlib.Path, default=DEFAULT_CONF)
    parser.add_argument("--compose", type=pathlib.Path, default=DEFAULT_COMPOSE)
    args = parser.parse_args(argv)

    try:
        current = args.compose.read_text(encoding="utf-8")
        wanted = render(current, args.conf.read_text(encoding="utf-8"))
    except (OSError, ShareError) as exc:
        print(f"h5ai_shares: {exc}", file=sys.stderr)
        return 2

    if wanted == current:
        print(f"h5ai_shares: {args.compose.name} is up to date")
        return 0
    if args.check:
        print(
            f"h5ai_shares: {args.compose.name} is out of date, run: python3 -I ng/scripts/h5ai_shares.py",
            file=sys.stderr,
        )
        return 1
    args.compose.write_text(wanted, encoding="utf-8")
    print(f"h5ai_shares: {args.compose.name} updated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
