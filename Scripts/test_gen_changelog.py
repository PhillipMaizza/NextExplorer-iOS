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

    def test_bump_commits_are_skipped(self):
        self.assertIsNone(gen.entry("Bump version to 1.1.4", ""))


class GenericNoteTests(unittest.TestCase):
    def notes_for(self, subjects):
        log = "".join(f"{index:040d}\x1f2026-11-09\x1f{subject}\x1f\x1e" for index, subject in enumerate(subjects))
        originals = (gen.git, gen.release_tags, gen.app_version)
        gen.git = lambda *args: log
        gen.release_tags = lambda: {}
        gen.app_version = lambda commit, cache: "1.1.3"
        try:
            return gen.notes(gen.releases("HEAD"), "1.1.3")
        finally:
            gen.git, gen.release_tags, gen.app_version = originals

    def test_generic_note_is_left_out_when_there_are_real_notes(self):
        text = self.notes_for([
            "NXTIOS-0089: the release lane commits the next MARKETING_VERSION to main (#120)",
            "NXTIOS-0087: sign in with a username, not only an email (#118)",
        ])
        self.assertEqual(text, "- Sign in with a username, not only an email")

    def test_generic_note_is_the_only_note_for_a_tooling_only_version(self):
        text = self.notes_for(["NXTIOS-0089: the release lane commits the next MARKETING_VERSION to main (#120)"])
        self.assertEqual(text, "- Bug fixes and improvements")


class NotesLimitTests(unittest.TestCase):
    def test_long_notes_are_cut_at_a_line_boundary(self):
        entries = [(f"Note number {index} " + "x" * 50, []) for index in range(200)]
        text = gen.notes([("1.1.3", "d", entries)], "1.1.3")
        self.assertLessEqual(len(text), gen.NOTES_LIMIT)
        self.assertTrue(all(line.startswith("- Note number") and line.endswith("x" * 50) for line in text.split("\n")))


if __name__ == "__main__":
    unittest.main()
