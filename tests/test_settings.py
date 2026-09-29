"""Tests for the retention and schedule plan in bin/omasnapper-helper."""

import unittest

from helper_module import load_helper

sh = load_helper()


class SettingsPlanTest(unittest.TestCase):
    def test_keep_sets_both_number_limits(self):
        plan = sh.settings_plan(8, True, "off")
        self.assertEqual(plan["config"]["NUMBER_LIMIT"], "8")
        self.assertEqual(plan["config"]["NUMBER_LIMIT_IMPORTANT"], "8")
        self.assertEqual(plan["config"]["NUMBER_CLEANUP"], "yes")

    def test_boot_menu_holds_every_kept_snapshot_plus_one(self):
        # One spare slot covers the window between a new snapshot and cleanup,
        # as in Omarchy's own MAX_SNAPSHOT_ENTRIES=6 for NUMBER_LIMIT=5.
        self.assertEqual(sh.settings_plan(8, True, "off")["max_entries"], "9")

    def test_boot_menu_counts_scheduled_snapshots(self):
        self.assertEqual(sh.settings_plan(5, True, "daily")["max_entries"], "13")
        self.assertEqual(sh.settings_plan(5, True, "hourly")["max_entries"], "25")

    def test_no_auto_delete_leaves_boot_menu_size_to_limine(self):
        plan = sh.settings_plan(5, False, "off")
        self.assertEqual(plan["config"]["NUMBER_CLEANUP"], "no")
        self.assertEqual(plan["max_entries"], "auto")

    def test_schedule_off_disables_timeline(self):
        plan = sh.settings_plan(5, True, "off")
        self.assertEqual(plan["config"]["TIMELINE_CREATE"], "no")
        self.assertFalse(plan["timer"])

    def test_daily_schedule_keeps_seven_days(self):
        plan = sh.settings_plan(5, True, "daily")
        self.assertEqual(plan["config"]["TIMELINE_CREATE"], "yes")
        self.assertEqual(plan["config"]["TIMELINE_LIMIT_DAILY"], "7")
        self.assertEqual(plan["config"]["TIMELINE_LIMIT_HOURLY"], "0")
        self.assertTrue(plan["timer"])

    def test_hourly_schedule_keeps_twelve_hours_and_seven_days(self):
        plan = sh.settings_plan(5, True, "hourly")
        self.assertEqual(plan["config"]["TIMELINE_LIMIT_HOURLY"], "12")
        self.assertEqual(plan["config"]["TIMELINE_LIMIT_DAILY"], "7")

    def test_rejects_out_of_range_keep(self):
        with self.assertRaises(ValueError):
            sh.settings_plan(0, True, "off")
        with self.assertRaises(ValueError):
            sh.settings_plan(51, True, "off")

    def test_rejects_unknown_schedule(self):
        with self.assertRaises(ValueError):
            sh.settings_plan(5, True, "weekly")


if __name__ == "__main__":
    unittest.main()
