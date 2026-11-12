#!/usr/bin/env python3
"""Which platforms a change can affect, so CI skips the build of the other one.

Reads changed file paths from stdin (one per line) and prints GitHub Actions outputs:

    ios=true|false
    mac=true|false

A Swift file wholly wrapped in `#if os(macOS)` (or `#if os(iOS)`) cannot change the other
platform's build, so a change made only of such files skips the other platform's jobs. Anything
else counts for both: shared Swift, project files, resources, workflows, and any file that is
deleted or that has an `#else` branch. Paths come from the caller already stripped of docs.

    python3 Scripts/ci-platforms.py --ref <sha>     reads each file at that commit
"""
import argparse
import re
import subprocess
import sys

MAC = "mac"
IOS = "ios"
SHARED = "shared"

GUARDS = {"#if os(macOS)": MAC, "#if os(iOS)": IOS}


def kind(path, content):
    """MAC, IOS or SHARED for one changed file, given its content (None when it is gone)."""
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


def content_at(ref, path):
    result = subprocess.run(["git", "show", f"{ref}:{path}"], capture_output=True, text=True)
    return result.stdout if result.returncode == 0 else None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ref", required=True)
    args = parser.parse_args()
    paths = [line.strip() for line in sys.stdin if line.strip()]
    ios, mac = platforms([kind(path, content_at(args.ref, path)) for path in paths])
    print(f"ios={str(ios).lower()}")
    print(f"mac={str(mac).lower()}")


if __name__ == "__main__":
    main()
