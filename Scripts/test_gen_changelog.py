#!/usr/bin/env python3
"""Self check for gen-changelog.py: python3 Scripts/test_gen_changelog.py"""
import importlib.util
import pathlib
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent / "gen-changelog.py"
spec = importlib.util.spec_from_file_location("gen_changelog", SCRIPT)
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)


def text_of(title):
    made = gen.entry(title, "")
    return None if made is None else made[0]


class VersionMentionTests(unittest.TestCase):
    def test_app_versions_are_dropped(self):
        self.assertEqual(text_of("NXTIOS-0079: sign in with mTLS, version 1.1.2 (#109)"), "Sign in with mTLS")
        self.assertEqual(text_of("NXTIOS-0066: iPhone Duo support, v1.0.5 (#93)"), "iPhone Duo support")
        self.assertEqual(text_of("NXTIOS-0048: dark mode, 1.0.1 (#74)"), "Dark mode")

    def test_a_version_number_inside_the_text_is_kept(self):
        self.assertEqual(text_of("NXTIOS-0090: Support iOS 18.2 photo formats (#1)"), "Support iOS 18.2 photo formats")


class UserFacingTests(unittest.TestCase):
    def test_plain_user_facing_title_is_kept(self):
        self.assertEqual(text_of("NXTIOS-0087: sign in with a username, not only an email (#118)"),
                         "Sign in with a username, not only an email")

    def test_no_longer_describes_a_change_users_notice(self):
        self.assertEqual(text_of("NXTIOS-0088: Back no longer waits on the breadcrumb bar animation (#119)"),
                         "Back no longer waits on the breadcrumb bar animation")

    def test_technical_titles_fold_into_the_generic_note(self):
        made = gen.entry("NXTIOS-0089: the release lane commits the next MARKETING_VERSION to main (#120)", "")
        self.assertEqual(made, ("", "120", True))

    def test_testflight_is_not_user_facing(self):
        made = gen.entry("NXTIOS-0084: TestFlight builds go to the external testers only (#114)", "")
        self.assertEqual(made, ("", "114", True))

    def test_house_rules_work_is_not_user_facing(self):
        made = gen.entry("NXTIOS-0180: House rules across the codebase (#207)", "")
        self.assertEqual(made, ("", "207", True))

    def test_internal_cleanup_is_not_user_facing(self):
        for title, pr in [
            ("NXTIOS-0185: Caches share one hash helper and the server timestamp formats (#212)", "212"),
            ("NXTIOS-0184: Code nothing calls is deleted (#211)", "211"),
            ("NXTIOS-0188: Dead properties go and repeated kind and version reads share one copy (#215)", "215"),
            ("NXTIOS-0189: One call clears every rebuildable cache (#216)", "216"),
        ]:
            self.assertEqual(gen.entry(title, ""), ("", pr, True), title)

    def test_a_search_fix_users_notice_is_kept(self):
        self.assertEqual(text_of("NXTIOS-0190: Browse search never shows an older term's results for the typed one (#217)"),
                         "Browse search never shows an older term's results for the typed one")

    def test_bump_commits_are_skipped(self):
        self.assertIsNone(gen.entry("Bump version to 1.1.4", ""))

    def test_format_bot_commits_are_skipped(self):
        self.assertIsNone(gen.entry("Format Swift code (#160)", ""))

    def test_a_title_opening_with_technical_work_folds_whole(self):
        made = gen.entry("NXTIOS-0167: UI tests find the toast, share sheet and offline bar by identifier (#194)", "")
        self.assertEqual(made, ("", "194", True))

    def test_ci_shards_do_not_leak_from_a_merge_title(self):
        made = gen.entry(
            "Merge pull request #177 from PhillipMaizza/feature/NXTIOS-0148-fix-mac-ui-and-ci",
            "NXTIOS-0148: Mac UI tests pass again, UI tests run on PRs that change them, two iPhone shards",
        )
        self.assertEqual(made, ("", "177", True))

    def test_a_merge_from_a_technical_branch_folds_whole(self):
        made = gen.entry(
            "Merge pull request #178 from PhillipMaizza/feature/NXTIOS-0149-explicit-state-machines",
            "NXTIOS-0149: Confirmations, change password and share link creation each move through one explicit phase",
        )
        self.assertEqual(made, ("", "178", True))

    def test_a_warning_users_see_is_kept(self):
        self.assertEqual(text_of("NXTIOS-0300: a warning before deleting a shared file (#300)"),
                         "A warning before deleting a shared file")

    def test_feature_titles_with_tooling_words_are_kept(self):
        for title in [
            "Google Docs files open in Preview",
            "A PIN lock for the app",
            "Upload phases show progress",
            "Wipe all offline files from Settings",
        ]:
            self.assertEqual(text_of(f"NXTIOS-0301: {title} (#301)"), title)

    def test_a_cache_wipe_fix_folds(self):
        made = gen.entry("NXTIOS-0173: No cache writes after a wipe, thumbnail and selection fixes (#200)", "")
        self.assertEqual(made, ("", "200", True))

    def test_compiler_warnings_fold(self):
        made = gen.entry("NXTIOS-0107: Swift concurrency warnings cleared (#139)", "")
        self.assertEqual(made, ("", "139", True))

    def test_multi_clause_feature_titles_are_kept_whole(self):
        for title in [
            "Document thumbnails, one type icon, folder filter chips",
            "Grid redesign with folder cards, page icons and a Grid sheet",
            "Trash on iPhone, iPad and Mac, restore with progress and Undo",
        ]:
            self.assertEqual(text_of(f"NXTIOS-0199: {title} (#199)"), title)


