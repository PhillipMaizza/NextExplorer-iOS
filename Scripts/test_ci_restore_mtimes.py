#!/usr/bin/env python3
"""Self check for ci-restore-mtimes.py: python3 Scripts/test_ci_restore_mtimes.py"""
import importlib.util
import os
import pathlib
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent / "ci-restore-mtimes.py"
spec = importlib.util.spec_from_file_location("ci_restore_mtimes", SCRIPT)
mtimes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mtimes)

BASE = 1_700_000_000


class RestoreTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.directory.name)
        self.git("init", "-q", "-b", "main")

    def tearDown(self):
        self.directory.cleanup()

    def git(self, *args, at=None, check=True):
        # The machine's git config never applies, so the run is the same on a laptop and on CI.
        env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1",
                   GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.com",
                   GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.com")
        if at is not None:
            env["GIT_AUTHOR_DATE"] = env["GIT_COMMITTER_DATE"] = f"@{at} +0000"
        return subprocess.run(["git", "-C", str(self.root), *args], check=check, capture_output=True, env=env)

    def commit(self, files, at):
        for name, text in files.items():
            (self.root / name).write_text(text)
        self.git("add", "-A")
        self.git("commit", "-q", "-m", f"at {at}", at=at)

    def mtime(self, name):
        return int((self.root / name).stat().st_mtime)

    def test_each_file_gets_the_time_of_its_last_commit(self):
        self.commit({"a.swift": "1", "b.swift": "1"}, BASE)
        self.commit({"a.swift": "2"}, BASE + 100)

        self.assertEqual(mtimes.restore(self.root), (2, 2))
        self.assertEqual(self.mtime("a.swift"), BASE + 100)
        self.assertEqual(self.mtime("b.swift"), BASE)

    def test_a_file_last_changed_by_a_merge_gets_the_merge_time(self):
        self.commit({"shared.swift": "base", "other.swift": "1"}, BASE)
        self.git("checkout", "-q", "-b", "side")
        self.commit({"shared.swift": "side"}, BASE + 100)
        self.git("checkout", "-q", "main")
        self.commit({"shared.swift": "main"}, BASE + 200)
        self.git("merge", "-q", "side", check=False)
        self.assertTrue((self.root / ".git" / "MERGE_HEAD").exists(), "the edits conflict and wait for a resolution")
        # The resolution exists only in the merge commit.
        (self.root / "shared.swift").write_text("resolved")
        self.git("add", "-A")
        self.git("commit", "-q", "--no-edit", at=BASE + 300)

        mtimes.restore(self.root)
        self.assertEqual(self.mtime("shared.swift"), BASE + 300)
        self.assertEqual(self.mtime("other.swift"), BASE)


if __name__ == "__main__":
    unittest.main()
