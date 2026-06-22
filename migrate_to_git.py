#!/usr/bin/env python3
"""
Portainer Stack Git Migrator
=============================
Automates the migration of Portainer stacks from "Web Editor" mode
to "Git Repository" mode via the Portainer API.

Only migrates stacks that already have a corresponding directory
(with docker-compose.yml) in the local repository.
"""

import argparse
import getpass
import json
import os
import re
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

HTTP_TIMEOUT = 30
SAFE_NAME_RE = re.compile(r"[^a-zA-Z0-9_\-]")
MULTI_UNDERSCORE_RE = re.compile(r"_+")


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Migrate Portainer stacks from Web Editor to Git Repository mode."
    )
    portainer = parser.add_argument_group("Portainer connection")
    portainer.add_argument("--url", required=True, help="Portainer URL (e.g., https://portainer.local:9443)")
    portainer.add_argument("--token", "--api-key", dest="api_key", help="Portainer API Access Token (recommended)")
    portainer.add_argument("--username", help="Portainer username (fallback if no API token)")
    portainer.add_argument("--password", help="Portainer password (will prompt if not provided)")
    portainer.add_argument("--insecure", action="store_true", help="Disable SSL certificate verification for Portainer")

    git = parser.add_argument_group("Git repository")
    git.add_argument("--repo-url", required=True, help="Git repository URL that Portainer will pull from")
    git.add_argument("--repo-ref", default="refs/heads/main", help="Git reference (default: refs/heads/main)")
    git.add_argument("--repo-username", help="Git repository username (if authentication required)")
    git.add_argument("--repo-password", help="Git repository password or token (if authentication required)")
    git.add_argument("--repo-insecure", action="store_true", help="Skip TLS verification for Git repository")

    migration = parser.add_argument_group("Migration options")
    migration.add_argument("--output", default=".", help="Local repository root directory (default: current directory)")
    migration.add_argument("--dry-run", action="store_true", help="Preview migration without making any changes")
    migration.add_argument("--exclude", nargs="*", default=[], metavar="STACK",
                           help="Stack names to exclude from migration")
    migration.add_argument("--only", nargs="*", default=[], metavar="STACK",
                           help="Only migrate these specific stacks")
    migration.add_argument("--delay", type=int, default=3,
                           help="Seconds to wait between delete and recreate (default: 3)")
    migration.add_argument("--auto-update", action="store_true",
                           help="Enable automatic polling for Git updates in Portainer (5 min interval)")
    migration.add_argument("--yes", "-y", action="store_true", help="Skip confirmation prompt")

    return parser.parse_args()


def make_request(url, headers=None, data=None, method="GET", context=None):
    if headers is None:
        headers = {}
    headers.setdefault("Content-Type", "application/json")
    headers.setdefault("User-Agent", "PortainerStackMigrator/1.0")

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
        error_body = ""
        try:
            error_body = e.read().decode("utf-8")
        except Exception:
            pass
        sys.stderr.write(f"  HTTP {e.code}: {e.reason}\n")
        if error_body:
            sys.stderr.write(f"  Response: {error_body}\n")
        raise
    except urllib.error.URLError as e:
        sys.stderr.write(f"  Network error: {e.reason}\n")
        raise


def authenticate(base_url, username, password, context):
    url = f"{base_url}/api/auth"
    res = make_request(url, data={"username": username, "password": password}, method="POST", context=context)
    jwt = res.get("jwt")
    if not jwt:
        raise ValueError("Failed to retrieve JWT token")
    return jwt


def build_auth_headers(args, context):
    base_url = args.url.rstrip("/")
    if args.api_key:
        return {"X-API-Key": args.api_key}
    if not args.username:
        sys.stderr.write("Error: Provide either --token or --username for Portainer authentication.\n")
        sys.exit(1)
    if args.password:
        print("WARNING: Password visible in process list. Consider omitting --password.", file=sys.stderr)
        password = args.password
    else:
        password = getpass.getpass("Enter Portainer password: ")
    try:
        jwt_token = authenticate(base_url, args.username, password, context)
    except Exception as e:
        sys.stderr.write(f"Authentication failed: {e}\n")
        sys.exit(1)
    return {"Authorization": f"Bearer {jwt_token}"}


def sanitize_filename(name):
    sanitized = SAFE_NAME_RE.sub("_", name)
    sanitized = MULTI_UNDERSCORE_RE.sub("_", sanitized).strip("_").lower()
    return sanitized


def get_local_stacks(output_base):
    stacks = set()
    if not os.path.isdir(output_base):
        return stacks
    for entry in os.listdir(output_base):
        compose_path = os.path.join(output_base, entry, "docker-compose.yml")
        if os.path.isfile(compose_path):
            stacks.add(entry)
    return stacks


def classify_stacks(stacks, local_dirs, exclude_list, only_list):
    to_migrate = []
    already_git = []
    no_local_dir = []
    excluded = []

    exclude_normalized = {sanitize_filename(e) for e in exclude_list} | set(exclude_list)
    only_normalized = {sanitize_filename(o) for o in only_list} | set(only_list) if only_list else set()

    for stack in sorted(stacks, key=lambda s: s.get("Name", "")):
        name = stack.get("Name", "")
        safe_name = sanitize_filename(name)

        if only_normalized and name not in only_normalized and safe_name not in only_normalized:
            continue

        if name in exclude_normalized or safe_name in exclude_normalized:
            excluded.append(stack)
            continue

        if stack.get("GitConfig"):
            already_git.append(stack)
            continue

        if safe_name not in local_dirs:
            no_local_dir.append(stack)
            continue

        to_migrate.append(stack)

    return to_migrate, already_git, no_local_dir, excluded


