#!/usr/bin/env python3
"""Write the config sources of config/ into docker-compose.yml.

The configs stay inline (content:) in docker-compose.yml: outside Swarm, a
"file:" config is a bind mount from the host, and Portainer deploys from its
own clone of the repository, a path that does not exist on the host. So the
committed compose file must hold every config, and this script keeps it in
step with the sources:

    python3 build.py           rewrite the content: blocks from config/
    python3 build.py --check   exit 1 if docker-compose.yml is out of date

A source holds the text that the container reads. The script escapes it for
Compose: each $ becomes $$, except the ${VAR...} that Compose must interpolate,
listed per config in INTERPOLATED. A ${NAME...} listed nowhere stops the build:
the script cannot tell whether Compose or the container should read it.

Only the body of each content: block changes; the comments and every other
line of docker-compose.yml stay as written.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

STACK_DIR = Path(__file__).resolve().parent
COMPOSE = STACK_DIR / "docker-compose.yml"
CONFIG_DIR = STACK_DIR / "config"

DASHBOARDS = (
    "authentik",
    "proxmox",
    "unifi",
    "synology",
    "hosts",
    "logs",
    "docker",
    "dns",
    "firewall",
    "http",
    "alerts",
    "disks",
    "services",
    "stack",
    "freebox",
    "network",
)

# Compose config name -> source file, relative to config/.
SOURCES: dict[str, str] = {
    "victoriametrics_scrape": "victoriametrics/scrape.yml",
    "snmp_exporter_auth": "snmp_exporter/auth.yml",
    "freebox_exporter_config": "freebox_exporter/config.toml",
    "vmalert_logs_rules": "vmalert/logs_rules.yml",
    "vmalert_metrics_rules": "vmalert/metrics_rules.yml",
    "alertmanager_config": "alertmanager/alertmanager.yml",
    "vector_config": "vector/vector.yaml",
    "grafana_datasources": "grafana/datasources.yml",
    "grafana_dashboard_provider": "grafana/dashboards.yml",
    **{
        f"grafana_dashboard_{name}": f"grafana/dashboards/{name}.json"
        for name in DASHBOARDS
    },
}

# Variables that Compose interpolates, per config: the only ${...} written
# with a single $ in docker-compose.yml.
INTERPOLATED: dict[str, frozenset[str]] = {
    "victoriametrics_scrape": frozenset({"SYNOLOGY_SNMP_TARGET"}),
    "alertmanager_config": frozenset(
        {"ALERTMANAGER_WATCHDOG_URL", "VECTOR_WEBHOOK_PASSWORD"}
    ),
    "vector_config": frozenset(
        {"VECTOR_SYSLOG_DOMAIN", "VECTOR_SYSLOG_SENDERS", "VECTOR_WEBHOOK_PASSWORD"}
    ),
}

# ${...} that the container reads, not Compose: snmp_exporter expands its
# environment, Grafana its data links. They become $${...} in the compose file.
LITERAL = frozenset(
    {"SNMP_USER", "SNMP_AUTH_PASS", "SNMP_PRIV_PASS", "__url_time_range", "__data"}
)

BODY_INDENT = " " * 6
CONFIGS_KEY = "configs:"
NAME_RE = re.compile(r"^  ([a-z0-9_]+):$")
CONTENT_LINE = "    content: |"
BRACE_RE = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)")


class BuildError(Exception):
    """The sources or docker-compose.yml do not allow a safe build."""


def escape(config: str, text: str) -> str:
    """Return text with each $ escaped for Compose, except interpolations."""
    allowed = INTERPOLATED.get(config, frozenset())
    out: list[str] = []
    for index, char in enumerate(text):
        if char != "$":
            out.append(char)
            continue
        match = BRACE_RE.match(text, index)
        if match is None:
            if text.startswith("${", index):
                raise BuildError(f"{config}: invalid ${{ at offset {index}")
            out.append("$$")
        elif match.group(1) in allowed:
            out.append("$")
        elif match.group(1) in LITERAL:
            out.append("$$")
        else:
            raise BuildError(
                f"{config}: unknown ${{{match.group(1)}}}: add it to INTERPOLATED"
                " (Compose reads it) or LITERAL (the container reads it)"
            )
    return "".join(out)


def indent(text: str) -> list[str]:
    """Return the lines of a content: | body; blank lines stay empty."""
    if not text.endswith("\n"):
        raise BuildError("source must end with a newline")
    lines = text[:-1].split("\n")
    if lines and lines[0].startswith(" "):
        raise BuildError("first line must not be indented (YAML block indicator)")
    if lines and lines[-1] == "":
        raise BuildError("trailing blank line is lost by the content: | block")
    return [BODY_INDENT + line if line else "" for line in lines]


def body_spans(lines: list[str]) -> dict[str, tuple[int, int]]:
    """Return config name -> [start, end) of its content: body lines."""
    try:
        start = lines.index(CONFIGS_KEY)
    except ValueError as exc:
        raise BuildError("no top-level configs: key") from exc
    spans: dict[str, tuple[int, int]] = {}
    index = start + 1
    while index < len(lines):
        match = NAME_RE.match(lines[index])
        if match is None:
            if lines[index] and not lines[index].startswith("  #"):
                raise BuildError(f"line {index + 1}: unexpected line in configs:")
            index += 1
            continue
        name = match.group(1)
        if index + 1 >= len(lines) or lines[index + 1] != CONTENT_LINE:
            raise BuildError(
                f"{name}: expected '{CONTENT_LINE.strip()}' on the next line"
            )
        first = end = index + 2
        while end < len(lines) and (
            lines[end] == "" or lines[end].startswith(BODY_INDENT)
        ):
            end += 1
        while end > first and lines[end - 1] == "":
            end -= 1
        if name in spans:
            raise BuildError(f"{name}: defined twice")
        spans[name] = (first, end)
        index = end
    return spans


def build(compose_text: str, config_dir: Path) -> str:
    """Return docker-compose.yml with every content: body taken from config_dir."""
    lines = compose_text.split("\n")
    spans = body_spans(lines)
    if set(spans) != set(SOURCES):
        missing = sorted(set(SOURCES) - set(spans))
        unmapped = sorted(set(spans) - set(SOURCES))
        raise BuildError(
            f"configs without source: {unmapped}; sources without config: {missing}"
        )
    for name, (first, end) in sorted(spans.items(), key=lambda item: -item[1][0]):
        path = config_dir / SOURCES[name]
        try:
            text = path.read_text(encoding="utf-8")
        except OSError as exc:
            raise BuildError(f"{name}: cannot read {path}: {exc}") from exc
        try:
            lines[first:end] = indent(escape(name, text))
        except BuildError as exc:
            raise BuildError(f"{path}: {exc}") from exc
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Write the config sources of config/ into docker-compose.yml."
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="exit 1 if docker-compose.yml is out of date",
    )
    parser.add_argument("--compose", type=Path, default=COMPOSE, help=argparse.SUPPRESS)
    parser.add_argument(
        "--config-dir", type=Path, default=CONFIG_DIR, help=argparse.SUPPRESS
    )
    args = parser.parse_args(argv)
    current = args.compose.read_text(encoding="utf-8")
    try:
        built = build(current, args.config_dir)
    except BuildError as exc:
        print(f"build.py: {exc}", file=sys.stderr)
        return 2
    if args.check:
        if built != current:
            print(
                f"build.py: {args.compose.name} is out of date: run python3 build.py",
                file=sys.stderr,
            )
            return 1
        return 0
    if built != current:
        args.compose.write_text(built, encoding="utf-8")
        print(f"build.py: {args.compose.name} updated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
