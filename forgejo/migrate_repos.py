#!/usr/bin/env python3
"""Copy every repository of a Gitea instance into Forgejo through the API.

Forgejo cannot take over the database of Gitea 1.23 or later, so each
repository goes through Forgejo's own migration tool (POST /repos/migrate),
which reads the Gitea API: code, LFS, wiki, issues, pull requests, labels,
milestones and releases. Pull mirrors are recreated as mirrors of their
upstream URL. Archived repositories are archived again after the copy.

Gitea answers 404 when the pull requests of an archived repository are listed,
which makes Forgejo's migration fail. Archived repositories are therefore
copied without their pull requests, unless --unarchive-source is given: the
repository is then unarchived in Gitea for the duration of its copy, and
archived again afterwards.

The script prints the plan by default and changes nothing; --apply runs it.
Repositories that already exist in Forgejo are skipped, so a run can be
repeated. When Forgejo reports a failed migration, the partial repository it
leaves behind is deleted so that the next run copies it again. Missing owners
are created in Forgejo: organisations with the settings they have in Gitea,
user accounts with the same name, email and full name, a random password that
is not shown, and the obligation to change it (see README.md). Packages
(container images...) are not copied by Forgejo; they are listed at the end so
that they can be pushed again.

Tokens are read from GITEA_TOKEN and FORGEJO_TOKEN, never from the command
line. TLS certificates are verified with the system trust store (SSL_CERT_FILE
also works).
"""

from __future__ import annotations

import argparse
import json
import os
import secrets
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Iterator, Sequence
from dataclasses import dataclass
from typing import Any

PAGE_SIZE = 50
API_TIMEOUT_SECONDS = 60
# Forgejo answers POST /repos/migrate only once the copy is over.
DEFAULT_MIGRATE_TIMEOUT_SECONDS = 3600
# Bytes of randomness of the password given to the user accounts created in
# Forgejo. Nobody knows it: an admin sets a new one, or the user resets it.
CREATED_USER_PASSWORD_BYTES = 32

JsonObject = dict[str, Any]


class ApiError(Exception):
    """An API call failed. status is None when no HTTP answer was received
    (connection error, timeout): the server may still be working on it."""

    def __init__(self, method: str, url: str, status: int | None, detail: str) -> None:
        self.status = status
        where = f"HTTP {status}" if status is not None else "no response"
        super().__init__(f"{method} {url}: {where}: {detail}")


class Api:
    """Minimal JSON client for the /api/v1 of Gitea and Forgejo."""

    def __init__(self, base_url: str, token: str) -> None:
        self.base_url = base_url.rstrip("/")
        self._token = token

    def request(
        self,
        method: str,
        path: str,
        body: JsonObject | None = None,
        timeout: float = API_TIMEOUT_SECONDS,
    ) -> Any:
        url = f"{self.base_url}/api/v1{path}"
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(url, data=data, method=method)
        request.add_header("Authorization", f"token {self._token}")
        request.add_header("Accept", "application/json")
        if data is not None:
            request.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                payload = response.read()
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")[:500]
            raise ApiError(method, url, error.code, detail) from error
        except (urllib.error.URLError, TimeoutError) as error:
            raise ApiError(method, url, None, str(error)) from error
        return json.loads(payload) if payload else None

    def exists(self, path: str) -> bool:
        """True on 200, False on 404; any other failure is raised."""
        try:
            self.request("GET", path)
        except ApiError as error:
            if error.status == 404:
                return False
            raise
        return True

    def paginate(self, path: str) -> Iterator[Any]:
        """Yields the items of a paged list. Some endpoints (repos/search)
        wrap the list as {"ok": ..., "data": [...]}."""
        separator = "&" if "?" in path else "?"
        page = 1
        while True:
            result = self.request(
                "GET", f"{path}{separator}limit={PAGE_SIZE}&page={page}"
            )
            items = result.get("data", []) if isinstance(result, dict) else result
            if not items:
                return
            yield from items
            if len(items) < PAGE_SIZE:
                return
            page += 1


@dataclass(frozen=True)
class SourceRepo:
    owner: str
    name: str
    clone_url: str
    description: str
    private: bool
    archived: bool
    mirror: bool
    original_url: str
    has_wiki: bool

    @property
    def full_name(self) -> str:
        return f"{self.owner}/{self.name}"

    @property
    def api_path(self) -> str:
        return (
            f"/repos/{urllib.parse.quote(self.owner)}/{urllib.parse.quote(self.name)}"
        )

    @classmethod
    def from_api(cls, data: JsonObject) -> SourceRepo:
        return cls(
            owner=data["owner"]["login"],
            name=data["name"],
            clone_url=data["clone_url"],
            description=data.get("description") or "",
            private=bool(data.get("private")),
            archived=bool(data.get("archived")),
            mirror=bool(data.get("mirror")),
            original_url=data.get("original_url") or "",
            has_wiki=bool(data.get("has_wiki")),
        )