def delete_stack(base_url, headers, stack_id, endpoint_id, context):
    url = f"{base_url}/api/stacks/{stack_id}?endpointId={endpoint_id}"
    make_request(url, headers=headers, method="DELETE", context=context)


def create_stack_from_repo(base_url, headers, stack, args, context):
    endpoint_id = stack.get("EndpointId")
    stack_type = stack.get("Type", 2)
    safe_name = sanitize_filename(stack["Name"])

    if stack_type == 1:
        create_path = "swarm"
    else:
        create_path = "standalone"

    url = f"{base_url}/api/stacks/create/{create_path}/repository?endpointId={endpoint_id}"

    body = {
        "name": stack["Name"],
        "repositoryURL": args.repo_url,
        "repositoryReferenceName": args.repo_ref,
        "composeFile": f"{safe_name}/docker-compose.yml",
        "env": stack.get("Env", []),
        "tlsskipVerify": args.repo_insecure,
    }

    if stack_type == 1:
        body["swarmID"] = stack.get("SwarmId", "")

    if args.repo_username:
        body["repositoryAuthentication"] = True
        body["repositoryUsername"] = args.repo_username
        body["repositoryPassword"] = args.repo_password or ""
    else:
        body["repositoryAuthentication"] = False

    if args.auto_update:
        body["autoUpdate"] = {
            "interval": "5m",
        }

    return make_request(url, headers=headers, data=body, method="POST", context=context)


def print_report(already_git, no_local_dir, excluded, to_migrate):
    if already_git:
        print(f"Already on Git ({len(already_git)}):")
        for s in already_git:
            git_url = s["GitConfig"].get("URL", "?")
            print(f"  [git] {s['Name']} -> {git_url}")
        print()

    if no_local_dir:
        print(f"No local directory — skipped ({len(no_local_dir)}):")
        for s in no_local_dir:
            print(f"  [skip] {s['Name']} (missing '{sanitize_filename(s['Name'])}/' folder)")
        print()

    if excluded:
        print(f"Excluded ({len(excluded)}):")
        for s in excluded:
            print(f"  [excl] {s['Name']}")
        print()

    if to_migrate:
        print(f"Ready to migrate ({len(to_migrate)}):")
        for s in to_migrate:
            safe = sanitize_filename(s["Name"])
            env_count = len(s.get("Env", []))
            print(f"  [migrate] {s['Name']} (compose: {safe}/docker-compose.yml, {env_count} env vars)")
        print()
    else:
        print("Nothing to migrate.\n")


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
        print("No stacks found in Portainer.")
        sys.exit(0)

    local_dirs = get_local_stacks(args.output)
    print(f"Portainer: {len(stacks)} stacks | Local: {len(local_dirs)} directories with docker-compose.yml\n")

    to_migrate, already_git, no_local_dir, excluded = classify_stacks(
        stacks, local_dirs, args.exclude, args.only
    )

    print_report(already_git, no_local_dir, excluded, to_migrate)

    if not to_migrate:
        sys.exit(0)

    if args.dry_run:
        print("[DRY RUN] No changes were made. Remove --dry-run to proceed.")
        sys.exit(0)

    if not args.yes:
        print("WARNING: Each stack will be deleted then recreated from Git.")
        print("         Containers will restart. Data in volumes is preserved.")
        print(f"         Delay between delete/recreate: {args.delay}s per stack.\n")
        answer = input(f"Proceed with migration of {len(to_migrate)} stack(s)? [y/N] ").strip().lower()
        if answer not in ("y", "yes"):
            print("Migration cancelled.")
            sys.exit(0)

    success = 0
    failed = []
    for idx, stack in enumerate(to_migrate, 1):
        name = stack["Name"]
        stack_id = stack["Id"]
        endpoint_id = stack.get("EndpointId")
        print(f"[{idx}/{len(to_migrate)}] Migrating '{name}'...")

        try:
            print(f"  Deleting stack (ID: {stack_id})...")
            delete_stack(base_url, headers, stack_id, endpoint_id, context)

            if args.delay > 0:
                print(f"  Waiting {args.delay}s...")
                time.sleep(args.delay)

            print(f"  Recreating from Git...")
            result = create_stack_from_repo(base_url, headers, stack, args, context)
            new_id = result.get("Id", "?")
            print(f"  Done (new ID: {new_id})")
            success += 1
        except Exception as e:
            sys.stderr.write(f"  FAILED: {e}\n")
            sys.stderr.write(f"  Stack '{name}' may need manual recreation in Portainer!\n")
            failed.append(name)

    print(f"\nMigration complete: {success} succeeded, {len(failed)} failed out of {len(to_migrate)}.")
    if failed:
        print(f"Failed stacks: {', '.join(failed)}")
        print("These stacks were deleted but could not be recreated.")
        print("Recreate them manually in Portainer using the Git repository method.")
        sys.exit(1)


if __name__ == "__main__":
    main()
