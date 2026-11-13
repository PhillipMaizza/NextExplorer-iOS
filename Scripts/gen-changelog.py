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

Notes speak to users. A title is split into its comma separated clauses; the technical ones
(tests, CI, lint, tooling, refactors, dependency pins, docs) and the maintenance ones (fixes,
audits, crashes, hardening, performance) are not listed one by one but folded into a single
closing line, GENERIC_NOTE, so a version made only of such work still gets a note. A title that
opens with a fix or an audit ("Fixes from a QA pass over X, Y") is folded whole, since the rest
only lists what was fixed. Version numbers in titles are dropped.
"""
import argparse, pathlib, re, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
# Project paths over time (the project was renamed once).
PBXPROJ_PATHS = ("NextExplorer.xcodeproj/project.pbxproj", "NetxExplorer.xcodeproj/project.pbxproj")
REPO_URL = "https://github.com/PhillipMaizza/NextExplorer-iOS"
# TestFlight caps "What to Test" at 4000 characters.
NOTES_LIMIT = 4000

SKIP = re.compile(r"^(bump version|update package\.resolved|format swift code)|^initial commit$", re.IGNORECASE)
GENERIC_NOTE = "Bug fixes and improvements"
TECHNICAL = re.compile(
    r"\b(tests?|ui ?tests?|xcuitests?|ci|lint|linting|swiftformat|swiftlint|flakes?|flaky|de-?flake|"
    r"testflight|fastlane|lanes?|changelog|releases?|refactor\w*|dedup\w*|state machines?|import sort|"
    r"package\.resolved|pins?|dependenc(y|ies)|swiftpm|node \d+ actions|readme|contributing|license|workflows?|"
    r"build[- ]phase|instrument\w*|warnings?|docs?|dto|dataphase|domain split|reorg|"
    r"main[- ]thread|bool clusters?|typography rename)\b",
    re.IGNORECASE,
)
# Maintenance users only notice as "it works better": folded into GENERIC_NOTE.
MAINTENANCE = re.compile(
    r"\b(fix\w*|bugs?|bugfix\w*|crash\w*|regressions?|qa pass|audit\w*|harden\w*|stabili\w*|"
    r"reliab\w*|leaks?|polish\w*|clean ?up|optimi[sz]\w*|performance|tweaks?|again)\b",
    re.IGNORECASE,
)
# A first clause like this means the rest of the title only lists what was fixed.
FIX_TITLE = re.compile(r"^(fix\w*|bugs?|bugfix\w*)\b|\b(qa pass|audit\w*)\b", re.IGNORECASE)
MERGE_PR = re.compile(r"^Merge pull request #(\d+)")
TRAILING_PR = re.compile(r"\s*\(#(\d+)\)\s*$")
TICKET = re.compile(r"^NXTIOS-\d+(?:/\d+)*:\s*")
# An app version in a title: "version 1.1.2" or "v1.0.5" anywhere, or a bare number as the last
# comma separated clause ("..., 1.0.1"). A bare number elsewhere ("iOS 18.2") is real text.
VERSION_MENTION = re.compile(
    r",?\s*\b(?:version\s+v?\d+(?:\.\d+)+|v\d+(?:\.\d+)+)\b|,\s*\d+(?:\.\d+)+\s*$",
    re.IGNORECASE,
)
MARKETING_VERSION = re.compile(r"MARKETING_VERSION = ([0-9.]+);")
RELEASE_TAG = re.compile(r"^v(\d+(?:\.\d+)+)$")
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
    """(text, PR number, folded) for one main commit, or None when it is skipped.

    text is the user facing part ("" when nothing is left); folded says some of the title went
    into GENERIC_NOTE."""
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
    text, folded = user_facing(text)
    if not text:
        return "", pr, folded
    # Capitalize, but leave words like "iPhone" alone.
    if text[0].islower() and not (len(text) > 1 and text[1].isupper()):
        text = text[0].upper() + text[1:]
    return text, pr, folded


def release_tags():
    """{commit: version} for every `v<version>` tag."""
    tags = {}
    for line in git("tag", "--list", "v*", "--format=%(objectname) %(*objectname) %(refname:short)").splitlines():
        parts = line.split()
        name = parts[-1]
        match = RELEASE_TAG.match(name)
        if match:
            # Annotated tags point at a tag object; the peeled commit is the second field.
            commit = parts[1] if len(parts) == 3 else parts[0]
            tags[commit] = match.group(1)
    return tags


def folds(clause):
    return bool(TECHNICAL.search(clause) or MAINTENANCE.search(clause))


def user_facing(title):
    """(the title's user facing clauses joined, whether any clause was folded)."""
    parts = re.split(r",|\s\+\s", title)
    clauses = [re.sub(r"^(and|plus)\s+", "", part.strip(), flags=re.IGNORECASE) for part in parts]
    clauses = [clause for clause in clauses if clause]
    if clauses and FIX_TITLE.search(clauses[0]):
        return "", True
    kept = [clause for clause in clauses if not folds(clause)]
    return ", ".join(kept), len(kept) < len(clauses)


def releases(ref, upcoming=UPCOMING):
    """[(version, date, [(text, [pr])])], newest first; untagged commits first under `upcoming`.

    A version made only of folded PRs gets GENERIC_NOTE, carrying those PRs, so it still has a note."""
    log = git("log", "--first-parent", "--format=%H%x1f%cs%x1f%s%x1f%b%x1e", ref)
    tags = release_tags()
    oldest = min(tags, key=lambda commit: version_key(tags[commit])) if tags else None
    cache, groups, order = {}, {}, []
    current = upcoming
    in_tagged_era = bool(tags)
    for record in filter(None, (r.strip("\n") for r in log.split("\x1e"))):
        commit, date, subject, body = record.split("\x1f", 3)
        if commit in tags:
            current = tags[commit]
        if commit == oldest:
            in_tagged_era = False
        version = current if in_tagged_era else app_version(commit, cache)
        made = entry(subject, body)
        if version is None or made is None:
            continue
        if version not in groups:
            groups[version] = {"date": date, "entries": [], "folded": []}
            order.append(version)
        text, pr, folded = made
        group = groups[version]
        if text:
            group["entries"].append((text, [pr] if pr else []))
        if folded:
            group["folded"].append(pr)
    history = []
    for version in order:
        group = groups[version]
        entries = list(group["entries"])
        if group["folded"] and not entries:
            entries.append((GENERIC_NOTE, [pr for pr in group["folded"] if pr]))
        history.append((version, group["date"], entries))
    return history


def markdown(history):
    out = [
        "# Changelog",
        "",
        "Generated from the git history of `main` by `Scripts/gen-changelog.py`.",
        "",
    ]
    for version, date, entries in history:
        out += [f"## {version} ({date})", ""]
        for text, prs in entries:
            links = ", ".join(f"[#{pr}]({REPO_URL}/pull/{pr})" for pr in prs)
            out.append(f"- {text}" + (f" ({links})" if links else ""))
        out.append("")
    return "\n".join(out)


def notes(history, version, links=False):
    for candidate, _, entries in history:
        if candidate == version:
            text = "\n".join(
                f"- {text}" + (f" ({', '.join(f'#{pr}' for pr in prs)})" if links and prs else "")
                for text, prs in entries
            )
            if len(text) > NOTES_LIMIT:
                text = text[:NOTES_LIMIT].rsplit("\n", 1)[0]
            return text
    return ""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--notes", metavar="VERSION", help="print plain notes for one version")
    parser.add_argument("--ref", default="HEAD", help="history to read (default HEAD)")
    parser.add_argument("--upcoming", default=UPCOMING, help="title for commits after the newest tag")
    parser.add_argument("--links", action="store_true", help="append (#PR) references to --notes")
    args = parser.parse_args()
    # Notes for a version not tagged yet are the commits since the newest tag.
    tagged = set(release_tags().values())
    upcoming = args.notes if args.notes and args.notes not in tagged else args.upcoming
    history = releases(args.ref, upcoming=upcoming)
    if args.notes:
        print(notes(history, args.notes, links=args.links))
        return
    print(markdown(history))


if __name__ == "__main__":
    sys.exit(main())