@dataclass(frozen=True)
class Options:
    apply: bool
    unarchive_source: bool
    migrate_timeout: float


def list_source_repos(gitea: Api) -> list[SourceRepo]:
    """All repositories the Gitea token can read. With an admin token this
    includes the private repositories of every user and organisation."""
    repos = [
        SourceRepo.from_api(item)
        for item in gitea.paginate("/repos/search?private=true")
    ]
    return sorted(repos, key=lambda repo: repo.full_name.lower())


def migrate_body(
    repo: SourceRepo, gitea_token: str, with_pulls: bool
) -> JsonObject | None:
    """Request body of POST /repos/migrate, or None when the repository
    cannot be copied (a mirror without upstream URL)."""
    common: JsonObject = {
        "repo_owner": repo.owner,
        "repo_name": repo.name,
        "description": repo.description,
        "private": repo.private,
    }
    if repo.mirror:
        # Gitea's copy of a mirror is only a cache: mirror the upstream again.
        # Credentials of a private upstream are not readable through the API.
        if not repo.original_url:
            return None
        return common | {
            "clone_addr": repo.original_url,
            "service": "git",
            "mirror": True,
        }
    return common | {
        "clone_addr": repo.clone_url,
        "service": "gitea",
        "auth_token": gitea_token,
        "mirror": False,
        "wiki": repo.has_wiki,
        "lfs": True,
        "issues": True,
        "pull_requests": with_pulls,
        "labels": True,
        "milestones": True,
        "releases": True,
    }


class MigrationError(Exception):
    """A repository or its owner cannot be copied; the message says why and
    what was left in Forgejo."""


def org_body(name: str, org: JsonObject) -> JsonObject:
    """Request body of POST /orgs, from a Gitea organisation."""
    return {
        "username": name,
        "full_name": org.get("full_name") or "",
        "description": org.get("description") or "",
        "website": org.get("website") or "",
        "location": org.get("location") or "",
        "visibility": org.get("visibility") or "public",
    }


def user_body(user: JsonObject) -> JsonObject:
    """Request body of POST /admin/users, from a Gitea user. The account is
    never made admin. Its password is random and thrown away: the owner must
    get a new one before logging in, and change it at first login."""
    email = user.get("email") or ""
    if "@" not in email:
        raise MigrationError(
            f"the email of user {user['login']} is not readable in Gitea: "
            "use a token of a Gitea admin"
        )
    return {
        "username": user["login"],
        "email": email,
        "full_name": user.get("full_name") or "",
        "visibility": user.get("visibility") or "public",
        "password": secrets.token_urlsafe(CREATED_USER_PASSWORD_BYTES),
        "must_change_password": True,
        "send_notify": False,
    }


def ensure_owner(owner: str, gitea: Api, forgejo: Api, apply: bool) -> None:
    """Creates the owner in Forgejo when it is missing there, as an
    organisation or a user account like in Gitea. Raises ApiError or
    MigrationError when this fails."""
    quoted = urllib.parse.quote(owner)
    if forgejo.exists(f"/users/{quoted}"):
        return
    if gitea.exists(f"/orgs/{quoted}"):
        if apply:
            org = gitea.request("GET", f"/orgs/{quoted}")
            forgejo.request("POST", "/orgs", org_body(owner, org))
        print(f"create organisation {owner}")
        return
    user = gitea.request("GET", f"/users/{quoted}")
    body = user_body(user)
    if apply:
        forgejo.request("POST", "/admin/users", body)
    print(f"create user {owner}")


def post_migration(
    repo: SourceRepo, body: JsonObject, forgejo: Api, timeout: float
) -> None:
    """Runs one migration. A 5xx answer means the migration ran and failed:
    the partial repository Forgejo keeps would be skipped as already copied
    on the next run, so it is deleted. The repository did not exist before
    (checked by the caller). Other answers (4xx) are refused requests that
    created nothing. Without an answer (timeout), Forgejo may still be
    copying, so nothing is deleted."""
    try:
        forgejo.request("POST", "/repos/migrate", body, timeout=timeout)
    except ApiError as error:
        if error.status is None:
            raise MigrationError(
                f"{error} (Forgejo may still be copying: check {repo.full_name} "
                "in Forgejo before running again)"
            ) from error
        if error.status >= 500 and forgejo.exists(repo.api_path):
            forgejo.request("DELETE", repo.api_path)
            raise MigrationError(f"{error} (partial copy deleted)") from error
        raise


