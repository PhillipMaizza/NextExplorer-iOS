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
        self.assertEqual(check.count_in("let date = MockDate.date\nlet id = UUID(0)\n"), {})

    def test_wall_clock_dates_are_found(self):
        self.assertEqual(check.count_in("let a = Date()\nlet b = Date.now\n"), {"Date()": 1, "Date.now": 1})

    def test_a_literal_epoch_date_is_found_but_longer_names_are_not(self):
        self.assertEqual(check.count_in("Date(timeIntervalSince1970: 3)\nMockDate()\nStartDate()\n"), {"Date(timeIntervalSince1970:)": 1})

    def test_random_uuids_are_found_but_numbered_ones_are_not(self):
        self.assertEqual(check.count_in("UUID()\nUUID(0)\nUUID(uuidString: \"x\")\n"), {"UUID()": 1})

    def test_real_time_waits_are_found(self):
        counts = check.count_in("try await Task.sleep(for: .seconds(1))\nThread.sleep(forTimeInterval: 1)\nusleep(5)\n")
        self.assertEqual(counts, {"Task.sleep": 1, "Thread.sleep": 2})

    def test_a_clock_sleep_is_found_too(self):
        self.assertEqual(check.count_in("try await clock.sleep(for: .seconds(1))\n"), {"clock.sleep": 1})

    def test_inline_json_is_found_but_fixture_reads_are_not(self):
        code = 'let a = Data(#"{"id":1}"#.utf8)\nlet b = Data("[1]".utf8)\nlet c = "{\\"id\\":1}"\n'
        self.assertEqual(check.count_in(code), {"inline JSON": 3})
        self.assertEqual(check.count_in("let d = try Fixture.data(FilesClientFixture.userAdmin, bundle: .module)\n"), {})

    def test_a_file_over_the_line_limit_counts_the_excess(self):
        self.assertEqual(check.count_in("\n" * 650), {"lines over 600": 51})
        self.assertEqual(check.count_in("\n" * 599), {})

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
    def test_no_uses_means_no_violations(self):
        self.assertEqual(check.violations({}), [])

    def test_every_use_is_a_violation(self):
        self.assertEqual(
            check.violations({"A.swift": {"Date()": 2, "Task.sleep": 1}, "B.swift": {"UUID()": 1}}),
            ["A.swift: Date() x2", "A.swift: Task.sleep x1", "B.swift: UUID() x1"],
        )


if __name__ == "__main__":
    unittest.main()
