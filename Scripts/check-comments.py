#!/usr/bin/env python3
"""Hold the number of Swift comment lines to a ratchet that only goes down.

Code says what it does; a decision that needs words goes in docs/adr, and a known limit goes in a
GitHub issue. Comments already in the tree are counted per file in Scripts/comment-baseline.json; a
file may lose comment lines but never gain them, and a file missing from the baseline may have none.
MARK, swiftlint and swiftformat directives are not counted, nor the generated L10n.swift.

  python3 Scripts/check-comments.py                    fail when a file has more than its baseline
  python3 Scripts/check-comments.py --update-baseline  write the current counts (refused if any rose)
  python3 Scripts/check-comments.py --list             one TSV row per comment block, for a sweep
  python3 Scripts/check-comments.py --delete LEDGER    delete the blocks a ledger names (path<TAB>line)

The scanner tracks string literals, so `//` inside "..." or a multi line string is code, not a comment.
"""
import argparse
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BASELINE = ROOT / "Scripts" / "comment-baseline.json"
DIRECTIVE = re.compile(r"^\s*//\s*(MARK:|swiftlint:|swiftformat:)")
GENERATED = {"Packages/Localization/Sources/Localization/L10n.swift"}


def scan(source):
    """Line number (1 based) to the column its comment starts at, for every line holding comment text.
    Column None marks a line that is comment from start to end."""
    lines = source.split("\n")
    commented = {}
    index, line, line_start, length = 0, 1, 0, len(source)

    def mark(at):
        column = at - line_start
        if line not in commented:
            commented[line] = None if lines[line - 1][:column].strip() == "" else column
    # Each frame is code (paren depth inside an interpolation) or a string (hashes, is triple quoted).
    stack = [("code", 0)]
    block_depth = 0
    while index < length:
        char = source[index]
        if char == "\n":
            line += 1
            index += 1
            line_start = index
            continue
        if block_depth:
            mark(index)
            if source.startswith("/*", index):
                block_depth, index = block_depth + 1, index + 2
            elif source.startswith("*/", index):
                block_depth, index = block_depth - 1, index + 2
            else:
                index += 1
            continue
        kind, value = stack[-1]
        if kind == "string":
            hashes, triple = value
            escape = "\\" + "#" * hashes
            if source.startswith(escape + "(", index):
                stack.append(("code", 0))
                index += len(escape) + 1
            elif source.startswith(escape, index):
                index += len(escape) + 1
            elif source.startswith(('"""' if triple else '"') + "#" * hashes, index):
                stack.pop()
                index += (3 if triple else 1) + hashes
            else:
                index += 1
            continue
        if source.startswith("//", index):
            if not DIRECTIVE.match(lines[line - 1]):
                mark(index)
            end = source.find("\n", index)
            index = length if end < 0 else end
            continue
        if source.startswith("/*", index):
            mark(index)
            block_depth, index = 1, index + 2
            continue
        opener = re.match(r'(#*)("""|")', source[index:index + 8])
        if opener:
            stack.append(("string", (len(opener.group(1)), opener.group(2) == '"""')))
            index += len(opener.group(0))
            continue
        if char == "(":
            stack[-1] = ("code", value + 1)
        elif char == ")" and len(stack) > 1:
            if value == 0:
                stack.pop()
            else:
                stack[-1] = ("code", value - 1)
        index += 1
    return commented


def swift_files():
    listing = subprocess.run(["git", "ls-files", "*.swift"], cwd=ROOT, capture_output=True, text=True, check=True)
    return [path for path in listing.stdout.splitlines() if path and path not in GENERATED]


def counts():
    result = {}
    for path in swift_files():
        number = len(scan((ROOT / path).read_text(encoding="utf-8")))
        if number:
            result[path] = number
    return result


def grown(current, baseline):
    return sorted(
        f"{path}: {number} comment lines (baseline {baseline.get(path, 0)}); explain it in code, docs/adr or an issue"
        for path, number in current.items()
        if number > baseline.get(path, 0)
    )


def blocks(source):
    """Runs of whole comment lines, plus each trailing comment on its own, as (first line, last line)."""
    found = scan(source)
    runs = []
    for number in sorted(found):
        if found[number] is None and runs and runs[-1][1] == number - 1 and found[runs[-1][1]] is None:
            runs[-1][1] = number
        else:
            runs.append([number, number])
    return [tuple(run) for run in runs]


def delete(source, starts):
    """Source with every block starting at one of `starts` removed: whole comment lines go, a trailing
    comment is cut off its code line."""
    found = scan(source)
    lines = source.split("\n")
    drop = set()
    for first, last in blocks(source):
        if first not in starts:
            continue
        for number in range(first, last + 1):
            if found[number] is None:
                drop.add(number)
            else:
                lines[number - 1] = lines[number - 1][: found[number]].rstrip()
    return "\n".join(text for number, text in enumerate(lines, start=1) if number not in drop)


def main():
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--update-baseline", action="store_true")
    group.add_argument("--list", action="store_true")
    group.add_argument("--delete", metavar="LEDGER")
    args = parser.parse_args()

    if args.list:
        for path in swift_files():
            source = (ROOT / path).read_text(encoding="utf-8")
            lines = source.split("\n")
            for first, last in blocks(source):
                text = " ".join(lines[n - 1].strip() for n in range(first, last + 1)).replace("\t", " ")
                after = lines[last].strip() if last < len(lines) else ""
                print(f"{path}\t{first}\t{last - first + 1}\t{text}\t{after}")
        return 0
    if args.delete:
        targets = {}
        for row in pathlib.Path(args.delete).read_text().splitlines():
            if row.strip():
                path, line = row.split("\t")[:2]
                targets.setdefault(path, set()).add(int(line))
        for path, starts in targets.items():
            file = ROOT / path
            file.write_text(delete(file.read_text(encoding="utf-8"), starts), encoding="utf-8")
        print(f"Deleted {sum(map(len, targets.values()))} comment blocks in {len(targets)} files")
        return 0

    current = counts()
    baseline = json.loads(BASELINE.read_text()) if BASELINE.exists() else {}
    findings = grown(current, baseline)
    if args.update_baseline:
        if findings and BASELINE.exists():
            print("\n".join(findings))
            print("Comments: baseline not raised; remove the new comments first")
            return 1
        BASELINE.write_text(json.dumps(dict(sorted(current.items())), indent=1) + "\n")
        print(f"Comments: baseline written, {sum(current.values())} lines in {len(current)} files")
        return 0
    for finding in findings:
        print(finding)
    if findings:
        print(f"Comments: {len(findings)} file(s) over the ratchet")
        return 1
    print(f"Comments: within the ratchet ({sum(current.values())} lines left)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
