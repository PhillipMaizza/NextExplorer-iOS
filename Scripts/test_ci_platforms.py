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
