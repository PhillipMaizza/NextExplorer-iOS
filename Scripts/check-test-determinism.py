#!/usr/bin/env python3
"""Fail when a package test uses something that makes it nondeterministic.

Tests must give the same result on every run, on any machine. Scans Packages/*/Tests for:

  Date()                       use MockDate.date, or Date(timeIntervalSince1970:)
  Date.now                     same
  UUID()                       use UUID(0), UUID(1), ... or the .incrementing dependency
  Task.sleep, Thread.sleep     inject a clock and use TestClock / ImmediateClock
  ContinuousClock(), SuspendingClock()   same
  DispatchQueue asyncAfter     same
  XCTWaiter                    await the result instead of waiting for time to pass
  URLSession.shared            inject a client
  Int.random, shuffled(), randomElement()   seed a generator (SplitMix64)
  exhaustivity = .off, skipReceivedActions   assert every state change and every effect

Existing uses are recorded in Scripts/test-determinism-baseline.json (file -> pattern -> count).
A count may go down but never up, and a file not in the baseline may use none. Fixing a use and
rerunning with --update lowers the baseline.

  python3 Scripts/check-test-determinism.py            check (CI)
  python3 Scripts/check-test-determinism.py --update   rewrite the baseline from the tests
"""
import argparse
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BASELINE = pathlib.Path(__file__).resolve().parent / "test-determinism-baseline.json"

PATTERNS = {
    "Date()": r"(?<![A-Za-z0-9_.])Date\(\)",
    "Date.now": r"\bDate\.now\b",
    "UUID()": r"(?<![A-Za-z0-9_.])UUID\(\)",
    "Task.sleep": r"\bTask\.sleep\b",
    "clock.sleep": r"(?<!Task)(?<!Thread)\.sleep\(",
    "Thread.sleep": r"\bThread\.sleep\b|\busleep\(",
    "ContinuousClock()": r"\bContinuousClock\(\)|\bSuspendingClock\(\)",
    "asyncAfter": r"\basyncAfter\b",
    "XCTWaiter": r"\bXCTWaiter\b|\bwaitForExpectations\b",
    "URLSession.shared": r"\bURLSession\.shared\b",
    "random": r"\b(Int|UInt|Double|Float|CGFloat|Bool)\.random\(|\.randomElement\(|\.shuffled\(\)|SystemRandomNumberGenerator",
    "exhaustivity off": r"exhaustivity\s*=\s*\.off",
    "skipReceivedActions": r"\bskipReceivedActions\b",
}


def count_in(text):
    counts = {}
    for line in text.splitlines():
        code = line.split("//", 1)[0]
        for name, pattern in PATTERNS.items():
            found = len(re.findall(pattern, code))
            if found:
                counts[name] = counts.get(name, 0) + found
    return counts


def scan(root):
    result = {}
    for path in sorted(root.glob("Packages/*/Tests/**/*.swift")):
        counts = count_in(path.read_text())
        if counts:
            result[str(path.relative_to(root))] = counts
    return result


def violations(current, baseline):
    """Lines describing every count above its baseline."""
    problems = []
    for path, counts in current.items():
        allowed = baseline.get(path, {})
        for name, count in counts.items():
            if count > allowed.get(name, 0):
                problems.append(f"{path}: {name} x{count} (allowed {allowed.get(name, 0)})")
    return problems


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--update", action="store_true")
    args = parser.parse_args()
    current = scan(ROOT)
    if args.update:
        BASELINE.write_text(json.dumps(current, indent=2, sort_keys=True) + "\n")
        total = sum(sum(c.values()) for c in current.values())
        print(f"Baseline rewritten: {total} uses in {len(current)} files")
        return 0
    baseline = json.loads(BASELINE.read_text()) if BASELINE.exists() else {}
    problems = violations(current, baseline)
    if problems:
        print("Nondeterministic test code (see the header of Scripts/check-test-determinism.py):")
        print("\n".join(problems))
        return 1
    total = sum(sum(c.values()) for c in current.values())
    print(f"Test determinism: {total} baseline uses in {len(current)} files, none new")
    return 0


if __name__ == "__main__":
    sys.exit(main())
