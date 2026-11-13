"""Unit tests of migrate_repos.py with a fake API (no network).

The end-to-end behaviour against real Gitea and Forgejo instances is covered
by test_stack.sh. Run with: python3 -m unittest discover -s forgejo/tests
"""

from __future__ import annotations

import importlib.util
import io
import sys
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from typing import Any, ClassVar
from unittest import mock

_SCRIPT = Path(__file__).resolve().parent.parent / "migrate_repos.py"
_spec = importlib.util.spec_from_file_location("migrate_repos", _SCRIPT)
assert _spec is not None and _spec.loader is not None
mr = importlib.util.module_from_spec(_spec)
sys.modules["migrate_repos"] = mr
_spec.loader.exec_module(mr)


class FakeApi(mr.Api):  # type: ignore[misc,name-defined]  # loaded at runtime
    """Records calls; answers from a table keyed by (method, path)."""

    def __init__(self, answers: dict[tuple[str, str], Any] | None = None) -> None:
        super().__init__("http://fake", "token")
        self.answers = answers or {}
        self.calls: list[tuple[str, str, Any]] = []

    def request(
        self, method: str, path: str, body: Any = None, timeout: float = 0
    ) -> Any:
        self.calls.append((method, path, body))
        answer = self.answers.get((method, path))
        if isinstance(answer, Exception):
            raise answer
        if callable(answer):
            return answer()
        return answer

    def methods(self) -> list[tuple[str, str]]:
        return [(method, path) for method, path, _ in self.calls]


def not_found(path: str) -> Any:
    return mr.ApiError("GET", path, 404, "not found")


def repo(**overrides: Any) -> Any:
    fields: dict[str, Any] = {
        "owner": "team",
        "name": "app",
        "clone_url": "https://git.example/team/app.git",
        "description": "",
        "private": False,
        "archived": False,
        "mirror": False,
        "original_url": "",
        "has_wiki": True,
    }
    return mr.SourceRepo(**(fields | overrides))


def options(**overrides: Any) -> Any:
    fields: dict[str, Any] = {
        "apply": True,
        "unarchive_source": False,
        "migrate_timeout": 10,
    }
    return mr.Options(**(fields | overrides))


def quiet(function: Any, *args: Any) -> Any:
    with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
        return function(*args)


class MigrateBodyTest(unittest.TestCase):
    def test_regular_repository_is_copied_with_its_history(self) -> None:
        body = mr.migrate_body(repo(), "secret", True)
        self.assertEqual(body["service"], "gitea")
        self.assertEqual(body["auth_token"], "secret")
        self.assertFalse(body["mirror"])
        self.assertTrue(body["issues"] and body["pull_requests"] and body["releases"])

    def test_mirror_is_recreated_from_its_upstream_without_the_token(self) -> None:
        body = mr.migrate_body(
            repo(mirror=True, original_url="https://github.com/a/b"), "secret", True
        )
        self.assertEqual(body["clone_addr"], "https://github.com/a/b")
        self.assertTrue(body["mirror"])
        self.assertNotIn("auth_token", body)

    def test_mirror_without_upstream_is_not_copied(self) -> None:
        self.assertIsNone(mr.migrate_body(repo(mirror=True), "secret", True))


class MigrateRepoTest(unittest.TestCase):
    def test_archived_repository_is_copied_without_pulls_and_archived(self) -> None:
        gitea, forgejo = FakeApi(), FakeApi()
        quiet(mr.migrate_repo, repo(archived=True), gitea, forgejo, "t", options())
        body = forgejo.calls[0][2]
        self.assertFalse(body["pull_requests"])
        self.assertEqual(
            forgejo.calls[1], ("PATCH", "/repos/team/app", {"archived": True})
        )
        self.assertEqual(gitea.calls, [])

    def test_unarchive_source_restores_the_archive_even_on_failure(self) -> None:
        gitea = FakeApi()
        forgejo = FakeApi(
            {
                ("POST", "/repos/migrate"): mr.ApiError("POST", "x", 500, "boom"),
                ("GET", "/repos/team/app"): not_found("/repos/team/app"),
            }
        )
        with self.assertRaises(mr.ApiError):
            quiet(
                mr.migrate_repo,
                repo(archived=True),
                gitea,
                forgejo,
                "t",
                options(unarchive_source=True),
            )
        self.assertEqual(
            [call[2] for call in gitea.calls], [{"archived": False}, {"archived": True}]
        )
        self.assertTrue(forgejo.calls[0][2]["pull_requests"])

    def test_dry_run_changes_nothing(self) -> None:
        gitea, forgejo = FakeApi(), FakeApi()
        quiet(
            mr.migrate_repo,
            repo(archived=True),
            gitea,
            forgejo,
            "t",
            options(apply=False, unarchive_source=True),
        )
        self.assertEqual(gitea.calls + forgejo.calls, [])


