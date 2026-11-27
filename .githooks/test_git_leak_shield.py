#!/usr/bin/env python3
"""Tests for git-leak-shield.py. Run: python3 -I .githooks/test_git_leak_shield.py"""

import importlib.util
import pathlib
import unittest

_PATH = pathlib.Path(__file__).with_name("git-leak-shield.py")
_SPEC = importlib.util.spec_from_file_location("git_leak_shield", _PATH)
shield = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(shield)


def finding_types(line, filepath="stack/vector.yaml"):
    return [f["type"] for f in shield.inspect_line(line, filepath, 1)]


class FalsePositives(unittest.TestCase):
    def test_wildcard_listen_address_is_not_an_ip_leak(self):
        self.assertEqual(finding_types("    address: 0.0.0.0:5514"), [])

    def test_vector_secret_reference_is_not_a_password(self):
        line = "      password: SECRET[compose.openobserve_ingest_password]"
        self.assertEqual(finding_types(line), [])

    def test_rfc5737_documentation_ips_are_not_leaks(self):
        line = '          message: "src=192.0.2.124 dst=198.51.100.7 nat=203.0.113.9"'
        self.assertEqual(finding_types(line, "stack/tests/vector_test.yaml"), [])


class RealLeaksStillDetected(unittest.TestCase):
    def test_hardcoded_password(self):
        self.assertIn("SECRET", finding_types("      password: hunter2secret"))

    def test_password_merely_prefixed_with_secret_word(self):
        self.assertIn("SECRET", finding_types("      password: SECRET123"))

    def test_private_ip(self):
        self.assertIn("PRIVATE_IP", finding_types("    address: 192.168.1.10:5514"))

    def test_public_ip_next_to_a_documentation_range(self):
        self.assertIn("PUBLIC_IP", finding_types("    address: 192.0.20.1:5514"))

    def test_loopback_ip(self):
        self.assertIn("PRIVATE_IP", finding_types("    address: 127.0.0.1:5514"))


if __name__ == "__main__":
    unittest.main()
