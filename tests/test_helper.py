"""Tests for bin/omasnapper-helper, run against a stub `snapper` on PATH.

Run: python3 -m unittest discover -s tests
"""

import json
import os
import subprocess
import tempfile
import textwrap
import unittest

HELPER = os.path.join(os.path.dirname(__file__), "..", "bin", "omasnapper-helper")

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
        self.config = {"ALLOW_USERS": "ks", "NUMBER_CLEANUP": "yes", "NUMBER_LIMIT": "5",
                       "TIMELINE_CREATE": "no", "TIMELINE_LIMIT_HOURLY": "10"}
        self.status_out = "c..... /etc/hostname\n+..... /usr/bin/new tool\n-..... /usr/lib/old.so\n"

    def tearDown(self):
        self.tmp.cleanup()

    def run_helper(self, *args):
        data = os.path.join(self.tmp.name, "data.json")
        with open(data, "w") as f:
            json.dump({"configs": LIST_CONFIGS, "root": self.snaps,
                       "config": self.config, "status": self.status_out,
                       "deny": getattr(self, "deny", False)}, f)
        stub = os.path.join(self.tmp.name, "snapper")
        with open(stub, "w") as f:
            f.write(textwrap.dedent("""\
                #!/usr/bin/env python3
                import json, sys
                with open(%r, "a") as log:
                    log.write(json.dumps(sys.argv[1:]) + "\\n")
                data = json.load(open(%r))
                args = sys.argv[1:]
                if data.get("deny"):
                    print("No permissions.")
                    sys.exit(1)
                if "get-config" in args:
                    print(json.dumps(data["config"]))
                elif "status" in args:
                    sys.stdout.write(data["status"])
                elif "list-configs" in args:
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

    def test_status_reports_retention_settings(self):
        _, doc = self.run_helper("status")
        self.assertEqual(doc["settings"], {"keep": 5, "auto_delete": True, "schedule": "off", "browse": False})

    def test_status_reads_hourly_schedule(self):
        self.config.update({"TIMELINE_CREATE": "yes", "TIMELINE_LIMIT_HOURLY": "12", "SYNC_ACL": "yes"})
        _, doc = self.run_helper("status")
        self.assertEqual(doc["settings"]["schedule"], "hourly")
        self.assertTrue(doc["settings"]["browse"])

    def test_status_marks_pinned_snapshots(self):
        pinned = snap(7)
        pinned["cleanup"] = ""
        self.snaps.append(pinned)
        _, doc = self.run_helper("status")
        self.assertEqual({s["number"]: s["pinned"] for s in doc["snapshots"]}, {7: True, 6: False, 5: False})

    def test_pin_clears_cleanup_algorithm(self):
        rc, _ = self.run_helper("pin", "root", "5", "on")
        self.assertEqual(rc, 0)
        self.assertIn(["-c", "root", "modify", "--cleanup-algorithm", "", "5"], self.calls())

    def test_unpin_restores_number_cleanup(self):
        self.run_helper("pin", "root", "5", "off")
        self.assertIn(["-c", "root", "modify", "--cleanup-algorithm", "number", "5"], self.calls())

    def test_rename_sets_description(self):
        rc, _ = self.run_helper("rename", "root", "5", "before kernel swap")
        self.assertEqual(rc, 0)
        self.assertIn(["-c", "root", "modify", "--description", "before kernel swap", "5"], self.calls())

    def test_files_lists_changes_since_snapshot(self):
        rc, doc = self.run_helper("files", "root", "5")
        self.assertEqual(rc, 0)
        self.assertIn(["-c", "root", "status", "5..0"], self.calls())
        self.assertEqual(doc["files"], [
            {"change": "changed", "path": "/etc/hostname"},
            {"change": "added", "path": "/usr/bin/new tool"},
            {"change": "removed", "path": "/usr/lib/old.so"},
        ])
        self.assertEqual(doc["total"], 3)

    def test_denied_access_explains_allow_users(self):
        self.deny = True
        rc, doc = self.run_helper("status")
        self.assertNotEqual(rc, 0)
        self.assertIn("ALLOW_USERS", doc["error"])

    def test_status_gives_each_snapshot_its_folder(self):
        _, doc = self.run_helper("status")
        self.assertEqual(doc["snapshots"][0]["path"], "/.snapshots/6/snapshot")

    def test_status_lists_each_config_snapshot_folder(self):
        _, doc = self.run_helper("status")
        self.assertEqual(doc["locations"], [{"config": "root", "subvolume": "/", "path": "/.snapshots"}])


if __name__ == "__main__":
    unittest.main()
