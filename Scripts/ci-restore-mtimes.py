#!/usr/bin/env python3
"""Set every tracked file's modification time to the time of the last commit that touched it.

A fresh checkout stamps every file with the clone time, and Xcode decides what to recompile from
modification times (not inodes or contents), so a cached DerivedData recompiled every local
package on every CI run. With the commit times, a file unchanged since the cached build keeps the
time that build recorded, and only what really changed recompiles. CI runs it right after the
checkout, on main where the cache is saved as well as on pull requests where it is restored.

A merge commit counts as touching every file it changes against its first parent. Without that,
git log lists no files for a merge, so a file last changed by a merge (a conflict resolution, or
the pull request merge CI checks out) kept an older commit's time, matched the cached build, and
Xcode linked the stale object. Paths are read unquoted, so a file name with accents or emoji is
stamped like any other instead of failing.

  python3 Scripts/ci-restore-mtimes.py
"""
import os, pathlib, subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent


def restore(root):
    """Stamps each tracked file under `root` and returns how many were stamped and tracked."""
    log = subprocess.run(
        ["git", "-C", str(root), "-c", "core.quotePath=false", "log", "--format=%x00%ct", "--name-only", "--no-renames", "--diff-merges=first-parent"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    tracked = set(
        subprocess.run(["git", "-C", str(root), "-c", "core.quotePath=false", "ls-files"], check=True, capture_output=True, text=True).stdout.splitlines()
    )
    stamped = set()
    # Newest commit first, so the first time a path shows up is its last change.
    for entry in log.split("\0"):
        lines = [line for line in entry.splitlines() if line]
        if not lines:
            continue
        time = int(lines[0])
        for path in lines[1:]:
            if path in tracked and path not in stamped:
                stamped.add(path)
                os.utime(root / path, (time, time), follow_symlinks=False)
    return len(stamped), len(tracked)


def main():
    stamped, tracked = restore(ROOT)
    print(f"Set {stamped} of {tracked} tracked files to their last commit time")


if __name__ == "__main__":
    main()
