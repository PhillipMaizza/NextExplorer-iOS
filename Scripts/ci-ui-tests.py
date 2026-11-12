#!/usr/bin/env python3
"""Run UI tests once, rerun only the failures once, and name every test that needed the rerun.

xcodebuild's own retry (-retry-tests-on-failure with relaunch) reran the whole suite after one
failure, which doubled a 12 minute Mac run, and a test that failed and then passed left no trace.
Here a test that passes only on its rerun keeps the job green but is reported as flaky (a warning
annotation and a line in the job summary), so it gets fixed instead of hidden. A run that fails
without a test failure (a build error, a crash before the results) is never rerun.

  python3 Scripts/ci-ui-tests.py --result TestResults --select "<-only-testing/-skip-testing args>" \\
      -- <xcodebuild arguments without a selection or -resultBundlePath>
"""
import argparse
import json
import os
import shlex
import subprocess
import sys


def failed_tests(summary):
    """`Target/Class/method` for every failed test in an xcresulttool summary, in order, once."""
    tests = []
    for failure in summary.get("testFailures", []):
        name = failure.get("testIdentifierString", "").removesuffix("()")
        target = failure.get("targetName", "")
        if name and target and f"{target}/{name}" not in tests:
            tests.append(f"{target}/{name}")
    return tests


def report(flaky, still_failing):
    """GitHub annotations and job summary lines for the rerun's outcome."""
    lines = [f"::warning title=Flaky UI test::{test} failed, then passed on its rerun. Fix it." for test in flaky]
    lines += [f"::error title=UI test failed twice::{test}" for test in still_failing]
    summary = []
    if flaky:
        summary += ["### Flaky UI tests (passed only on the rerun)", ""] + [f"- `{test}`" for test in flaky] + [""]
    if still_failing:
        summary += ["### UI tests that failed twice", ""] + [f"- `{test}`" for test in still_failing] + [""]
    return lines, summary


def xcodebuild(arguments, selection, result):
    """Exit code of one xcodebuild run, its output through xcbeautify for GitHub annotations."""
    command = ["xcodebuild", *arguments, *selection, "-resultBundlePath", f"{result}.xcresult"]
    pipeline = f"set -o pipefail; {shlex.join(command)} | xcbeautify --renderer github-actions"
    return subprocess.run(["bash", "-c", pipeline]).returncode


def summary_of(result):
    output = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", f"{result}.xcresult", "--compact"],
        capture_output=True,
        text=True,
    )
    return json.loads(output.stdout) if output.returncode == 0 and output.stdout else {}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--result", required=True, help="result bundle name, without .xcresult")
    parser.add_argument("--select", default="", help="the -only-testing / -skip-testing arguments")
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    arguments = args.arguments[1:] if args.arguments[:1] == ["--"] else args.arguments

    if xcodebuild(arguments, shlex.split(args.select), args.result) == 0:
        return 0
    failed = failed_tests(summary_of(args.result))
    if not failed:
        print("::error::The run failed without a test failure (build error or crash); not rerunning")
        return 1

    print(f"Rerunning {len(failed)} failed test(s) once: {', '.join(failed)}")
    retry = f"{args.result}-rerun"
    passed_on_rerun = xcodebuild(arguments, [f"-only-testing:{test}" for test in failed], retry) == 0
    still_failing = [] if passed_on_rerun else failed_tests(summary_of(retry)) or failed
    flaky = [test for test in failed if test not in still_failing]

    lines, summary = report(flaky, still_failing)
    print("\n".join(lines))
    if summary and os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as handle:
            handle.write("\n".join(summary) + "\n")
    return 0 if not still_failing else 1


if __name__ == "__main__":
    sys.exit(main())