def migrate_repo(
    repo: SourceRepo, gitea: Api, forgejo: Api, gitea_token: str, options: Options
) -> bool:
    """Copies one repository. Returns False when it is skipped."""
    unarchive = repo.archived and not repo.mirror and options.unarchive_source
    with_pulls = not repo.archived or unarchive
    body = migrate_body(repo, gitea_token, with_pulls)
    if body is None:
        print(f"skip {repo.full_name}: mirror without upstream URL")
        return False
    if options.apply:
        if unarchive:
            gitea.request("PATCH", repo.api_path, {"archived": False})
            try:
                post_migration(repo, body, forgejo, options.migrate_timeout)
            finally:
                gitea.request("PATCH", repo.api_path, {"archived": True})
        else:
            post_migration(repo, body, forgejo, options.migrate_timeout)
        if repo.archived:
            forgejo.request("PATCH", repo.api_path, {"archived": True})
    notes = []
    if repo.archived:
        notes.append("archived")
        if not repo.mirror:
            notes.append(
                "unarchived in Gitea during the copy"
                if unarchive
                else "without pull requests"
            )
    kind = "mirror" if repo.mirror else "copy"
    print(f"{kind} {repo.full_name}" + "".join(f", {note}" for note in notes))
    return True


def list_packages(gitea: Api, owners: Sequence[str]) -> list[str]:
    lines = []
    for owner in owners:
        for package in gitea.paginate(f"/packages/{urllib.parse.quote(owner)}"):
            lines.append(
                f"{package['type']} {owner}/{package['name']}:{package['version']}"
            )
    return lines


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=(__doc__ or "").splitlines()[0])
    parser.add_argument(
        "--source", required=True, help="Gitea URL, e.g. https://git.home.lan"
    )
    parser.add_argument("--target", required=True, help="Forgejo URL")
    parser.add_argument(
        "--only",
        action="append",
        default=[],
        metavar="OWNER/REPO",
        help="copy only this repository (repeatable)",
    )
    parser.add_argument(
        "--unarchive-source",
        action="store_true",
        help="unarchive archived repositories in Gitea during their copy, to keep their "
        "pull requests (the Gitea token then needs write:repository)",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="make the changes (default: print the plan)",
    )
    parser.add_argument(
        "--migrate-timeout",
        type=float,
        default=DEFAULT_MIGRATE_TIMEOUT_SECONDS,
        help="seconds allowed for one repository (default: %(default)s)",
    )
    return parser.parse_args(argv)


def read_token(name: str) -> str:
    token = os.environ.get(name, "").strip()
    if not token:
        raise SystemExit(f"error: set {name}")
    return token


def run(argv: Sequence[str]) -> int:
    args = parse_args(argv)
    options = Options(
        apply=args.apply,
        unarchive_source=args.unarchive_source,
        migrate_timeout=args.migrate_timeout,
    )
    gitea_token = read_token("GITEA_TOKEN")
    gitea = Api(args.source, gitea_token)
    forgejo = Api(args.target, read_token("FORGEJO_TOKEN"))
    if not options.apply:
        print("dry run: nothing is changed, add --apply to run the plan")

    repos = list_source_repos(gitea)
    if args.only:
        wanted = {name.lower() for name in args.only}
        repos = [repo for repo in repos if repo.full_name.lower() in wanted]
        missing = wanted - {repo.full_name.lower() for repo in repos}
        if missing:
            print(
                f"error: not found in Gitea: {', '.join(sorted(missing))}",
                file=sys.stderr,
            )
            return 2

    failures = 0
    owner_problems: dict[str, str | None] = {}
    for repo in repos:
        if repo.owner not in owner_problems:
            try:
                ensure_owner(repo.owner, gitea, forgejo, options.apply)
                owner_problems[repo.owner] = None
            except (ApiError, MigrationError) as error:
                print(f"FAILED owner {repo.owner}: {error}", file=sys.stderr)
                owner_problems[repo.owner] = "its owner could not be created"
        problem = owner_problems[repo.owner]
        if problem is not None:
            print(f"skip {repo.full_name}: {problem}")
            failures += 1
            continue
        try:
            if forgejo.exists(repo.api_path):
                print(f"skip {repo.full_name}: already in Forgejo")
                continue
            migrate_repo(repo, gitea, forgejo, gitea_token, options)
        except (ApiError, MigrationError) as error:
            print(f"FAILED {repo.full_name}: {error}", file=sys.stderr)
            failures += 1

    owners = sorted({repo.owner for repo in repos})
    try:
        packages = list_packages(gitea, owners)
    except ApiError as error:
        print(f"FAILED listing packages: {error}", file=sys.stderr)
        failures += 1
        packages = []
    if packages:
        print("packages to push again by hand (not copied by Forgejo):")
        for line in packages:
            print(f"  {line}")

    print(f"{len(repos)} repositories, {failures} problem(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(run(sys.argv[1:]))
