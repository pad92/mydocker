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

Compose does not recreate a service whose inline config changed: the
content: of a config is not part of the service hash that "docker compose up"
compares. So each service that mounts a config carries a label,
mydocker.config-hash, the sha256 of the configs it mounts, and the script
rewrites its value with the bodies. A changed config changes the label of the
services that mount it, and Compose recreates those services, and only those.
The label line must exist, under the labels: of the service: the script
updates its value but never adds it.

Only the body of each content: block and the value of each config-hash label
change; the comments and every other line of docker-compose.yml stay as
written.
"""

from __future__ import annotations

import argparse
import hashlib
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
    "wifi",
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
    "victoriametrics_scrape": frozenset({"SYNOLOGY_SNMP_TARGET", "NVIDIA_GPU_HOST_NAME"}),
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
SERVICES_KEY = "services:"
SERVICE_RE = re.compile(r"^  ([a-z0-9][a-z0-9_-]*):$")
SERVICE_KEY_RE = re.compile(r"^    ([a-z_]+):")
CONFIG_REF_RE = re.compile(r"^      - (?:source: )?([a-z0-9_]+)$")
HASH_LABEL = "mydocker.config-hash"
HASH_LABEL_RE = re.compile(r'^      mydocker\.config-hash: "[0-9a-f]*"$')


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


def config_hash(names: list[str], bodies: dict[str, list[str]]) -> str:
    """Return the sha256 of the configs names, as written in the compose file.

    Each config enters with its name and its line count, so that moving a line
    from one config to the next one changes the hash too.
    """
    digest = hashlib.sha256()
    for name in names:
        body = bodies[name]
        digest.update(f"{name}\n{len(body)}\n".encode())
        digest.update("\n".join(body).encode())
        digest.update(b"\n")
    return digest.hexdigest()


def service_spans(lines: list[str]) -> dict[str, tuple[int, int]]:
    """Return service name -> [start, end) of its lines, header included."""
    try:
        start = lines.index(SERVICES_KEY)
    except ValueError as exc:
        raise BuildError("no top-level services: key") from exc
    end = start + 1
    while end < len(lines) and (not lines[end] or lines[end][0] in " #"):
        end += 1
    spans: dict[str, tuple[int, int]] = {}
    current: str | None = None
    for index in range(start + 1, end):
        match = SERVICE_RE.match(lines[index])
        if match is None:
            continue
        if current is not None:
            spans[current] = (spans[current][0], index)
        current = match.group(1)
        spans[current] = (index, end)
    return spans


def hash_labels(lines: list[str], bodies: dict[str, list[str]]) -> None:
    """Rewrite in place the config-hash label of each service with configs."""
    for service, (first, end) in service_spans(lines).items():
        refs: list[str] = []
        label: int | None = None
        key = ""
        for index in range(first + 1, end):
            line = lines[index]
            match = SERVICE_KEY_RE.match(line)
            if match is not None:
                key = match.group(1)
                continue
            if HASH_LABEL in line:
                if key != "labels" or not HASH_LABEL_RE.match(line):
                    raise BuildError(
                        f"{service}: line {index + 1}: write the label as"
                        f" '      {HASH_LABEL}: \"\"' under labels:"
                    )
                if label is not None:
                    raise BuildError(f"{service}: {HASH_LABEL} defined twice")
                label = index
            elif key == "configs":
                ref = CONFIG_REF_RE.match(line)
                if ref is not None:
                    refs.append(ref.group(1))
        unknown = sorted(set(refs) - set(bodies))
        if unknown:
            raise BuildError(f"{service}: unknown configs {unknown}")
        if not refs and label is None:
            continue
        if not refs:
            raise BuildError(f"{service}: {HASH_LABEL} on a service without configs")
        if label is None:
            raise BuildError(
                f"{service}: mounts {refs} but has no {HASH_LABEL} label: add"
                f" '      {HASH_LABEL}: \"\"' under its labels:"
            )
        lines[label] = f'      {HASH_LABEL}: "{config_hash(refs, bodies)}"'


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
    bodies: dict[str, list[str]] = {}
    for name, (first, end) in sorted(spans.items(), key=lambda item: -item[1][0]):
        path = config_dir / SOURCES[name]
        try:
            text = path.read_text(encoding="utf-8")
        except OSError as exc:
            raise BuildError(f"{name}: cannot read {path}: {exc}") from exc
        try:
            bodies[name] = indent(escape(name, text))
        except BuildError as exc:
            raise BuildError(f"{path}: {exc}") from exc
        lines[first:end] = bodies[name]
    # services: comes before configs:, whose bodies only moved the lines
    # after it: the service spans are read from the rewritten lines.
    hash_labels(lines, bodies)
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
