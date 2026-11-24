#!/usr/bin/env python3
"""Self check for check-house-rules.py: python3 Scripts/test_check_house_rules.py"""
import importlib.util
import pathlib
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent / "check-house-rules.py"
spec = importlib.util.spec_from_file_location("check_house_rules", SCRIPT)
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)

SOURCE = "Packages/FilesFeature/Sources/FilesFeature/Trash/TrashView.swift"
TEST = "Packages/FilesFeature/Tests/FilesFeatureTests/TrashTests.swift"
DIFF = """diff --git a/{path} b/{path}
--- a/{path}
+++ b/{path}
@@ -3,0 +4,2 @@ struct A {{
+let a = 1
+let b = 2
@@ -9 +11 @@
-old
+let c = 3
"""


def lines_of(path, *texts, content=None, denylist=()):
    return check.check_lines(path, list(enumerate(texts, start=1)), content, list(denylist))


class DiffTests(unittest.TestCase):
    def test_added_lines_carry_their_new_line_numbers(self):
        added = check.parse_diff(DIFF.format(path=SOURCE))
        self.assertEqual(added, {SOURCE: [(4, "let a = 1"), (5, "let b = 2"), (11, "let c = 3")]})

    def test_a_deleted_file_has_no_added_lines(self):
        self.assertEqual(check.parse_diff("--- a/x.swift\n+++ /dev/null\n@@ -1 +0,0 @@\n-gone\n"), {})


class CommentTests(unittest.TestCase):
    def test_a_dash_as_punctuation_in_a_comment_is_found(self):
        lines = ["let a = 1 // a case - the common one", "/// Checks first \u2014 then saves", "// one--two", " * re-read \u2013 twice"]
        self.assertEqual(len(lines_of(SOURCE, *lines)), 4)

    def test_hyphenated_words_marks_and_docc_items_pass(self):
        lines = ["// a well-known case", "/// Pre-check", "// MARK: - Section", "/// - Parameters:", "///   - name: the file", "// rwx r-x r--"]
        self.assertEqual(lines_of(SOURCE, *lines), [])

    def test_links_and_code_hyphens_pass(self):
        self.assertEqual(lines_of(SOURCE, "// see https://example.com/a-b", "let a = b - c"), [])

    def test_other_files_are_not_swift_comments(self):
        self.assertEqual(lines_of("README.md", "// a-b"), [])


