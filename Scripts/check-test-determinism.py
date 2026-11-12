#!/usr/bin/env python3
"""Fail when a package test uses something that makes it nondeterministic.

Tests must give the same result on every run, on any machine. Scans Packages/*/Tests for:

  Date()                       use MockDate.date, or Date(timeIntervalSince1970:)
  Date.now                     same
  Date(timeIntervalSince1970:) in a test   use MockDate.date plus an offset, one fixed date for every test
  UUID()                       use UUID(0), UUID(1), ... or the .incrementing dependency
  Task.sleep, Thread.sleep     inject a clock and use TestClock / ImmediateClock
  ContinuousClock(), SuspendingClock()   same
  DispatchQueue asyncAfter     same
  XCTWaiter                    await the result instead of waiting for time to pass
  URLSession.shared            inject a client
  Int.random, shuffled(), randomElement()   seed a generator (SplitMix64)
  exhaustivity = .off, skipReceivedActions, skipInFlightEffects   assert every state change and every effect
  inline JSON in a test        a real .json file under Tests/<Target>/Fixtures/, named by the target's FixtureFile enum
  withMainSerialExecutor       process wide switch, races parallel suites: gate effects with AsyncGate
  a test file over 600 lines          split it into cohesive files, one suite per behavior area
  TestStore in a file without .isolatedDependencies   add @Suite(.isolatedDependencies) (TestUtils): fresh dependencies and @Shared in memory storage for every test

UI tests (NextExplorerUITests) drive a real app, so they wait on a condition with a timeout
(waitForExistence, waitUntil); only a fixed sleep (Task.sleep, clock.sleep, Thread.sleep, usleep,
asyncAfter) is banned there. The git excluded QA harness folder is not scanned.

Every use fails the check: there is no baseline and no allow list. When a test truly needs a banned
pattern, it is the wrong test; fix it.

  python3 Scripts/check-test-determinism.py            check (CI)
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

PATTERNS = {
    "Date()": r"(?<![A-Za-z0-9_.])Date\(\)",
    "Date.now": r"\bDate\.now\b",
    "Date(timeIntervalSince1970:)": r"(?<![A-Za-z0-9_.])Date\(timeIntervalSince1970:",
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
    "skipInFlightEffects": r"\bskipInFlightEffects\b",
    "withMainSerialExecutor": r"\bwithMainSerialExecutor\b",
    "inline JSON": r"Data\(#*\"{3}|Data\(#*\"+[\{\[]|#\"[\{\[]|\"[\{\[]\\\"",
}

# What a UI test may not do: wait for a fixed time instead of a condition.
UI_PATTERNS = {name: PATTERNS[name] for name in ("Task.sleep", "clock.sleep", "Thread.sleep", "asyncAfter")}
UI_TESTS = "NextExplorerUITests"
UI_EXCLUDED = "QA"

# A file that builds a TestStore must opt its suites into isolated dependencies and @Shared storage.
ISOLATION = "TestStore without .isolatedDependencies"

# Big test files are slow to read, review and run in parallel: split them by behavior area.
MAX_LINES = 600
TOO_LONG = f"lines over {MAX_LINES}"


def count_patterns(text, patterns):
    counts = {}
    for line in text.splitlines():
        code = line.split("//", 1)[0]
        for name, pattern in patterns.items():
            found = len(re.findall(pattern, code))
            if found:
                counts[name] = counts.get(name, 0) + found
    return counts


def count_in(text):
    counts = count_patterns(text, PATTERNS)
    lines = text.count("\n") + 1
    if lines > MAX_LINES:
        counts[TOO_LONG] = lines - MAX_LINES
    if "TestStore(" in text and "@Test" in text and not re.search(r"@Suite\([^)]*\.isolatedDependencies", text):
        counts[ISOLATION] = 1
    return counts


def scan(root):
    result = {}
    for path in sorted(root.glob("Packages/*/Tests/**/*.swift")):
        counts = count_in(path.read_text())
        if counts:
            result[str(path.relative_to(root))] = counts
    for path in sorted((root / UI_TESTS).glob("**/*.swift")):
        relative = path.relative_to(root / UI_TESTS)
        if relative.parts[0] == UI_EXCLUDED:
            continue
        counts = count_patterns(path.read_text(), UI_PATTERNS)
        if counts:
            result[str(path.relative_to(root))] = counts
    return result


def violations(current):
    """One line per use: every use is a failure."""
    return [
        f"{path}: {name} x{count}"
        for path, counts in current.items()
        for name, count in counts.items()
    ]


def main():
    problems = violations(scan(ROOT))
    if problems:
        print("Nondeterministic test code (see the header of Scripts/check-test-determinism.py):")
        print("\n".join(problems))
        return 1
    print("Test determinism: no banned patterns in any test")
    return 0


if __name__ == "__main__":
    sys.exit(main())
