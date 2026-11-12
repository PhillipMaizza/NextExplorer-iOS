#!/usr/bin/env python3
"""Self check for ci-platforms.py: python3 Scripts/test_ci_platforms.py"""
import importlib.util
import pathlib
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent / "ci-platforms.py"
spec = importlib.util.spec_from_file_location("ci_platforms", SCRIPT)
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)

MAC_FILE = "#if os(macOS)\n    import SwiftUI\n    struct MacBar {}\n#endif\n"
IOS_FILE = "#if os(iOS)\n    import XCTest\n    final class T {}\n#endif\n"
SHARED_FILE = "import SwiftUI\nstruct Shared {}\n"


class KindTests(unittest.TestCase):
    def test_a_file_wholly_guarded_for_one_platform_belongs_to_it(self):
        self.assertEqual(ci.kind("A.swift", MAC_FILE), ci.MAC)
        self.assertEqual(ci.kind("A.swift", IOS_FILE), ci.IOS)

    def test_an_unguarded_file_is_shared(self):
        self.assertEqual(ci.kind("A.swift", SHARED_FILE), ci.SHARED)

    def test_a_guard_with_an_else_branch_is_shared(self):
        self.assertEqual(ci.kind("A.swift", "#if os(macOS)\nlet a = 1\n#else\nlet a = 2\n#endif\n"), ci.SHARED)
        self.assertEqual(ci.kind("A.swift", "#if os(iOS)\nlet a = 1\n#elseif os(macOS)\nlet a = 2\n#endif\n"), ci.SHARED)

    def test_code_outside_the_guard_makes_the_file_shared(self):
        self.assertEqual(ci.kind("A.swift", MAC_FILE + "struct Both {}\n"), ci.SHARED)
        self.assertEqual(ci.kind("A.swift", "#if os(macOS)\nlet a = 1\n#endif\n#if os(iOS)\nlet b = 1\n#endif\n"), ci.SHARED)

    def test_a_guard_that_is_not_the_first_line_is_shared(self):
        self.assertEqual(ci.kind("A.swift", "import SwiftUI\n#if os(macOS)\nlet a = 1\n#endif\n"), ci.SHARED)

    def test_a_nested_or_compound_condition_is_shared(self):
        self.assertEqual(ci.kind("A.swift", "#if os(macOS) || os(iOS)\nlet a = 1\n#endif\n"), ci.SHARED)

    def test_a_deleted_file_is_shared(self):
        self.assertEqual(ci.kind("Gone.swift", None), ci.SHARED)

    def test_the_mac_entitlements_are_mac_only(self):
        self.assertEqual(ci.kind("NextExplorer/NextExplorer-macOS.entitlements", "<plist/>"), ci.MAC)

    def test_other_files_are_shared(self):
        self.assertEqual(ci.kind("NextExplorer.xcodeproj/project.pbxproj", "x"), ci.SHARED)
        self.assertEqual(ci.kind("NextExplorer/Info.plist", "x"), ci.SHARED)
        self.assertEqual(ci.kind(".github/workflows/ci.yml", "x"), ci.SHARED)

    def test_an_empty_swift_file_is_shared(self):
        self.assertEqual(ci.kind("A.swift", "\n\n"), ci.SHARED)


class NoBuildKindTests(unittest.TestCase):
    def test_docs_screenshots_and_store_text_are_docs(self):
        for path in ["README.md", "docs/guide.md", "LICENSE", "Screenshots/a.png", "fastlane/metadata/en-US/name.txt", "Gemfile.lock", ".ruby-version", ".github/ISSUE_TEMPLATE/bug_report.yml"]:
            self.assertEqual(ci.kind(path, "x"), ci.DOCS, path)

    def test_scripts_checked_in_the_changes_job_are_checked(self):
        for path in ["Scripts/check-test-determinism.py", "Scripts/ci-platforms.py", "Scripts/test_gen_changelog.py", "Scripts/mtls/make-ca.sh"]:
            self.assertEqual(ci.kind(path, "x"), ci.CHECKED, path)

    def test_scripts_the_build_jobs_run_still_build(self):
        self.assertEqual(ci.kind("Scripts/ci-restore-mtimes.py", "x"), ci.SHARED)
        self.assertEqual(ci.kind("Scripts/sync-package-pins.py", "x"), ci.SHARED)

    def test_an_unknown_script_builds(self):
        self.assertEqual(ci.kind("Scripts/new-tool.py", "x"), ci.SHARED)

    def test_lint_config_and_test_fixtures_build(self):
        self.assertEqual(ci.kind(".swiftlint.yml", "x"), ci.SHARED)
        self.assertEqual(ci.kind(".swiftformat", "x"), ci.SHARED)
        self.assertEqual(ci.kind("Packages/CoreModels/Tests/CoreModelsTests/Fixtures/user.json", "{}"), ci.SHARED)


class OutputsTests(unittest.TestCase):
    def test_docs_alone_build_nothing_on_a_pull_request_or_main(self):
        self.assertEqual(ci.outputs([ci.DOCS], "pull_request"), (False, False, False))
        self.assertEqual(ci.outputs([ci.DOCS], "push"), (False, False, False))

    def test_checked_scripts_alone_build_nothing_on_a_pull_request(self):
        self.assertEqual(ci.outputs([ci.CHECKED, ci.DOCS], "pull_request"), (True, False, False))

    def test_checked_scripts_build_everything_on_main(self):
        self.assertEqual(ci.outputs([ci.CHECKED], "push"), (True, True, True))

    def test_a_checked_script_with_a_mac_file_builds_only_the_mac(self):
        self.assertEqual(ci.outputs([ci.CHECKED, ci.MAC], "pull_request"), (True, False, True))

    def test_any_shared_file_builds_both(self):
        self.assertEqual(ci.outputs([ci.CHECKED, ci.SHARED], "pull_request"), (True, True, True))

    def test_main_builds_both_for_a_platform_only_change(self):
        self.assertEqual(ci.outputs([ci.MAC], "push"), (True, True, True))


class PlatformsTests(unittest.TestCase):
    def test_no_code_runs_nothing(self):
        self.assertEqual(ci.platforms([]), (False, False))

    def test_mac_only_changes_skip_ios(self):
        self.assertEqual(ci.platforms([ci.MAC, ci.MAC]), (False, True))

    def test_ios_only_changes_skip_the_mac(self):
        self.assertEqual(ci.platforms([ci.IOS]), (True, False))

    def test_shared_changes_run_both(self):
        self.assertEqual(ci.platforms([ci.SHARED]), (True, True))

    def test_mixed_platform_changes_run_both(self):
        self.assertEqual(ci.platforms([ci.MAC, ci.IOS]), (True, True))

    def test_one_shared_file_among_mac_files_runs_both(self):
        self.assertEqual(ci.platforms([ci.MAC, ci.SHARED]), (True, True))


if __name__ == "__main__":
    unittest.main()
