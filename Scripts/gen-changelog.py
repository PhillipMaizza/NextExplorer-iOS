#!/usr/bin/env python3
"""Generate the changelog from the git history of main.

Every PR lands on main as one commit (`NXTIOS-XXXX: summary (#N)`, or a merge commit for the
early ones), and `fastlane release` tags each shipped version `v<version>` on main. This walks
main's first parent history: the commits up to a release tag belong to that version, and the
commits after the newest tag to the upcoming one. History older than the first tag predates
tagging; there every release PR bumped MARKETING_VERSION, so those commits group by the
MARKETING_VERSION they carried.

  python3 Scripts/gen-changelog.py                       full changelog as Markdown (stdout)
  python3 Scripts/gen-changelog.py --notes 1.0.6         notes for one version (TestFlight)
  python3 Scripts/gen-changelog.py --notes 1.0.6 --links same, with (#PR) references (GitHub Release)
  python3 Scripts/gen-changelog.py --platform mac --notes 1.0.1   the Mac app's notes, from mac-v tags

The Mac app has its own versions and `mac-v<version>` tags. It has no untagged history of its
own: everything before its first tag belongs to that first Mac release.

Only what users notice is kept. A title is split into its comma separated clauses and the
technical ones (tests, CI, lint, tooling, refactors, dependency pins, docs) are dropped; a PR
with nothing user facing left is left out entirely.
"""
import argparse, pathlib, re, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
# Project paths over time (the project was renamed once).
PBXPROJ_PATHS = ("NextExplorer.xcodeproj/project.pbxproj", "NetxExplorer.xcodeproj/project.pbxproj")
REPO_URL = "https://github.com/PhillipMaizza/NextExplorer-iOS"
# TestFlight caps "What to Test" at 4000 characters.
NOTES_LIMIT = 4000

SKIP = re.compile(r"^(bump version|update package\.resolved)|^initial commit$", re.IGNORECASE)
TECHNICAL = re.compile(
    r"\b(tests?|ui ?tests?|xcuitests?|ci|lint|linting|swiftformat|swiftlint|flakes?|flaky|de-?flake|"
    r"fastlane|lanes?|changelog|releases?|refactor\w*|dedup\w*|state machines?|import sort|"
    r"package\.resolved|pins?|dependenc(y|ies)|readme|contributing|license|workflows?|"
    r"build[- ]phase|instrument\w*|warnings?|docs?|dto|dataphase|domain split|reorg|"
    r"main[- ]thread|bool clusters?|typography rename)\b",
    re.IGNORECASE,
)
MERGE_PR = re.compile(r"^Merge pull request #(\d+)")
TRAILING_PR = re.compile(r"\s*\(#(\d+)\)\s*$")
TICKET = re.compile(r"^NXTIOS-\d+(?:/\d+)*:\s*")
VERSION_MENTION = re.compile(r",?\s*\bv\d+(?:\.\d+)+\b")
MARKETING_VERSION = re.compile(r"MARKETING_VERSION = ([0-9.]+);")
# Release tag prefix per platform: iOS ships `v1.0.6`, the Mac `mac-v1.0.0`.
TAG_PREFIXES = {"ios": "v", "mac": "mac-v"}
UPCOMING = "Unreleased"


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
    text = user_facing(text)
    if not text:
        return None
    # Capitalize, but leave words like "iPhone" alone.
    if text[0].islower() and not (len(text) > 1 and text[1].isupper()):
        text = text[0].upper() + text[1:]
    return text, pr


def release_tags(platform="ios"):
    """{commit: version} for every release tag of `platform`."""
    prefix = TAG_PREFIXES[platform]
    pattern = re.compile(rf"^{re.escape(prefix)}(\d+(?:\.\d+)+)$")
    tags = {}
    for line in git("tag", "--list", f"{prefix}*", "--format=%(objectname) %(*objectname) %(refname:short)").splitlines():
        parts = line.split()
        name = parts[-1]
        match = pattern.match(name)
        if match:
            # Annotated tags point at a tag object; the peeled commit is the second field.
            commit = parts[1] if len(parts) == 3 else parts[0]
            tags[commit] = match.group(1)
    return tags


def user_facing(title):
    """The title's user facing clauses, or "" when every clause is technical."""
    parts = re.split(r",|\s\+\s", title)
    clauses = [re.sub(r"^(and|plus)\s+", "", part.strip(), flags=re.IGNORECASE) for part in parts]
    kept = [clause for clause in clauses if clause and not TECHNICAL.search(clause)]
    return ", ".join(kept)


def releases(ref, upcoming=UPCOMING, platform="ios"):
    """[(version, date, [(text, pr)])], newest first; untagged commits first under `upcoming`."""
    log = git("log", "--first-parent", "--format=%H%x1f%cs%x1f%s%x1f%b%x1e", ref)
    tags = release_tags(platform)
    oldest = min(tags, key=lambda commit: version_key(tags[commit])) if tags else None
    cache, groups, order = {}, {}, []
    current = upcoming
    # The Mac never left a pre tag era: its first release carries everything before it.
    in_tagged_era = bool(tags) or platform == "mac"
    for record in filter(None, (r.strip("\n") for r in log.split("\x1e"))):
        commit, date, subject, body = record.split("\x1f", 3)
        if commit in tags:
            current = tags[commit]
        if commit == oldest and platform == "ios":
            in_tagged_era = False
        version = current if in_tagged_era else app_version(commit, cache)
        made = entry(subject, body)
        if version is None or made is None:
            continue
        if version not in groups:
            groups[version] = {"date": date, "entries": []}
            order.append(version)
        groups[version]["entries"].append(made)
    return [(v, groups[v]["date"], groups[v]["entries"]) for v in order]


def markdown(history):
    out = [
        "# Changelog",
        "",
        "Generated from the git history of `main` by `Scripts/gen-changelog.py`.",
        "",
    ]
    for version, date, entries in history:
        out += [f"## {version} ({date})", ""]
        for text, pr in entries:
            link = f" ([#{pr}]({REPO_URL}/pull/{pr}))" if pr else ""
            out.append(f"- {text}{link}")
        out.append("")
    return "\n".join(out)


def notes(history, version, links=False):
    for candidate, _, entries in history:
        if candidate == version:
            text = "\n".join(f"- {text}" + (f" (#{pr})" if links and pr else "") for text, pr in entries)
            return text[:NOTES_LIMIT]
    return ""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--notes", metavar="VERSION", help="print plain notes for one version")
    parser.add_argument("--ref", default="HEAD", help="history to read (default HEAD)")
    parser.add_argument("--upcoming", default=UPCOMING, help="title for commits after the newest tag")
    parser.add_argument("--links", action="store_true", help="append (#PR) references to --notes")
    parser.add_argument("--platform", choices=sorted(TAG_PREFIXES), default="ios", help="which app's tags to read")
    args = parser.parse_args()
    # Notes for a version not tagged yet are the commits since the newest tag.
    tagged = set(release_tags(args.platform).values())
    upcoming = args.notes if args.notes and args.notes not in tagged else args.upcoming
    history = releases(args.ref, upcoming=upcoming, platform=args.platform)
    if args.notes:
        print(notes(history, args.notes, links=args.links))
        return
    print(markdown(history))


if __name__ == "__main__":
    sys.exit(main())
