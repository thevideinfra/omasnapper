"""Tests for the restore driver in bin/omasnapper-helper.

The driver answers limine-snapper-restore's prompts in a pty. These tests
run it against tests/fake_limine_restore.py, which asks the same prompts.
"""

import os
import sys
import tempfile
import unittest

from helper_module import load_helper

sh = load_helper()

FAKE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fake_limine_restore.py")


class RestoreTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.inputs = os.path.join(self.tmp.name, "inputs")
        open(self.inputs, "w").close()

    def tearDown(self):
        self.tmp.cleanup()

    def restore(self, number, scenario="ok"):
        os.environ["FAKE_SCENARIO"] = scenario
        os.environ["FAKE_INPUT_LOG"] = self.inputs
        try:
            return sh.drive_restore([sys.executable, FAKE], number, "Before restoring #%d" % number, timeout=20)
        finally:
            del os.environ["FAKE_SCENARIO"]
            del os.environ["FAKE_INPUT_LOG"]

    def answers(self):
        with open(self.inputs) as f:
            return f.read().splitlines()

    def test_picks_the_snapshot_and_names_the_backup(self):
        result = self.restore(9)
        self.assertTrue(result["ok"], result)
        self.assertEqual(self.answers(), ["9", "Before restoring #9"])

    def test_cancels_when_snapshot_is_not_in_boot_menu(self):
        result = self.restore(3)
        self.assertFalse(result["ok"])
        self.assertIn("boot menu", result["error"])
        self.assertEqual(self.answers(), ["3", "c"])

    def test_cancels_when_snapshot_files_fail_verification(self):
        result = self.restore(9, "corrupt")
        self.assertFalse(result["ok"])
        self.assertIn("verification", result["error"])
        self.assertEqual(self.answers(), ["9", "c"])

    def test_reports_failure_and_closes_the_hold_prompt(self):
        result = self.restore(9, "fail")
        self.assertFalse(result["ok"])
        self.assertIn("The restore failed.", result["error"])
        self.assertEqual(self.answers(), ["9", "Before restoring #9", "y"])


if __name__ == "__main__":
    unittest.main()
