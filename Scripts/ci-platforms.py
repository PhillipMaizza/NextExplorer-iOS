#!/usr/bin/env python3
"""Which builds a change needs, so CI skips the macOS jobs it cannot affect.

Reads changed file paths from stdin (one per line) and prints GitHub Actions outputs:

    code=true|false
    ios=true|false
    mac=true|false

Docs, screenshots, store text and issue templates never build, on a pull request or on main. On a pull request:

* a script that only runs in the Changes job, where its self check runs (or one CI never runs),
  cannot change the app or its tests, so it builds nothing;
* a Swift file wholly wrapped in `#if os(macOS)` (or `#if os(iOS)`) cannot change the other
  platform's build, so a change made only of such files skips the other platform's jobs.

Anything else counts for both: shared Swift, project files, resources, fixtures, lint config,
workflows, scripts the build jobs run, and any file that is deleted or has an `#else` branch. The
lists below are allow lists: an unknown file builds. A push to main builds everything except docs.

    python3 Scripts/ci-platforms.py --ref <sha> --event pull_request|push
"""
import argparse
import re
import subprocess
import sys

MAC = "mac"
IOS = "ios"
SHARED = "shared"
DOCS = "docs"
CHECKED = "checked"

# Never part of a build.
DOCS_PATTERN = re.compile(r"\.md$|^LICENSE$|^Screenshots/|^fastlane/|^Gemfile|^\.ruby-version$|^\.github/ISSUE_TEMPLATE/")

# Scripts whose only CI run is their self check in the Changes job, or that CI never runs (release,
# translation and certificate tools). gen-l10n.py writes Swift, but a change to that output is a
# Swift change and builds on its own.
CHECKED_FILES = {
    "Scripts/check-test-determinism.py",
    "Scripts/test_check_test_determinism.py",
    "Scripts/ci-platforms.py",
    "Scripts/test_ci_platforms.py",
    "Scripts/test_ci_restore_mtimes.py",
    "Scripts/test_sync_package_pins.py",
    "Scripts/gen-changelog.py",
    "Scripts/test_gen_changelog.py",
    "Scripts/gen-l10n.py",
    "Scripts/test_gen_l10n.py",
    "Scripts/machine-translate.py",
}
CHECKED_FOLDERS = ("Scripts/mtls/",)

GUARDS = {"#if os(macOS)": MAC, "#if os(iOS)": IOS}


def kind(path, content):
    """DOCS, CHECKED, MAC, IOS or SHARED for one changed file, given its content (None when gone)."""
    if DOCS_PATTERN.search(path):
        return DOCS
    if path in CHECKED_FILES or path.startswith(CHECKED_FOLDERS):
        return CHECKED
    if path.endswith("-macOS.entitlements"):
        return MAC
    if not path.endswith(".swift") or content is None:
        return SHARED
    lines = [line for line in content.splitlines() if line.strip()]
    if not lines or lines[0] not in GUARDS:
        return SHARED
    # One guard around the whole file: a single column zero #if, its #endif last, no #else.
    top_level_ifs = [line for line in lines if re.match(r"#if\b", line)]
    top_level_endifs = [line for line in lines if re.match(r"#endif\b", line)]
    if len(top_level_ifs) != 1 or len(top_level_endifs) != 1 or lines[-1] != "#endif":
        return SHARED
    if any(re.match(r"#(else|elseif)\b", line) for line in lines):
        return SHARED
    return GUARDS[lines[0]]


def platforms(kinds):
    """(ios, mac) for the kinds of every changed code file."""
    if not kinds:
        return False, False
    return any(k != MAC for k in kinds), any(k != IOS for k in kinds)


def outputs(kinds, event):
    """(code, ios, mac) for every changed file's kind on a pull request or a push."""
    code = [k for k in kinds if k != DOCS]
    if not code:
        return False, False, False
    if event != "pull_request":
        return True, True, True
    ios, mac = platforms([k for k in code if k != CHECKED])
    return True, ios, mac


def content_at(ref, path):
    result = subprocess.run(["git", "show", f"{ref}:{path}"], capture_output=True, text=True)
    return result.stdout if result.returncode == 0 else None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ref", required=True)
    parser.add_argument("--event", required=True)
    args = parser.parse_args()
    paths = [line.strip() for line in sys.stdin if line.strip()]
    code, ios, mac = outputs([kind(path, content_at(args.ref, path)) for path in paths], args.event)
    print(f"code={str(code).lower()}")
    print(f"ios={str(ios).lower()}")
    print(f"mac={str(mac).lower()}")


if __name__ == "__main__":
    main()