class EnsureOwnerTest(unittest.TestCase):
    gitea_user: ClassVar[dict[str, Any]] = {
        "login": "alice",
        "email": "alice@example.test",
        "full_name": "Alice",
        "visibility": "private",
        "is_admin": True,
    }

    def test_existing_owner_is_left_alone(self) -> None:
        gitea, forgejo = FakeApi(), FakeApi()
        quiet(mr.ensure_owner, "alice", gitea, forgejo, True)
        self.assertEqual(forgejo.methods(), [("GET", "/users/alice")])
        self.assertEqual(gitea.calls, [])

    def test_missing_user_is_created_like_in_gitea_but_never_admin(self) -> None:
        gitea = FakeApi(
            {
                ("GET", "/orgs/alice"): not_found("/orgs/alice"),
                ("GET", "/users/alice"): self.gitea_user,
            }
        )
        forgejo = FakeApi({("GET", "/users/alice"): not_found("/users/alice")})
        quiet(mr.ensure_owner, "alice", gitea, forgejo, True)
        method, path, body = forgejo.calls[-1]
        self.assertEqual((method, path), ("POST", "/admin/users"))
        self.assertEqual(
            (body["username"], body["email"], body["full_name"], body["visibility"]),
            ("alice", "alice@example.test", "Alice", "private"),
        )
        self.assertTrue(body["must_change_password"])
        self.assertFalse(body["send_notify"])
        self.assertNotIn("admin", body)
        self.assertGreaterEqual(len(body["password"]), 32)

    def test_each_created_user_gets_its_own_password(self) -> None:
        first = mr.user_body(self.gitea_user)["password"]
        self.assertNotEqual(first, mr.user_body(self.gitea_user)["password"])

    def test_user_with_hidden_email_is_not_created(self) -> None:
        # Gitea hides the email from tokens of non-admin accounts.
        with self.assertRaisesRegex(mr.MigrationError, "Gitea admin"):
            mr.user_body(self.gitea_user | {"email": ""})

    def test_missing_organisation_is_created_with_its_settings(self) -> None:
        org = {"username": "ignored", "full_name": "The Team", "visibility": "limited"}
        gitea = FakeApi({("GET", "/orgs/team"): org})
        forgejo = FakeApi({("GET", "/users/team"): not_found("/users/team")})
        quiet(mr.ensure_owner, "team", gitea, forgejo, True)
        method, path, body = forgejo.calls[-1]
        self.assertEqual((method, path), ("POST", "/orgs"))
        self.assertEqual(
            (body["username"], body["full_name"], body["visibility"]),
            ("team", "The Team", "limited"),
        )

    def test_dry_run_creates_no_owner(self) -> None:
        gitea = FakeApi(
            {
                ("GET", "/orgs/alice"): not_found("/orgs/alice"),
                ("GET", "/users/alice"): self.gitea_user,
            }
        )
        forgejo = FakeApi({("GET", "/users/alice"): not_found("/users/alice")})
        out = io.StringIO()
        with redirect_stdout(out):
            mr.ensure_owner("alice", gitea, forgejo, False)
        self.assertEqual(out.getvalue(), "create user alice\n")
        self.assertNotIn("POST", [method for method, _ in forgejo.methods()])


class PostMigrationTest(unittest.TestCase):
    def test_server_error_deletes_the_partial_copy(self) -> None:
        forgejo = FakeApi(
            {("POST", "/repos/migrate"): mr.ApiError("POST", "x", 500, "boom")}
        )
        with self.assertRaisesRegex(mr.MigrationError, "partial copy deleted"):
            mr.post_migration(repo(), {}, forgejo, 10)
        self.assertIn(("DELETE", "/repos/team/app"), forgejo.methods())

    def test_timeout_keeps_the_repository(self) -> None:
        forgejo = FakeApi(
            {("POST", "/repos/migrate"): mr.ApiError("POST", "x", None, "timed out")}
        )
        with self.assertRaisesRegex(mr.MigrationError, "may still be copying"):
            mr.post_migration(repo(), {}, forgejo, 10)
        self.assertNotIn("DELETE", [method for method, _ in forgejo.methods()])

    def test_refused_request_deletes_nothing(self) -> None:
        # A 409 may come from a repository created by someone else meanwhile.
        forgejo = FakeApi(
            {("POST", "/repos/migrate"): mr.ApiError("POST", "x", 409, "exists")}
        )
        with self.assertRaises(mr.ApiError):
            mr.post_migration(repo(), {}, forgejo, 10)
        self.assertEqual(forgejo.methods(), [("POST", "/repos/migrate")])


class PaginateTest(unittest.TestCase):
    def test_reads_every_page_of_a_wrapped_list(self) -> None:
        path = "/repos/search?private=true&limit=%d&page=%d"
        api = FakeApi(
            {
                ("GET", path % (mr.PAGE_SIZE, 1)): {"data": list(range(mr.PAGE_SIZE))},
                ("GET", path % (mr.PAGE_SIZE, 2)): {"data": [99]},
            }
        )
        self.assertEqual(len(list(api.paginate("/repos/search?private=true"))), 51)


class RunTest(unittest.TestCase):
    def test_tokens_are_required(self) -> None:
        with (
            self.assertRaises(SystemExit),
            mock.patch.dict("os.environ", {}, clear=True),
        ):
            mr.run(["--source", "http://a", "--target", "http://b"])


if __name__ == "__main__":
    unittest.main()
