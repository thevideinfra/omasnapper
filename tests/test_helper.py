"""Tests for bin/snapper-helper, run against a stub `snapper` on PATH.

Run: python3 -m unittest discover -s tests
"""

import json
import os
import subprocess
import tempfile
import textwrap
import unittest

HELPER = os.path.join(os.path.dirname(__file__), "..", "bin", "snapper-helper")

LIST_CONFIGS = {"configs": [{"config": "root", "subvolume": "/"}]}


def snap(number, description="4.0.4-1", used=None):
    return {
        "number": number, "type": "single", "pre-number": None,
        "date": "2026-09-17 02:04:42" if number else "", "user": "root",
        "cleanup": "number" if number else "", "description": description,
        "userdata": None, "used-space": used,
    }


class HelperTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.log = os.path.join(self.tmp.name, "calls.jsonl")
        self.snaps = [snap(0, "current"), snap(5), snap(6)]

    def tearDown(self):
        self.tmp.cleanup()

    def run_helper(self, *args):
        data = os.path.join(self.tmp.name, "data.json")
        with open(data, "w") as f:
            json.dump({"configs": LIST_CONFIGS, "root": self.snaps}, f)
        stub = os.path.join(self.tmp.name, "snapper")
        with open(stub, "w") as f:
            f.write(textwrap.dedent("""\
                #!/usr/bin/env python3
                import json, sys
                with open(%r, "a") as log:
                    log.write(json.dumps(sys.argv[1:]) + "\\n")
                data = json.load(open(%r))
                args = sys.argv[1:]
                if "list-configs" in args:
                    print(json.dumps(data["configs"]))
                elif "list" in args:
                    print(json.dumps({"root": data["root"]}))
                elif "create" in args:
                    print("9")
                """ % (self.log, data)))
        os.chmod(stub, 0o755)
        env = dict(os.environ, PATH=self.tmp.name + os.pathsep + os.environ["PATH"])
        p = subprocess.run(["python3", HELPER, *args], capture_output=True, text=True, env=env)
        return p.returncode, json.loads(p.stdout)

    def calls(self):
        with open(self.log) as f:
            return [json.loads(line) for line in f]

    def test_status_skips_current_pseudo_snapshot(self):
        rc, doc = self.run_helper("status")
        self.assertEqual(rc, 0)
        self.assertEqual([s["number"] for s in doc["snapshots"]], [6, 5])

    def test_status_tags_snapshots_with_config(self):
        _, doc = self.run_helper("status")
        self.assertEqual({s["config"] for s in doc["snapshots"]}, {"root"})

    def test_status_reports_quota_off_when_used_space_missing(self):
        _, doc = self.run_helper("status")
        self.assertFalse(doc["quota_enabled"])
        self.assertEqual(doc["total_exclusive_bytes"], 0)

    def test_status_sums_used_space_when_quota_on(self):
        self.snaps = [snap(0, "current"), snap(5, used=1000), snap(6, used=500)]
        _, doc = self.run_helper("status")
        self.assertTrue(doc["quota_enabled"])
        self.assertEqual(doc["snapshots"][0]["size"], 500)
        self.assertEqual(doc["total_exclusive_bytes"], 1500)

    def test_description_with_pipe_survives(self):
        self.snaps = [snap(7, "a | b")]
        _, doc = self.run_helper("status")
        self.assertEqual(doc["snapshots"][0]["description"], "a | b")

    def test_delete_targets_only_named_config(self):
        rc, doc = self.run_helper("delete", "root", "5")
        self.assertEqual(rc, 0)
        self.assertIn(["-c", "root", "delete", "5"], self.calls())

    def test_delete_rejects_non_numeric_id(self):
        rc, doc = self.run_helper("delete", "root", "5; rm")
        self.assertNotEqual(rc, 0)
        self.assertFalse(doc["ok"])

    def test_delete_rejects_snapshot_zero(self):
        rc, doc = self.run_helper("delete", "root", "0")
        self.assertNotEqual(rc, 0)

    def test_delete_rejects_unknown_config(self):
        rc, doc = self.run_helper("delete", "home", "5")
        self.assertNotEqual(rc, 0)


if __name__ == "__main__":
    unittest.main()
