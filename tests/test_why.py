"""Tests for the "why was this snapshot made" text in bin/snapper-helper."""

import os
import time
import unittest

from helper_module import load_helper

sh = load_helper()

PACMAN_LOG = """\
[2026-09-21T18:11:12+0000] [PACMAN] Running 'pacman -Sy --noconfirm archlinux-keyring'
[2026-09-21T18:11:12+0000] [ALPM] transaction started
[2026-09-21T18:11:13+0000] [ALPM] transaction completed
[2026-09-21T18:11:13+0000] [PACMAN] Running 'pacman -Syu --noconfirm'
[2026-09-21T18:11:20+0000] [ALPM] upgraded mesa (26.1.0-1 -> 26.1.1-1)
[2026-09-21T18:11:21+0000] [ALPM] upgraded omarchy (4.0.4-1 -> 4.0.5-1)
[2026-09-21T18:11:22+0000] [ALPM] installed foo (1.0-1)
[2026-09-21T18:11:23+0000] [ALPM] removed bar (2.0-1)
[2026-09-24T18:11:12+0000] [PACMAN] Running 'pacman -Syu --noconfirm'
[2026-09-24T18:11:13+0000] [ALPM] upgraded mesa (26.1.1-1 -> 26.1.2-1)
[2026-09-24T19:30:00+0000] [ALPM] upgraded later-by-hand (1-1 -> 2-1)
"""


def snap(date, description="4.0.4-1", user="root", cleanup="number"):
    return {"number": 7, "date": date, "user": user, "cleanup": cleanup,
            "description": description}


class WhyTest(unittest.TestCase):
    def setUp(self):
        self.old_tz = os.environ.get("TZ")
        os.environ["TZ"] = "UTC"
        time.tzset()
        self.events = sh.parse_pacman_log(PACMAN_LOG)

    def tearDown(self):
        if self.old_tz is None:
            del os.environ["TZ"]
        else:
            os.environ["TZ"] = self.old_tz
        time.tzset()

    def why(self, s):
        return sh.describe(s, self.events)

    def test_omarchy_update_names_version_change(self):
        w = self.why(snap("2026-09-21 18:11:11"))
        self.assertEqual(w["origin"], "omarchy-update")
        self.assertEqual(w["title"], "Before Omarchy update")
        self.assertEqual(w["detail"], "4.0.4 → 4.0.5 · 4 packages")

    def test_omarchy_update_counts_only_packages_from_that_update(self):
        w = self.why(snap("2026-09-24 18:11:11"))
        self.assertEqual(w["detail"], "4.0.4 · 1 package")

    def test_omarchy_update_with_no_changes(self):
        w = self.why(snap("2026-09-25 22:44:02"))
        self.assertEqual(w["detail"], "4.0.4 · no changes")

    def test_manual_snapshot_names_its_maker(self):
        w = self.why(snap("2026-09-25 22:44:02", "Manual snapshot", user="ks", cleanup="number"))
        self.assertEqual(w["origin"], "manual")
        self.assertEqual(w["title"], "Manual snapshot")
        self.assertEqual(w["detail"], "Made by ks")

    def test_restore_safety_copy(self):
        w = self.why(snap("2026-09-25 22:44:02", "backup before restore #6", cleanup=""))
        self.assertEqual(w["origin"], "restore-backup")
        self.assertEqual(w["title"], "Safety copy before restore")
        self.assertEqual(w["detail"], "Taken before restoring #6")

    def test_unknown_root_snapshot_keeps_description(self):
        w = self.why(snap("2026-09-25 22:44:02", "before kernel swap", cleanup=""))
        self.assertEqual(w["origin"], "other")
        self.assertEqual(w["title"], "before kernel swap")
        self.assertEqual(w["detail"], "Made by root")


if __name__ == "__main__":
    unittest.main()
