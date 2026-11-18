#!/usr/bin/env python3
"""Tests for h5ai_shares.py. Run: python3 -I ng/scripts/test_h5ai_shares.py"""

import importlib.util
import pathlib
import tempfile
import unittest

_PATH = pathlib.Path(__file__).with_name("h5ai_shares.py")
_SPEC = importlib.util.spec_from_file_location("h5ai_shares", _PATH)
shares = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(shares)

COMPOSE = """\
services:
  h5ai:
    volumes:
      - cache:/cache
      # BEGIN h5ai-shares mounts
      - stale:/share/stale:ro
      # END h5ai-shares mounts
    networks:
      - web

volumes:
  movies:
    driver: local
  # BEGIN h5ai-shares volumes
  h5ai_share_stale:
    driver: local
  # END h5ai-shares volumes

networks:
  web:
"""


def mounts(text):
    lines = text.split("\n")
    begin = next(
        i for i, line in enumerate(lines) if "# BEGIN h5ai-shares mounts" in line
    )
    end = lines.index("      # END h5ai-shares mounts")
    return [line.strip() for line in lines[begin + 1 : end]]


class Render(unittest.TestCase):
    def test_each_type_becomes_a_read_only_mount(self):
        conf = "${PHOTOS_PATH}/x:b\nnfs:${MEDIA_BASE_PATH}/C:c  # trailing comment\n"
        out = shares.render(COMPOSE, conf)
        self.assertEqual(
            mounts(out),
            [
                "- ${PHOTOS_PATH}/x:/share/b:ro",
                "- h5ai_share_c:/share/c:ro",
            ],
        )
        self.assertIn(
            "  h5ai_share_c:\n    driver: local\n    driver_opts:\n      <<: *nfs-driver-opts\n"
            "      device: :${MEDIA_BASE_PATH}/C\n  # END h5ai-shares volumes",
            out,
        )

    def test_previous_generated_content_is_replaced(self):
        out = shares.render(COMPOSE, "/x:a\n")
        self.assertNotIn("stale", out)

    def test_empty_list_keeps_markers_and_rest_of_file(self):
        out = shares.render(COMPOSE, "# nothing\n\n")
        self.assertEqual(mounts(out), [])
        self.assertIn("      - cache:/cache\n", out)
        self.assertIn("networks:\n  web:\n", out)

    def test_render_is_idempotent(self):
        conf = "/x/A:a\nnfs:/x/C:c\n"
        once = shares.render(COMPOSE, conf)
        self.assertEqual(shares.render(once, conf), once)

    def test_hash_inside_path_is_not_a_comment(self):
        out = shares.render(COMPOSE, "nfs:${MEDIA_BASE_PATH}/#recycle:trash\n")
        self.assertIn("device: :${MEDIA_BASE_PATH}/#recycle", out)

    def test_any_number_of_shares(self):
        conf = "".join(f"nfs:/export/s{i}:s{i}\n" for i in range(50))
        out = shares.render(COMPOSE, conf)
        self.assertEqual(len(mounts(out)), 50)
        self.assertEqual(out.count("<<: *nfs-driver-opts"), 50)


class Rejected(unittest.TestCase):
    def assertRejected(self, conf, compose=COMPOSE):
        with self.assertRaises(shares.ShareError):
            shares.render(compose, conf)

    def test_old_three_field_format(self):
        self.assertRejected("a nfs /x\n")
        self.assertRejected("a\tbind\t/x\n")

    def test_missing_destination(self):
        for conf in ("/x\n", "nfs:/x\n", "/x:\n", ":a\n", "nfs::a\n"):
            with self.subTest(conf=conf):
                self.assertRejected(conf)

    def test_generated_name_must_not_clash_with_a_declared_volume(self):
        self.assertRejected(
            "nfs:/x:x\n", COMPOSE.replace("  movies:\n", "  h5ai_share_x:\n")
        )

    def test_duplicate_name(self):
        self.assertRejected("/y:a\nnfs:/x:a\n")

    def test_unknown_scheme(self):
        self.assertRejected("smb:/x:a\n")

    def test_mount_options_are_not_accepted(self):
        self.assertRejected("/x:a:ro\n")

    def test_bad_names_and_paths(self):
        for conf in (
            "/x:../a\n",
            "relative/x:a\n",
            "/x:/y:a\n",
            "/x'y:a\n",
            "nfs:$HOME:a\n",
            "/x//y:a\n",
        ):
            with self.subTest(conf=conf):
                self.assertRejected(conf)

    def test_missing_or_duplicated_markers(self):
        self.assertRejected(
            "/x:a\n", COMPOSE.replace("      # END h5ai-shares mounts\n", "")
        )
        doubled = COMPOSE.replace(
            "  # END h5ai-shares volumes\n", "  # END h5ai-shares volumes\n" * 2
        )
        self.assertRejected("/x:a\n", doubled)


class Cli(unittest.TestCase):
    def test_check_fails_when_out_of_date_and_write_fixes_it(self):
        with tempfile.TemporaryDirectory() as tmp:
            compose = pathlib.Path(tmp, "docker-compose.yml")
            conf = pathlib.Path(tmp, "h5ai-shares.conf")
            compose.write_text(COMPOSE, encoding="utf-8")
            conf.write_text("/x:a\n", encoding="utf-8")
            args = ["--conf", str(conf), "--compose", str(compose)]
            self.assertEqual(shares.main(["--check", *args]), 1)
            self.assertEqual(compose.read_text(encoding="utf-8"), COMPOSE)
            self.assertEqual(shares.main(args), 0)
            self.assertEqual(shares.main(["--check", *args]), 0)

    def test_invalid_conf_leaves_compose_untouched(self):
        with tempfile.TemporaryDirectory() as tmp:
            compose = pathlib.Path(tmp, "docker-compose.yml")
            conf = pathlib.Path(tmp, "h5ai-shares.conf")
            compose.write_text(COMPOSE, encoding="utf-8")
            conf.write_text("a nfs /x\n", encoding="utf-8")
            self.assertEqual(
                shares.main(["--conf", str(conf), "--compose", str(compose)]), 2
            )
            self.assertEqual(compose.read_text(encoding="utf-8"), COMPOSE)

    def test_repository_compose_is_up_to_date(self):
        self.assertEqual(shares.main(["--check"]), 0)


if __name__ == "__main__":
    unittest.main()