class SourceRuleTests(unittest.TestCase):
    def test_a_raw_string_in_a_view_is_found(self):
        self.assertEqual(len(lines_of(SOURCE, 'Text("Hi")', 'Button("Go") {}', '.navigationTitle("Trash")')), 3)

    def test_a_literal_equal_to_a_ds_token_is_found(self):
        found = lines_of(SOURCE, "static let gap: CGFloat = 16", ".padding(48)", ".frame(width: 1, height: 24)", ".padding(.top, 8)")
        self.assertEqual(len(found), 4)

    def test_tokens_and_other_literals_pass(self):
        self.assertEqual(
            lines_of(SOURCE, "static let gap: CGFloat = .space16", "static let width: CGFloat = 340", "static let columns = 2", ".frame(width: 1)"),
            [],
        )

    def test_the_token_definitions_hold_their_literals(self):
        spacing = "Packages/DesignSystem/Sources/DesignSystem/Essentials/Spacing.swift"
        self.assertEqual(lines_of(spacing, "    static let space40: CGFloat = 40"), [])

    def test_a_symbol_name_outside_iconkit_is_found(self):
        self.assertEqual(len(lines_of(SOURCE, 'Image(systemName: "trash")', 'Label(L10n.Trash.title, systemImage: "trash")')), 2)
        self.assertEqual(lines_of("Packages/DesignSystem/Sources/DesignSystem/Essentials/IconKit.swift", 'Image(systemName: "trash")'), [])

    def test_an_indented_preview_counts_as_a_preview(self):
        content = "#if os(macOS)\n    struct A {}\n    #Preview {\n        Text(\"Hi\")\n    }\n#endif\n"
        self.assertEqual(check.check_lines(SOURCE, [(4, '        Text("Hi")')], content, []), [])

    def test_localized_and_symbol_strings_pass(self):
        self.assertEqual(lines_of(SOURCE, "Text(L10n.Trash.title)", 'Text(verbatim: "%")', "Image(IconKit.trash)"), [])

    def test_a_raw_string_in_a_preview_or_test_passes(self):
        content = "struct A {}\n#Preview {\n    Text(\"Hi\")\n}\n"
        self.assertEqual(check.check_lines(SOURCE, [(3, 'Text("Hi")')], content, []), [])
        self.assertEqual(lines_of(TEST, 'Text("Hi")'), [])
        self.assertEqual(lines_of("Packages/A/Sources/A/BrowsePreviews.swift", 'Text("Hi")'), [])

    def test_a_stored_loading_flag_is_found_but_a_computed_one_is_not(self):
        found = lines_of(SOURCE, "var isLoading = false", "public var hasLoaded: Bool", "var isLoading: Bool { phase.isLoading }")
        self.assertEqual(len(found), 2)

    def test_a_suffixed_loading_flag_is_found(self):
        found = lines_of(SOURCE, "var isLoadingMore = false", "var isLoadingMore: Bool { morePhase == .loading }")
        self.assertEqual(len(found), 1)

    def test_a_bool_not_named_as_a_question_is_found(self):
        found = lines_of(SOURCE, "let enabled: Bool", "public var showThumbnails: Bool?", "@State private var dirty: Bool = false")
        self.assertEqual(len(found), 3)

    def test_a_bool_named_as_a_question_passes(self):
        lines = ["let isEnabled: Bool", "var hasItems: Bool", "let shouldShowThumbnails: Bool?", "let supportsThumbnail: Bool"]
        self.assertEqual(lines_of(SOURCE, *lines), [])

    def test_a_negated_platform_check_is_found(self):
        self.assertEqual(len(lines_of(SOURCE, "#if !os(macOS)", "#if os(iOS)")), 1)

    def test_byte_streaming_is_found(self):
        self.assertEqual(len(lines_of(SOURCE, "let (bytes, _) = try await session.bytes(for: request)")), 1)


class SecretTests(unittest.TestCase):
    def test_key_material_is_found_anywhere(self):
        found = lines_of("fastlane/Fastfile", "-----BEGIN " + "PRIVATE KEY-----", "Auth" + "Key_ABCDE12345.p8", "token ghp_" + "a" * 36)
        self.assertEqual(len(found), 3)

    def test_an_issuer_id_is_found(self):
        self.assertEqual(len(lines_of("x.rb", "issuer" + '_id: "12345678-1234-1234-1234-123456789012"')), 1)

    def test_a_signing_file_is_found_unless_it_is_a_test_fixture(self):
        self.assertEqual(len(check.check_new_file("fastlane/key.p8", "")), 1)
        self.assertEqual(check.check_new_file("Packages/N/Tests/NTests/Fixtures/client.p12", ""), [])


class DenylistTests(unittest.TestCase):
    def test_a_denylisted_term_is_found_in_any_case(self):
        self.assertEqual(len(lines_of("a.swift", "// Made By Acme", denylist=["ACME"])), 1)

    def test_no_denylist_finds_nothing(self):
        self.assertEqual(lines_of("a.swift", "let acme = 1"), [])

    def test_an_exempt_prefix_is_skipped(self):
        self.assertEqual(lines_of("RULES.md", "acme", denylist=["acme", "!RULES.md"]), [])
        self.assertEqual(lines_of(".notes/a.md", "acme", denylist=["acme", "!.notes/"]), [])
        self.assertEqual(len(lines_of("README.md", "acme", denylist=["acme", "!RULES.md"])), 1)

    def test_an_exempt_prefix_is_not_a_commit_message_term(self):
        self.assertEqual(check.check_commit_message("NXTIOS-0150: A\n\nsee RULES.md\n", ["!rules.md"]), [])


