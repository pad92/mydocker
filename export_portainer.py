#!/usr/bin/env python3
"""
Portainer Stack Exporter
========================
Exports all docker-compose stacks from a Portainer instance
into a structured Git-ready directory layout:
  stack_name/docker-compose.yml
  stack_name/.env
  stack_name/.env.example
"""

import argparse
import getpass
import json
import os
import re
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request

HTTP_TIMEOUT = 30
SECRET_PATTERN = re.compile(r"password|secret|token|key|api", re.IGNORECASE)
SAFE_NAME_RE = re.compile(r"[^a-zA-Z0-9_\-]")
MULTI_UNDERSCORE_RE = re.compile(r"_+")
PORTAINER_IMPORT_RE = re.compile(
    r"\n*# Imported from Portainer on \d{4}-\d{2}-\d{2}.*?(?=\n[^#\n]|\Z)",
    re.DOTALL,
)


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Export Portainer docker-compose stacks with environment variables."
    )
    parser.add_argument(
        "--url",
        required=True,
        help="Portainer URL (e.g., http://localhost:9000 or https://portainer.local)",
    )
    parser.add_argument(
        "--token",
        "--api-key",
        dest="api_key",
        help="Portainer API Access Token (recommended)",
    )
    parser.add_argument(
        "--username",
        help="Portainer username (fallback if no API token is provided)",
    )
    parser.add_argument(
        "--password",
        help="Portainer password (will prompt securely if not provided and username is present)",
    )
    parser.add_argument(
        "--output",
        default=".",
        help="Output base directory for the stacks (default: current directory)",
    )
    parser.add_argument(
        "--insecure",
        action="store_true",
        help="Disable SSL certificate verification (useful for self-signed certificates)",
    )
    parser.add_argument(
        "--only-env",
        action="store_true",
        help="Only export environment variables (.env and .env.example) and skip docker-compose.yml",
    )
    return parser.parse_args()


