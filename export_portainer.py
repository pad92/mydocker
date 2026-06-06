#!/usr/bin/env python3
"""
Portainer Stack Exporter
========================
This script exports all docker-compose stacks from a Portainer instance
into a structured Git-ready directory layout:
  nomstack/docker-compose.yml
  nomstack/.env
  nomstack/.env.example

It uses Python's standard library (no external dependencies required)
and supports both Portainer API keys and Username/Password auth.
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


def parse_arguments():
    """Parses command-line arguments for the script."""
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


def get_ssl_context(insecure):
    """Creates SSL context based on verification preference."""
    if insecure:
        # Create unverified context to bypass self-signed certificate warnings
        ctx = ssl._create_unverified_context()
        return ctx
    return ssl.create_default_context()


def sanitize_filename(name):
    """Sanitizes the stack name to be safe for directory creation across all OS platforms."""
    # Keep only alphanumeric characters, dashes, and underscores
    sanitized = re.sub(r"[^a-zA-Z0-9_\-]", "_", name)
    # Avoid double underscores or leading/trailing underscores/dashes
    sanitized = re.sub(r"_+", "_", sanitized)
    return sanitized.strip("_").lower()


def make_request(url, headers=None, data=None, method="GET", context=None):
    """Performs HTTP requests and handles errors gracefully."""
    if headers is None:
        headers = {}

    headers.setdefault("Content-Type", "application/json")
    headers.setdefault("User-Agent", "PortainerStackExporter/1.0")

    req_data = None
    if data is not None:
        req_data = json.dumps(data).encode("utf-8")

    req = urllib.request.Request(url, data=req_data, headers=headers, method=method)

    try:
        with urllib.request.urlopen(req, context=context) as response:
            res_content = response.read().decode("utf-8")
            if not res_content:
                return {}
            return json.loads(res_content)
    except urllib.error.HTTPError as e:
        sys.stderr.write(f"HTTP Error {e.code}: {e.reason}\n")
        try:
            error_body = e.read().decode("utf-8")
            sys.stderr.write(f"Server response: {error_body}\n")
        except Exception:
            pass
        raise
    except urllib.error.URLError as e:
        sys.stderr.write(f"Network Connection Error: {e.reason}\n")
        raise


def authenticate(base_url, username, password, context):
    """Authenticates using username/password and returns a JWT token."""
    print("No API Key provided. Attempting Username/Password authentication...")
    auth_url = f"{base_url.rstrip('/')}/api/auth"
    payload = {"username": username, "password": password}

    res = make_request(auth_url, data=payload, method="POST", context=context)
    jwt = res.get("jwt")
    if not jwt:
        raise ValueError("Failed to retrieve JWT token from authentication response")
    return jwt


def fetch_stacks(base_url, headers, context):
    """Fetches list of all stacks from Portainer."""
    print("Fetching stacks list from Portainer...")
    stacks_url = f"{base_url.rstrip('/')}/api/stacks"
    # Portainer stacks API returns a list of stack records
    return make_request(stacks_url, headers=headers, context=context)


def fetch_stack_file(base_url, headers, stack_id, context):
    """Retrieves the raw docker-compose file content for a given stack ID."""
    file_url = f"{base_url.rstrip('/')}/api/stacks/{stack_id}/file"
    res = make_request(file_url, headers=headers, context=context)
    return res.get("StackFileContent", "")


def write_stack_files(output_base, stack_name, compose_content, env_variables, only_env=False):
    """Writes docker-compose and environment files for a single stack."""
    safe_name = sanitize_filename(stack_name)
    stack_dir = os.path.join(output_base, safe_name)

    # Ensure output directory exists
    os.makedirs(stack_dir, exist_ok=True)

    # 1. Write docker-compose.yml
    if not only_env:
        compose_path = os.path.join(stack_dir, "docker-compose.yml")
        with open(compose_path, "w", encoding="utf-8") as f:
            f.write(compose_content)

    # 2. Write environment files if they exist
    if env_variables:
        env_path = os.path.join(stack_dir, ".env")
        env_example_path = os.path.join(stack_dir, ".env.example")

        # Sort env variables by name for consistency
        sorted_env = sorted(env_variables, key=lambda x: x.get("name", ""))

        env_exists = os.path.exists(env_path)
        from datetime import datetime
        current_date = datetime.now().strftime("%Y-%m-%d")

        if env_exists:
            # Read existing content to check if it ends with a newline
            with open(env_path, "r", encoding="utf-8") as f:
                existing_content = f.read()

            with open(env_path, "a", encoding="utf-8") as f_env:
                if existing_content and not existing_content.endswith("\n"):
                    f_env.write("\n")
                
                f_env.write(f"\n# Imported from Portainer on {current_date} (commented because .env already existed):\n")
                for item in sorted_env:
                    name = item.get("name", "")
                    val = item.get("value", "")
                    if name:
                        f_env.write(f"# {name}={val} # {current_date}\n")

            # Still overwrite/write .env.example
            with open(env_example_path, "w", encoding="utf-8") as f_example:
                f_example.write("# Exported template (Fill in values for local deployment)\n")
                for item in sorted_env:
                    name = item.get("name", "")
                    if name:
                        f_example.write(f"{name}=\n")
        else:
            with open(env_path, "w", encoding="utf-8") as f_env, open(
                env_example_path, "w", encoding="utf-8"
            ) as f_example:
                f_env.write("# Exported from Portainer\n")
                f_example.write("# Exported template (Fill in values for local deployment)\n")

                for item in sorted_env:
                    name = item.get("name", "")
                    val = item.get("value", "")
                    if name:
                        # Write real values to .env
                        f_env.write(f"{name}={val}\n")
                        # Write placeholder keys to .env.example
                        f_example.write(f"{name}=\n")

        if only_env:
            print(f"  -> Exported: {safe_name}/ (.env + .env.example only)")
        else:
            print(f"  -> Exported: {safe_name}/ (compose + .env + .env.example)")
    else:
        if only_env:
            print(f"  -> Skipped: {safe_name}/ (no env variables to export)")
        else:
            print(f"  -> Exported: {safe_name}/ (compose only)")


def write_global_gitignore(output_base):
    """Generates a top-level .gitignore to prevent accidental commit of credentials in .env."""
    gitignore_path = os.path.join(output_base, ".gitignore")

    # If gitignore already exists, check if it already ignores .env
    if os.path.exists(gitignore_path):
        with open(gitignore_path, "r", encoding="utf-8") as f:
            content = f.read()
        if "**/.env" in content or ".env" in content:
            return

    # Create/append .gitignore to ensure safety
    with open(gitignore_path, "a", encoding="utf-8") as f:
        f.write("\n# Protect credentials: ignore all .env files\n")
        f.write("**/.env\n")
    print("\n[Security] Added global .gitignore protecting all subfolder '.env' files.")


def main():
    args = parse_arguments()
    context = get_ssl_context(args.insecure)

    # Initialize headers
    headers = {}

    # Set up authentication headers
    if args.api_key:
        headers["X-API-Key"] = args.api_key
    elif args.username:
        password = args.password
        if not password:
            password = getpass.getpass("Enter Portainer password: ")
        try:
            jwt_token = authenticate(args.url, args.username, password, context)
            headers["Authorization"] = f"Bearer {jwt_token}"
        except Exception as e:
            sys.stderr.write(f"Authentication failed: {e}\n")
            sys.exit(1)
    else:
        sys.stderr.write(
            "Error: You must provide either an API Key (--token) or a Username (--username).\n"
        )
        sys.exit(1)

    try:
        stacks = fetch_stacks(args.url, headers, context)
    except Exception as e:
        sys.stderr.write(f"Error fetching stacks: {e}\n")
        sys.exit(1)

    if not stacks:
        print("No stacks found to export.")
        sys.exit(0)

    print(f"Found {len(stacks)} stacks. Starting export...")

    exported_count = 0
    for idx, stack in enumerate(stacks, 1):
        stack_id = stack.get("Id")
        stack_name = stack.get("Name")
        env_vars = stack.get("Env", [])

        # Filter out invalid records
        if not stack_name or stack_id is None:
            continue

        print(f"[{idx}/{len(stacks)}] Processing stack '{stack_name}' (ID: {stack_id})...")

        try:
            if not args.only_env:
                compose_content = fetch_stack_file(args.url, headers, stack_id, context)
                if not compose_content.strip():
                    print(f"  WARNING: Compose content is empty for '{stack_name}', skipping.")
                    continue
            else:
                compose_content = ""

            write_stack_files(args.output, stack_name, compose_content, env_vars, only_env=args.only_env)
            exported_count += 1
        except Exception as e:
            sys.stderr.write(f"  Error exporting stack '{stack_name}': {e}\n")

    # Generate a root gitignore to protect generated environment variables
    try:
        write_global_gitignore(args.output)
    except Exception as e:
        sys.stderr.write(f"Could not write .gitignore: {e}\n")

    print(f"\nSuccessfully migrated {exported_count}/{len(stacks)} stacks to '{args.output}'.")


if __name__ == "__main__":
    main()
