#!/usr/bin/env python3
"""Self check for check-comments.py: python3 Scripts/test_check_comments.py"""
import importlib.util
import pathlib
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent / "check-comments.py"
spec = importlib.util.spec_from_file_location("check_comments", SCRIPT)
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


class ScanTests(unittest.TestCase):
    def test_whole_and_trailing_comments_are_found(self):
        self.assertEqual(check.scan("// a\nlet x = 1 // b\n/// c\nlet y = 2"), {1: None, 2: 10, 3: None})

    def test_slashes_inside_strings_are_code(self):
        source = 'let a = "http://x"\nlet b = """\n// sample\n"""\nlet c = #"//"#\nlet d = "\\(f("//"))"'
        self.assertEqual(check.scan(source), {})

    def test_a_comment_after_an_interpolated_string_is_found(self):
        self.assertEqual(check.scan('let a = "\\(f("x"))" // t'), {1: 20})

    def test_block_comments_cover_every_line(self):
        self.assertEqual(check.scan("/* a\n b\n */\nlet x = 1"), {1: None, 2: None, 3: None})

    def test_directives_are_not_counted(self):
        self.assertEqual(check.scan("// MARK: - A\n// swiftlint:disable x\n// swiftformat:disable y"), {})


class DeleteTests(unittest.TestCase):
    def test_a_block_goes_with_its_lines_and_a_trailing_comment_is_cut(self):
        source = "// one\n// two\nlet x = 1 // tail\n// kept\nlet y = 2"
        self.assertEqual(check.delete(source, {1, 3}), "let x = 1\n// kept\nlet y = 2")


class RatchetTests(unittest.TestCase):
    def test_a_file_over_its_baseline_or_new_with_comments_fails(self):
        findings = check.grown({"A.swift": 3, "B.swift": 1, "C.swift": 2}, {"A.swift": 2, "C.swift": 5})
        self.assertEqual([finding.split(":")[0] for finding in findings], ["A.swift", "B.swift"])

    def test_fewer_comments_pass(self):
        self.assertEqual(check.grown({"A.swift": 1}, {"A.swift": 4}), [])


if __name__ == "__main__":
    unittest.main()