def make_request(url, headers=None, data=None, method="GET", context=None):
    if headers is None:
        headers = {}
    headers.setdefault("Content-Type", "application/json")
    headers.setdefault("User-Agent", "PortainerStackExporter/1.0")

    req = urllib.request.Request(
        url,
        data=json.dumps(data).encode("utf-8") if data is not None else None,
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(req, context=context, timeout=HTTP_TIMEOUT) as resp:
            body = resp.read().decode("utf-8")
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as e:
        sys.stderr.write(f"HTTP Error {e.code}: {e.reason}\n")
        try:
            sys.stderr.write(f"Server response: {e.read().decode('utf-8')}\n")
        except Exception:
            pass
        raise
    except urllib.error.URLError as e:
        sys.stderr.write(f"Network Connection Error: {e.reason}\n")
        raise


def authenticate(base_url, username, password, context):
    print("No API Key provided. Attempting Username/Password authentication...")
    url = f"{base_url.rstrip('/')}/api/auth"
    res = make_request(url, data={"username": username, "password": password}, method="POST", context=context)
    jwt = res.get("jwt")
    if not jwt:
        raise ValueError("Failed to retrieve JWT token from authentication response")
    return jwt


def sanitize_filename(name):
    sanitized = SAFE_NAME_RE.sub("_", name)
    sanitized = MULTI_UNDERSCORE_RE.sub("_", sanitized).strip("_").lower()
    if not sanitized:
        raise ValueError(f"Stack name '{name}' produces an empty directory name after sanitization")
    return sanitized


def is_secret_key(name):
    return bool(SECRET_PATTERN.search(name))


def format_env_lines(env_vars, with_values=True, comment=False):
    lines = []
    for item in env_vars:
        name = item.get("name", "")
        if not name:
            continue
        if with_values:
            val = item.get("value", "")
            line = f"{name}={val}"
        else:
            line = f"{name}={'CHANGEME' if is_secret_key(name) else ''}"
        lines.append(f"# {line}" if comment else line)
    return lines


def write_env_files(stack_dir, stack_name, env_vars, current_date):
    if not env_vars:
        return False

    sorted_env = sorted(env_vars, key=lambda x: x.get("name", ""))
    env_path = os.path.join(stack_dir, ".env")
    example_path = os.path.join(stack_dir, ".env.example")

    if os.path.exists(env_path):
        with open(env_path, "r", encoding="utf-8") as f:
            content = f.read()
        content = PORTAINER_IMPORT_RE.sub("", content).rstrip("\n")
        import_lines = format_env_lines(sorted_env, with_values=True, comment=True)
        content += f"\n\n# Imported from Portainer on {current_date} (commented because .env already existed):\n"
        content += "\n".join(import_lines) + "\n"
        with open(env_path, "w", encoding="utf-8") as f:
            f.write(content)
    else:
        lines = format_env_lines(sorted_env, with_values=True)
        with open(env_path, "w", encoding="utf-8") as f:
            f.write(f"# Environment configuration for stack: {stack_name}\n")
            f.write("\n".join(lines) + "\n")

    example_lines = format_env_lines(sorted_env, with_values=False)
    with open(example_path, "w", encoding="utf-8") as f:
        f.write(f"# Template configuration for stack: {stack_name} (Fill in values for local deployment)\n")
        f.write("\n".join(example_lines) + "\n")

    return True


def write_stack(output_base, stack_name, compose_content, env_vars, only_env, current_date):
    safe_name = sanitize_filename(stack_name)
    stack_dir = os.path.join(output_base, safe_name)
    os.makedirs(stack_dir, exist_ok=True)

    if not only_env:
        with open(os.path.join(stack_dir, "docker-compose.yml"), "w", encoding="utf-8") as f:
            f.write(compose_content)

    has_env = write_env_files(stack_dir, stack_name, env_vars, current_date)

    if only_env:
        suffix = ".env + .env.example only" if has_env else "no env variables to export"
        action = "Exported" if has_env else "Skipped"
    else:
        suffix = "compose + .env + .env.example" if has_env else "compose only"
        action = "Exported"
    print(f"  -> {action}: {safe_name}/ ({suffix})")


def ensure_gitignore(output_base):
    path = os.path.join(output_base, ".gitignore")
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            if "**/.env" in f.read():
                return
    with open(path, "a", encoding="utf-8") as f:
        f.write("\n# Protect credentials: ignore all .env files\n**/.env\n")
    print("\n[Security] Added global .gitignore protecting all subfolder '.env' files.")


def build_auth_headers(args, context):
    if args.api_key:
        return {"X-API-Key": args.api_key}

    if not args.username:
        sys.stderr.write("Error: You must provide either an API Key (--token) or a Username (--username).\n")
        sys.exit(1)

    if args.password:
        print("WARNING: Password passed via command line is visible in process list and shell history.", file=sys.stderr)
        print("         Consider omitting --password to use the secure interactive prompt.\n", file=sys.stderr)
        password = args.password
    else:
        password = getpass.getpass("Enter Portainer password: ")

    try:
        jwt_token = authenticate(args.url, args.username, password, context)
    except Exception as e:
        sys.stderr.write(f"Authentication failed: {e}\n")
        sys.exit(1)
    return {"Authorization": f"Bearer {jwt_token}"}


def main():
    args = parse_arguments()
    context = ssl._create_unverified_context() if args.insecure else ssl.create_default_context()
    headers = build_auth_headers(args, context)
    base_url = args.url.rstrip("/")

    try:
        stacks = make_request(f"{base_url}/api/stacks", headers=headers, context=context)
    except Exception as e:
        sys.stderr.write(f"Error fetching stacks: {e}\n")
        sys.exit(1)

    if not stacks:
        print("No stacks found to export.")
        sys.exit(0)

    print(f"Found {len(stacks)} stacks. Starting export...")

    from datetime import datetime
    current_date = datetime.now().strftime("%Y-%m-%d")

    exported = 0
    for idx, stack in enumerate(stacks, 1):
        stack_id = stack.get("Id")
        stack_name = stack.get("Name")
        if not stack_name or stack_id is None:
            continue

        print(f"[{idx}/{len(stacks)}] Processing stack '{stack_name}' (ID: {stack_id})...")

        try:
            compose_content = ""
            if not args.only_env:
                compose_content = make_request(
                    f"{base_url}/api/stacks/{stack_id}/file",
                    headers=headers,
                    context=context,
                ).get("StackFileContent", "")
                if not compose_content.strip():
                    print(f"  WARNING: Compose content is empty for '{stack_name}', skipping.")
                    continue

            write_stack(args.output, stack_name, compose_content, stack.get("Env", []), args.only_env, current_date)
            exported += 1
        except Exception as e:
            sys.stderr.write(f"  Error exporting stack '{stack_name}': {e}\n")

    try:
        ensure_gitignore(args.output)
    except Exception as e:
        sys.stderr.write(f"Could not write .gitignore: {e}\n")

    print(f"\nSuccessfully migrated {exported}/{len(stacks)} stacks to '{args.output}'.")


if __name__ == "__main__":
    main()
