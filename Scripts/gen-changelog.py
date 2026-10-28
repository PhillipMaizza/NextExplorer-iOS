#!/usr/bin/env python3
"""Generate CHANGELOG.md from the git history of main.

Every PR lands on main as one commit (`NXTIOS-XXXX: summary (#N)`, or a merge commit for the
early ones) and every release PR bumps MARKETING_VERSION, so the history already says what
shipped in which version. This walks main's first parent history, reads the app's
MARKETING_VERSION at each commit, and groups the PRs by it, newest version first.

  python3 Scripts/gen-changelog.py               rewrite CHANGELOG.md
  python3 Scripts/gen-changelog.py --notes 1.0.5 print plain notes for one version (TestFlight)

Version bumps and dependency pin updates are left out.
"""
import argparse, pathlib, re, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CHANGELOG = ROOT / "CHANGELOG.md"
# Project paths over time (the project was renamed once).
PBXPROJ_PATHS = ("NextExplorer.xcodeproj/project.pbxproj", "NetxExplorer.xcodeproj/project.pbxproj")
REPO_URL = "https://github.com/PhillipMaizza/NextExplorer-iOS"
# TestFlight caps "What to Test" at 4000 characters.
NOTES_LIMIT = 4000

SKIP = re.compile(r"^(bump version|update package\.resolved)|^initial commit$", re.IGNORECASE)
MERGE_PR = re.compile(r"^Merge pull request #(\d+)")
TRAILING_PR = re.compile(r"\s*\(#(\d+)\)\s*$")
TICKET = re.compile(r"^NXTIOS-\d+:\s*")
VERSION_MENTION = re.compile(r",?\s*\bv\d+(?:\.\d+)+\b")
MARKETING_VERSION = re.compile(r"MARKETING_VERSION = ([0-9.]+);")


def git(*args):
    return subprocess.run(["git", "-C", str(ROOT), *args], check=True, capture_output=True, text=True).stdout


def version_key(version):
    return tuple(int(part) for part in version.split("."))


def project_blob(commit):
    for path in PBXPROJ_PATHS:
        found = subprocess.run(
            ["git", "-C", str(ROOT), "rev-parse", "--verify", "--quiet", f"{commit}:{path}"],
            capture_output=True,
            text=True,
        )
        if found.returncode == 0:
            return found.stdout.strip()
    return None


def app_version(commit, cache):
    """The app's MARKETING_VERSION at `commit`. Test targets carry a lower one, so take the max."""
    blob = project_blob(commit)
    if blob not in cache:
        found = MARKETING_VERSION.findall(git("cat-file", "-p", blob)) if blob else []
        cache[blob] = max(found, key=version_key) if found else None
    return cache[blob]


def entry(subject, body):
    """(text, PR number) for one main commit, or None when it is left out."""
    pr = None
    merge = MERGE_PR.match(subject)
    if merge:
        pr = merge.group(1)
        lines = [line.strip() for line in body.splitlines() if line.strip()]
        subject = lines[0] if lines else subject
    else:
        trailing = TRAILING_PR.search(subject)
        if trailing:
            pr = trailing.group(1)
            subject = subject[: trailing.start()]
    text = VERSION_MENTION.sub("", TICKET.sub("", subject)).strip().rstrip(",.")
    if not text or SKIP.search(text):
        return None
    # Capitalize, but leave words like "iPhone" alone.
    if text[0].islower() and not (len(text) > 1 and text[1].isupper()):
        text = text[0].upper() + text[1:]
    return text, pr


def releases(ref):
    """[(version, date, [(text, pr)])], newest version first."""
    log = git("log", "--first-parent", "--format=%H%x1f%cs%x1f%s%x1f%b%x1e", ref)
    cache, groups, order = {}, {}, []
    for record in filter(None, (r.strip("\n") for r in log.split("\x1e"))):
        commit, date, subject, body = record.split("\x1f", 3)
        version = app_version(commit, cache)
        made = entry(subject, body)
        if version is None or made is None:
            continue
        if version not in groups:
            groups[version] = {"date": date, "entries": []}
            order.append(version)
        groups[version]["entries"].append(made)
    order.sort(key=version_key, reverse=True)
    return [(v, groups[v]["date"], groups[v]["entries"]) for v in order]


def markdown(history):
    out = [
        "# Changelog",
        "",
        "Generated from the git history of `main` by `Scripts/gen-changelog.py`; do not edit by hand.",
        "",
    ]
    for version, date, entries in history:
        out += [f"## {version} ({date})", ""]
        for text, pr in entries:
            link = f" ([#{pr}]({REPO_URL}/pull/{pr}))" if pr else ""
            out.append(f"- {text}{link}")
        out.append("")
    return "\n".join(out)


def notes(history, version):
    for candidate, _, entries in history:
        if candidate == version:
            text = "\n".join(f"- {text}" for text, _ in entries)
            return text[:NOTES_LIMIT]
    return ""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--notes", metavar="VERSION", help="print plain notes for one version")
    parser.add_argument("--ref", default="HEAD", help="history to read (default HEAD)")
    args = parser.parse_args()
    history = releases(args.ref)
    if args.notes:
        print(notes(history, args.notes))
        return
    CHANGELOG.write_text(markdown(history))
    print(f"Wrote {CHANGELOG.relative_to(ROOT)} ({len(history)} versions)")


if __name__ == "__main__":
    sys.exit(main())