class GenericNoteTests(unittest.TestCase):
    def notes_for(self, subjects, app_lines=None):
        log = "".join(f"{index:040d}\x1f2026-11-09\x1f{subject}\x1f\x1e" for index, subject in enumerate(subjects))
        originals = (gen.git, gen.release_tags, gen.app_version, gen.app_lines)
        gen.git = lambda *args: log
        gen.release_tags = lambda: {}
        gen.app_version = lambda commit, cache: "1.1.3"
        gen.app_lines = lambda ref: {f"{index:040d}": lines for index, lines in enumerate(app_lines or [])}
        try:
            return gen.notes(gen.releases("HEAD"), "1.1.3")
        finally:
            gen.git, gen.release_tags, gen.app_version, gen.app_lines = originals

    def test_generic_note_is_left_out_when_there_are_real_notes(self):
        text = self.notes_for([
            "NXTIOS-0089: the release lane commits the next MARKETING_VERSION to main (#120)",
            "NXTIOS-0087: sign in with a username, not only an email (#118)",
        ])
        self.assertEqual(text, "- Sign in with a username, not only an email")

    def test_a_pr_that_changes_no_app_source_folds_whole(self):
        text = self.notes_for(
            [
                "NXTIOS-0166: Package folders group files by feature (#193)",
                "NXTIOS-0087: sign in with a username, not only an email (#118)",
            ],
            app_lines=[0, 40],
        )
        self.assertEqual(text, "- Sign in with a username, not only an email")

    def test_generic_note_is_the_only_note_for_a_tooling_only_version(self):
        text = self.notes_for(["NXTIOS-0089: the release lane commits the next MARKETING_VERSION to main (#120)"])
        self.assertEqual(text, "- Bug fixes and improvements")


class AppLinesTests(unittest.TestCase):
    def test_moves_tests_and_binaries_are_counted_apart(self):
        log = "\n".join([
            "@aaa",
            "0\t0\tPackages/Core/Sources/{ => Listing}/Favorite.swift",
            "12\t3\tPackages/Core/Tests/CoreTests/FavoriteTests.swift",
            "4\t1\t.github/workflows/ci.yml",
            "@bbb",
            "-\t-\tNextExplorer/Assets.xcassets/AppIcon.png",
            "2\t1\tPackages/Core/Sources/Core/Favorite.swift",
            "@ccc",
        ])
        original = gen.git
        gen.git = lambda *args: log
        try:
            self.assertEqual(gen.app_lines("HEAD"), {"aaa": 0, "bbb": 4, "ccc": 0})
        finally:
            gen.git = original


class OnlyTests(unittest.TestCase):
    def test_notes_for_the_newest_version_stop_at_its_tag(self):
        log = "".join(
            f"{commit}\x1f2026-11-09\x1fNXTIOS-0001: {title} (#{index})\x1f\x1e"
            for index, (commit, title) in enumerate([("c" * 40, "dark mode"), ("b" * 40, "trash"), ("a" * 40, "old")])
        )
        originals = (gen.git, gen.release_tags, gen.app_version, gen.app_lines)
        gen.git = lambda *args: log
        gen.release_tags = lambda: {"b" * 40: "1.0.0", "a" * 40: "0.9.0"}
        gen.app_lines = lambda ref: {}

        def untagged_history(commit, cache):
            raise AssertionError("walked past the tag")

        gen.app_version = untagged_history
        try:
            history = gen.releases("HEAD", upcoming="1.1.0", only="1.1.0")
        finally:
            gen.git, gen.release_tags, gen.app_version, gen.app_lines = originals
        self.assertEqual(history, [("1.1.0", "2026-11-09", [("Dark mode", ["0"])])])


class NotesLimitTests(unittest.TestCase):
    def test_long_notes_are_cut_at_a_line_boundary(self):
        entries = [(f"Note number {index} " + "x" * 50, []) for index in range(200)]
        text = gen.notes([("1.1.3", "d", entries)], "1.1.3")
        self.assertLessEqual(len(text), gen.NOTES_LIMIT)
        self.assertTrue(all(line.startswith("- Note number") and line.endswith("x" * 50) for line in text.split("\n")))


if __name__ == "__main__":
    unittest.main()
