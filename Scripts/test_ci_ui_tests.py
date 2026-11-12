#!/usr/bin/env python3
"""Self check for ci-ui-tests.py: python3 Scripts/test_ci_ui_tests.py"""
import importlib.util
import pathlib
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent / "ci-ui-tests.py"
spec = importlib.util.spec_from_file_location("ci_ui_tests", SCRIPT)
ui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ui)

TARGET = "NextExplorerUITests"
SIGN_OUT = "MacCriticalPathUITests/testSignOutFromTheAccountMenu()"
MOVE = "MacCriticalPathUITests/testMoveDialogOpensAFolderFromTheKeyboard()"


def failure(identifier, target=TARGET):
    # The fields xcresulttool's test-results summary gives for each failed test.
    return {"failureText": "XCTAssertTrue failed", "targetName": target, "testIdentifierString": identifier}


class FailedTestsTests(unittest.TestCase):
    def test_each_failure_becomes_an_only_testing_identifier(self):
        summary = {"testFailures": [failure(SIGN_OUT), failure(MOVE)]}
        self.assertEqual(
            ui.failed_tests(summary),
            [f"{TARGET}/MacCriticalPathUITests/testSignOutFromTheAccountMenu", f"{TARGET}/MacCriticalPathUITests/testMoveDialogOpensAFolderFromTheKeyboard"],
        )

    def test_a_test_with_several_failures_is_listed_once(self):
        summary = {"testFailures": [failure(SIGN_OUT), failure(SIGN_OUT)]}
        self.assertEqual(len(ui.failed_tests(summary)), 1)

    def test_a_run_without_test_failures_has_nothing_to_rerun(self):
        self.assertEqual(ui.failed_tests({}), [])
        self.assertEqual(ui.failed_tests({"testFailures": [{"failureText": "crash"}]}), [])


class ReportTests(unittest.TestCase):
    def test_a_test_passing_only_on_the_rerun_is_a_warning(self):
        lines, summary = ui.report(["T/C/flaky"], [])
        self.assertEqual(lines, ["::warning title=Flaky UI test::T/C/flaky failed, then passed on its rerun. Fix it."])
        self.assertIn("- `T/C/flaky`", summary)

    def test_a_test_failing_twice_is_an_error(self):
        lines, summary = ui.report([], ["T/C/broken"])
        self.assertEqual(lines, ["::error title=UI test failed twice::T/C/broken"])
        self.assertIn("### UI tests that failed twice", summary)

    def test_nothing_to_report_writes_nothing(self):
        self.assertEqual(ui.report([], []), ([], []))


if __name__ == "__main__":
    unittest.main()
