#!/usr/bin/env python3
"""Self check for check-test-determinism.py: python3 Scripts/test_check_test_determinism.py"""
import importlib.util
import pathlib
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent / "check-test-determinism.py"
spec = importlib.util.spec_from_file_location("check_test_determinism", SCRIPT)
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


class CountTests(unittest.TestCase):
    def test_a_clean_file_has_no_uses(self):
        self.assertEqual(check.count_in("let date = Date(timeIntervalSince1970: 1)\nlet id = UUID(0)\n"), {})

    def test_wall_clock_dates_are_found(self):
        self.assertEqual(check.count_in("let a = Date()\nlet b = Date.now\n"), {"Date()": 1, "Date.now": 1})

    def test_a_date_with_arguments_or_a_longer_name_is_not_a_wall_clock_date(self):
        self.assertEqual(check.count_in("Date(timeIntervalSince1970: 3)\nMockDate()\nStartDate()\n"), {})

    def test_random_uuids_are_found_but_numbered_ones_are_not(self):
        self.assertEqual(check.count_in("UUID()\nUUID(0)\nUUID(uuidString: \"x\")\n"), {"UUID()": 1})

    def test_real_time_waits_are_found(self):
        counts = check.count_in("try await Task.sleep(for: .seconds(1))\nThread.sleep(forTimeInterval: 1)\nusleep(5)\n")
        self.assertEqual(counts, {"Task.sleep": 1, "Thread.sleep": 2})

    def test_a_clock_sleep_is_found_too(self):
        self.assertEqual(check.count_in("try await clock.sleep(for: .seconds(1))\n"), {"clock.sleep": 1})

    def test_real_clocks_are_found_but_test_clocks_are_not(self):
        self.assertEqual(check.count_in("let a = ContinuousClock()\nlet b = TestClock()\nlet c = ImmediateClock()\n"), {"ContinuousClock()": 1})

    def test_loose_exhaustivity_is_found(self):
        self.assertEqual(
            check.count_in("store.exhaustivity = .off\nstore.exhaustivity = .off(showSkippedAssertions: false)\nawait store.skipReceivedActions()\n"),
            {"exhaustivity off": 2, "skipReceivedActions": 1},
        )

    def test_system_randomness_is_found_but_a_seeded_generator_is_not(self):
        self.assertEqual(check.count_in("Int.random(in: 0..<3)\nitems.shuffled()\nFuzzStrings.random(using: &rng, maxLength: 4)\n"), {"random": 2})

    def test_a_comment_is_not_code(self):
        self.assertEqual(check.count_in("// Date() is not used here\nlet x = 1 // UUID()\n"), {})


class ViolationTests(unittest.TestCase):
    def test_a_count_at_the_baseline_passes(self):
        self.assertEqual(check.violations({"A.swift": {"Date()": 2}}, {"A.swift": {"Date()": 2}}), [])

    def test_a_count_below_the_baseline_passes(self):
        self.assertEqual(check.violations({"A.swift": {"Date()": 1}}, {"A.swift": {"Date()": 2}}), [])

    def test_a_count_above_the_baseline_fails(self):
        self.assertEqual(len(check.violations({"A.swift": {"Date()": 3}}, {"A.swift": {"Date()": 2}})), 1)

    def test_a_new_file_may_use_none(self):
        self.assertEqual(len(check.violations({"New.swift": {"UUID()": 1}}, {"A.swift": {"UUID()": 9}})), 1)

    def test_a_new_kind_of_use_in_a_known_file_fails(self):
        self.assertEqual(len(check.violations({"A.swift": {"Date()": 1, "Task.sleep": 1}}, {"A.swift": {"Date()": 1}})), 1)


if __name__ == "__main__":
    unittest.main()