class SizeTests(unittest.TestCase):
    VIEW = "struct TrashView: View {\n" + "\n" * 420

    def test_a_view_file_crossing_the_limit_fails(self):
        self.assertEqual(len(check.check_size(SOURCE, "struct TrashView: View {}\n", self.VIEW)), 1)

    def test_an_oversized_view_file_that_does_not_grow_passes(self):
        self.assertEqual(check.check_size(SOURCE, self.VIEW, self.VIEW), [])
        self.assertEqual(check.check_size(SOURCE, self.VIEW, self.VIEW[:-5]), [])

    def test_an_oversized_view_file_that_grows_fails(self):
        self.assertEqual(len(check.check_size(SOURCE, self.VIEW, self.VIEW + "\n")), 1)

    def test_a_test_file_crossing_its_limit_fails(self):
        test = "Packages/A/Tests/ATests/TrashTests.swift"
        self.assertEqual(len(check.check_size(test, "", "struct TrashTests {\n" + "\n" * 620)), 1)
        self.assertEqual(check.check_size(test, "", "struct TrashTests {\n" + "\n" * 500), [])

    def test_a_large_non_view_file_passes(self):
        self.assertEqual(check.check_size(SOURCE, None, "struct Reducer {\n" + "\n" * 500), [])


class PreviewTests(unittest.TestCase):
    def test_a_new_view_without_a_preview_fails(self):
        self.assertEqual(len(check.check_new_file(SOURCE, "struct TrashRow: View {}\n")), 1)

    def test_a_new_view_with_a_preview_passes(self):
        self.assertEqual(check.check_new_file(SOURCE, "struct TrashRow: View {}\n#Preview { TrashRow() }\n"), [])

    def test_conformance_lists_count(self):
        self.assertEqual(len(check.check_new_file(SOURCE, "struct A: Equatable, View {}\n")), 1)


class CommitMessageTests(unittest.TestCase):
    def test_a_good_message_passes(self):
        self.assertEqual(check.check_commit_message("NXTIOS-0150: Trash lists items\n\nWhy it matters.\n", []), [])

    def test_a_bad_subject_and_missing_body_fail(self):
        self.assertEqual(len(check.check_commit_message("fix stuff\n", [])), 2)

    def test_git_comment_lines_are_ignored(self):
        self.assertEqual(check.check_commit_message("NXTIOS-0150: A\n\nB\n# Please enter\n", []), [])

    def test_co_author_and_generator_lines_fail(self):
        for line in ("Co-Authored-By: Someone <a@b.c>", "Generated with a tool"):
            self.assertEqual(len(check.check_commit_message(f"NXTIOS-0150: A\n\nB\n\n{line}\n", [])), 1, line)

    def test_a_denylisted_term_fails(self):
        self.assertEqual(len(check.check_commit_message("NXTIOS-0150: A\n\nlike Acme does\n", ["acme"])), 1)


class BranchTests(unittest.TestCase):
    def test_branch_names(self):
        for name in ("feature/NXTIOS-0150-trash", "main", "release/1.2.1", ""):
            self.assertEqual(check.check_branch(name), [], name)
        for name in ("feature/trash", "fix/NXTIOS-0150-trash", "feature/NXTIOS-0150-Trash"):
            self.assertEqual(len(check.check_branch(name)), 1, name)


class MovedFileTests(unittest.TestCase):
    def test_a_moved_file_is_its_old_self_not_a_new_file(self):
        import os
        import subprocess
        import tempfile

        view = "import SwiftUI\n\nstruct Row: View {\n    var body: some View {\n        // A hyphen-ated comment\n        Text(\"x\")\n    }\n}\n"
        with tempfile.TemporaryDirectory() as temp:
            def git(*args):
                return subprocess.run(["git", *args], cwd=temp, capture_output=True, text=True, check=True).stdout

            git("init", "-q")
            git("config", "user.email", "t@example.com")
            git("config", "user.name", "t")
            pathlib.Path(temp, "Row.swift").write_text(view)
            git("add", "-A")
            git("commit", "-qm", "base")
            os.makedirs(os.path.join(temp, "Views"))
            git("mv", "Row.swift", "Views/Row.swift")
            git("add", "-A")
            real_root = check.ROOT
            check.ROOT = pathlib.Path(temp)
            try:
                statuses = check.changed_files(["--cached"])
            finally:
                check.ROOT = real_root
        self.assertEqual(statuses, {"Views/Row.swift": ("M", "Row.swift")})


if __name__ == "__main__":
    unittest.main()
