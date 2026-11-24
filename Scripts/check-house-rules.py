#!/usr/bin/env python3
"""Fail a commit or a branch that breaks the repository's code rules.

Line rules look only at lines a change adds, and size rules fail only when a file crosses its limit
or an oversized file grows, so older code is never blocked; it is fixed when touched.

  comment dash          a Swift comment using a dash as punctuation (hyphenated words, MARK
                        separators and DocC list items are fine)
  raw string            Text("..."), Label, Button, navigationTitle, accessibilityLabel or help with
                        a literal outside previews; use L10n
  loading flags         a stored isLoading or hasLoaded; model a DataPhase
  negated platform      #if !os(...); name the platform
  byte streaming        URLSession bytes; download the file instead
  bool name             a stored Bool not named as a question (is, has, should, can, did...); a server
                        field keeps its wire name as a CodingKeys raw value
  view size             a view file over 400 lines, newly or growing
  test size             a test file over 600 lines, newly or growing
  missing preview       a new file declaring a View without a #Preview
  key material          a private key, App Store Connect key, GitHub token or signing file
  denylisted term       a term listed in .git/info/house-rules-denylist (local only, never committed);
                        a line "!prefix" there exempts paths starting with prefix
  localization drift    strings.tsv or a translation changed but the generated files were not regenerated
  test determinism      Scripts/check-test-determinism.py on the staged tests
  comment ratchet       Scripts/check-comments.py: no Swift file gains comment lines over its baseline
  lint                  swiftformat and swiftlint on the staged Swift files
  commit message        "NXTIOS-1234: what changed", a body saying why, no co author or generator lines
  branch name           feature/NXTIOS-1234-short-slug, main or release/*

  python3 Scripts/check-house-rules.py --staged            pre-commit hook: the index only
  python3 Scripts/check-house-rules.py --base origin/main  CI: the branch since its merge base
  python3 Scripts/check-house-rules.py --commit-msg FILE   commit-msg hook

Nothing here edits, formats or stashes the working tree: staged content is read with git show and
checked in temporary copies.
"""
import argparse
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent

MAX_VIEW_LINES = 400
MAX_TEST_LINES = 600
SUBJECT = re.compile(r"^NXTIOS-\d{4}: \S")
BRANCH = re.compile(r"^(feature/NXTIOS-\d{4}-[a-z0-9-]+|main|release/.+)$")
URL = re.compile(r"[a-z]+://\S+")
# A dash standing in for a comma or colon: an em or en dash, or a spaced or doubled hyphen.
PUNCTUATION_DASH = re.compile(r"[\u2014\u2013]|\s--?\s|\w--\w")
# A MARK separator or a DocC list item opens with a dash that is markup, not punctuation.
MARKUP_DASH = re.compile(r"^//[/!]?\s*(MARK:\s*-|-\s)")
RAW_STRING = re.compile(r"\b(Text|Label|Button|navigationTitle|accessibilityLabel|help)\(\s*\"[^\"]*[A-Za-z]")
DS_TOKEN_VALUES = r"(2|4|6|8|12|16|20|24|32|40|44|48|56|64|96|192)(\.0)?"
TOKEN_LITERAL = re.compile(
    r":\s*CGFloat\s*=\s*" + DS_TOKEN_VALUES + r"\s*$"
    r"|\b(padding|spacing|cornerRadius|width|height|minWidth|maxWidth|minHeight|maxHeight|lineWidth|radius)"
    r"\s*[:(]\s*(\.\w+\s*,\s*)?" + DS_TOKEN_VALUES + r"\s*[,)]"
)
SYMBOL_LITERAL = re.compile(r"\b(Image\(systemName|systemImage|NSImage\(systemSymbolName):\s*\"")
ICON_CATALOG = "IconKit.swift"
LOADING_FLAG = re.compile(r"\bvar\s+(isLoading|hasLoaded)\w*\b")
BOOL_DECL = re.compile(r"\b(?:let|var)\s+(\w+)\s*:\s*Bool\b")
BOOL_PREFIX = re.compile(
    r"^(is|are|has|had|should|can|could|may|did|does|will|was|were|shows|supports|needs|allows|requires|wants|must|uses)[A-Z]"
)
NEGATED_PLATFORM = re.compile(r"#(if|elseif)\s+!os\(")
BYTE_STREAM = re.compile(r"URLSession\.bytes|\.bytes\((for|from):")
VIEW_DECL = re.compile(r"\bstruct\s+\w+(<[^>]*>)?\s*:\s*([\w.]+\s*,\s*)*View\b")
KEY_MATERIAL = re.compile(
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----|\bAuthKey_[A-Z0-9]{10}\b|\bghp_[A-Za-z0-9]{30,}|\bgithub_pat_\w{20,}"
    r"|\b(issuer_?id|key_?id)\b\W{1,4}[0-9a-f]{8}-[0-9a-f]{4}",
    re.IGNORECASE,
)
SIGNING_FILE = re.compile(r"\.(p8|p12|pfx|mobileprovision)$")
TEST_FIXTURE = re.compile(r"/Tests/[^/]+/Fixtures/")
BOT_AUTHOR = "[bot]@"
GENERATOR_LINES = re.compile(r"^\s*(Co-Authored-By:|.*Generated with\b)", re.IGNORECASE | re.MULTILINE)
LOCALIZATION_SOURCES = re.compile(r"^Packages/Localization/(strings\.tsv|translations/)")
GENERATED_L10N = (
    "Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings",
    "Packages/Localization/Sources/Localization/L10n.swift",
)


def git(*args, check=True):
    result = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)
    if check and result.returncode != 0:
        raise SystemExit(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout


def is_source(path):
    return path.endswith(".swift") and "/Tests/" not in path and not path.startswith("NextExplorerUITests/")


def is_test(path):
    return path.endswith(".swift") and ("/Tests/" in path or path.startswith("NextExplorerUITests/"))


def parse_diff(diff):
    """{path: [(new line number, text)]} of every added line in a unified diff run with -U0."""
    added, path, line = {}, None, 0
    for raw in diff.splitlines():
        if raw.startswith("+++ "):
            path = raw[6:] if raw.startswith("+++ b/") else None
            if path is not None:
                added.setdefault(path, [])
        elif raw.startswith("@@"):
            match = re.search(r"\+(\d+)", raw)
            line = int(match.group(1)) if match else 0
        elif raw.startswith("+") and path is not None:
            added[path].append((line, raw[1:]))
            line += 1
    return added


def comment_of(text):
    stripped = text.strip()
    if stripped.startswith(("*", "/*")):
        return stripped
    code = URL.sub("", text)
    index = code.find("//")
    return code[index:] if index >= 0 else None


def first_preview_line(content):
    for number, text in enumerate(content.splitlines(), start=1):
        if text.lstrip().startswith("#Preview"):
            return number
    return None


def split_denylist(entries):
    """Terms, and the path prefixes ("!prefix" lines) the terms do not apply to."""
    terms = [entry.lower() for entry in entries if not entry.startswith("!")]
    return terms, tuple(entry[1:] for entry in entries if entry.startswith("!"))


TOKEN_DEFINITIONS = "Packages/DesignSystem/Sources/DesignSystem/Essentials/"


def is_token_definition(path):
    """The design system files that define the tokens hold their values as literals."""
    return path.startswith(TOKEN_DEFINITIONS)


def check_lines(path, lines, content, denylist):
    findings = []
    preview_from = first_preview_line(content) if content is not None else None
    terms, exempt = split_denylist(denylist)
    for number, text in lines:
        where = f"{path}:{number}"
        if path.endswith(".swift"):
            comment = comment_of(text)
            if comment and PUNCTUATION_DASH.search(MARKUP_DASH.sub("", URL.sub("", comment))):
                findings.append(f"{where}: comment dash: {text.strip()}")
            if NEGATED_PLATFORM.search(text):
                findings.append(f"{where}: negated platform check, name the platform")
        if is_source(path):
            in_preview = preview_from is not None and number >= preview_from
            code = text.split("//", 1)[0]
            if RAW_STRING.search(code) and not in_preview and not path.endswith("Previews.swift"):
                findings.append(f"{where}: raw string, use L10n: {text.strip()}")
            if TOKEN_LITERAL.search(code) and not in_preview and not is_token_definition(path):
                findings.append(f"{where}: literal equal to a DS token, use the token: {text.strip()}")
            if SYMBOL_LITERAL.search(code) and not in_preview and not path.endswith(ICON_CATALOG):
                findings.append(f"{where}: symbol name literal, add it to IconKit: {text.strip()}")
            if LOADING_FLAG.search(code) and "{" not in code:
                findings.append(f"{where}: stored loading flag, model a DataPhase")
            for name in BOOL_DECL.findall(code):
                if not BOOL_PREFIX.match(name):
                    findings.append(f"{where}: Bool '{name}' should read as a question (is, has, should...)")
            if BYTE_STREAM.search(code):
                findings.append(f"{where}: byte by byte streaming, download instead")
        if KEY_MATERIAL.search(text):
            findings.append(f"{where}: looks like key material")
        if not path.startswith(exempt):
            lowered = text.lower()
            for term in terms:
                if term in lowered:
                    findings.append(f"{where}: denylisted term")
    return findings


def check_size(path, old, new):
    if new is None:
        return []
    if is_source(path) and VIEW_DECL.search(new):
        kind, limit = "view", MAX_VIEW_LINES
    elif is_test(path):
        kind, limit = "test", MAX_TEST_LINES
    else:
        return []
    old_count = len(old.splitlines()) if old is not None else 0
    new_count = len(new.splitlines())
    if new_count > limit and (old_count <= limit or new_count > old_count):
        return [f"{path}: {kind} file at {new_count} lines (limit {limit}, was {old_count}); split it"]
    return []


def check_new_file(path, new):
    findings = []
    if is_source(path) and new is not None and VIEW_DECL.search(new) and "#Preview" not in new:
        findings.append(f"{path}: new view file without a #Preview")
    if SIGNING_FILE.search(path) and not TEST_FIXTURE.search("/" + path):
        findings.append(f"{path}: signing or key file must never be committed")
    return findings


def check_commit_message(message, denylist):
    lines = [line for line in message.splitlines() if not line.startswith("#")]
    while lines and not lines[-1].strip():
        lines.pop()
    findings = []
    if not lines or not SUBJECT.match(lines[0]):
        findings.append("commit subject must read 'NXTIOS-1234: what changed'")
    if not any(line.strip() for line in lines[1:]):
        findings.append("commit message needs a body saying why")
    text = "\n".join(lines)
    if GENERATOR_LINES.search(text):
        findings.append("commit message carries a co author or generator line")
    lowered = text.lower()
    if any(term in lowered for term in split_denylist(denylist)[0]):
        findings.append("commit message carries a denylisted term")
    return findings


def check_branch(name):
    return [] if not name or BRANCH.match(name) else [f"branch '{name}' must read feature/NXTIOS-1234-short-slug"]


def read_denylist():
    path = pathlib.Path(git("rev-parse", "--git-path", "info/house-rules-denylist").strip())
    path = path if path.is_absolute() else ROOT / path
    if not path.exists():
        return []
    return [term.strip() for term in path.read_text().splitlines() if term.strip() and not term.startswith("#")]


def blob(spec):
    result = subprocess.run(["git", "show", spec], cwd=ROOT, capture_output=True)
    return result.stdout.decode("utf-8", "replace") if result.returncode == 0 else None


def materialize(paths, ref, into):
    """Writes the paths as staged (`ref` None) or as in a commit under `into`."""
    if not paths:
        return
    if ref is None:
        subprocess.run(["git", "checkout-index", f"--prefix={into}/", "--", *paths], cwd=ROOT, check=True, capture_output=True)
        return
    archive = subprocess.run(["git", "archive", ref, "--", *paths], cwd=ROOT, check=True, capture_output=True)
    subprocess.run(["tar", "-x", "-C", str(into)], input=archive.stdout, check=True)


def tracked(prefixes, ref):
    """Paths under the prefixes in the index (`ref` None) or in a commit."""
    listing = git("ls-files", "--", *prefixes) if ref is None else git("ls-tree", "-r", "--name-only", ref, "--", *prefixes)
    return [line for line in listing.splitlines() if line]


def check_localization(changed, ref):
    if not any(LOCALIZATION_SOURCES.match(path) for path in changed):
        return []
    spec_of = (lambda path: f":{path}") if ref is None else (lambda path: f"{ref}:{path}")
    with tempfile.TemporaryDirectory() as temp:
        into = pathlib.Path(temp)
        materialize(tracked(["Packages/Localization", "Scripts/gen-l10n.py"], ref), ref, into)
        run = subprocess.run([sys.executable, str(into / "Scripts/gen-l10n.py")], capture_output=True, text=True)
        if run.returncode != 0:
            return [f"gen-l10n.py failed: {(run.stdout + run.stderr).strip()}"]
        stale = [path for path in GENERATED_L10N if (into / path).read_text() != (blob(spec_of(path)) or "")]
    return [f"{path}: out of date, run python3 Scripts/gen-l10n.py and stage it" for path in stale]


def check_determinism(changed):
    if not any(is_test(path) for path in changed):
        return []
    with tempfile.TemporaryDirectory() as temp:
        into = pathlib.Path(temp)
        tests = [path for path in tracked(["Packages", "NextExplorerUITests"], None) if is_test(path) or "/Fixtures/" in path]
        materialize([*tests, "Scripts/check-test-determinism.py"], None, into)
        run = subprocess.run([sys.executable, str(into / "Scripts/check-test-determinism.py")], capture_output=True, text=True)
    return [] if run.returncode == 0 else [(run.stdout + run.stderr).strip()]


def check_comments(changed, ref):
    """The comment ratchet over the tree as staged (`ref` None) or as in a commit."""
    if not any(path.endswith(".swift") or path.startswith("Scripts/comment") for path in changed):
        return []
    with tempfile.TemporaryDirectory() as temp:
        into = pathlib.Path(temp)
        files = tracked(["."], ref)
        if "Scripts/comment-baseline.json" not in files:
            return []
        swift = [path for path in files if path.endswith(".swift")]
        materialize([*swift, "Scripts/check-comments.py", "Scripts/comment-baseline.json"], ref, into)
        subprocess.run(["git", "init", "-q"], cwd=into, check=True)
        subprocess.run(["git", "add", "-A"], cwd=into, check=True)
        run = subprocess.run([sys.executable, str(into / "Scripts/check-comments.py")], capture_output=True, text=True)
    return [] if run.returncode == 0 else [(run.stdout + run.stderr).strip()]


def check_lint(changed):
    swift = [path for path in changed if path.endswith(".swift") and path not in GENERATED_L10N]
    if not swift:
        return []
    findings = []
    with tempfile.TemporaryDirectory() as temp:
        into = pathlib.Path(temp)
        materialize(tracked([".swiftformat", ".swiftlint.yml", *swift], None), None, into)
        for command in (["swiftformat", "--lint", *swift], ["swiftlint", "lint", "--quiet", "--strict", "--force-exclude", *swift]):
            if shutil.which(command[0]) is None:
                findings.append(f"{command[0]} is not installed")
                continue
            run = subprocess.run(command, cwd=into, capture_output=True, text=True)
            if run.returncode != 0:
                findings.append((run.stdout + run.stderr).strip().replace(str(into) + "/", ""))
    return findings


def changed_files(diff_args):
    """Path to (status, the path it had before). A moved file is a modification of its old self, so a
    folder reshuffle is not a pile of new files."""
    changed = {}
    for line in git("diff", "--name-status", "--find-renames", *diff_args).splitlines():
        parts = line.split("\t")
        if len(parts) == 3 and parts[0].startswith("R"):
            changed[parts[2]] = ("M", parts[1])
        elif len(parts) == 2:
            changed[parts[1]] = (parts[0], parts[1])
    return changed


def check_change(diff_args, old_spec, new_spec, denylist):
    findings = []
    statuses = changed_files(diff_args)
    added = parse_diff(git("diff", "-U0", "--no-color", "--find-renames", *diff_args))
    for path, (status, was) in sorted(statuses.items()):
        if status == "D":
            continue
        new = blob(new_spec(path))
        old = None if status == "A" else blob(old_spec(was))
        findings += check_lines(path, added.get(path, []), new, denylist)
        findings += check_size(path, old, new)
        if status == "A":
            findings += check_new_file(path, new)
    return findings, [path for path, (status, _) in statuses.items() if status != "D"]


def check_worktree(paths, denylist):
    """The working tree copies of `paths` against HEAD: what the editor hook runs after each save."""
    findings = []
    for given in paths:
        file = pathlib.Path(given).resolve()
        if not file.is_file() or ROOT not in file.parents:
            continue
        path = str(file.relative_to(ROOT))
        new = file.read_text(errors="replace")
        old = blob(f"HEAD:{path}")
        if old is None:
            lines = list(enumerate(new.splitlines(), start=1))
        else:
            lines = parse_diff(git("diff", "-U0", "--no-color", "HEAD", "--", path)).get(path, [])
        findings += check_lines(path, lines, new, denylist)
        findings += check_size(path, old, new)
        if old is None:
            findings += check_new_file(path, new)
    return findings


def main():
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--staged", action="store_true")
    group.add_argument("--base")
    group.add_argument("--commit-msg", dest="commit_msg")
    group.add_argument("--files", nargs="+")
    args = parser.parse_args()
    denylist = read_denylist()

    if args.files:
        findings = check_worktree(args.files, denylist)
    elif args.commit_msg:
        findings = check_commit_message(pathlib.Path(args.commit_msg).read_text(), denylist)
    elif args.staged:
        findings, changed = check_change(["--cached"], lambda p: f"HEAD:{p}", lambda p: f":{p}", denylist)
        findings += check_branch(git("branch", "--show-current").strip())
        findings += check_localization(changed, None)
        findings += check_determinism(changed)
        findings += check_comments(changed, None)
        findings += check_lint(changed)
    else:
        base = git("merge-base", args.base, "HEAD").strip()
        authors = git("log", "--no-merges", "--format=%ae", f"{base}..HEAD").split()
        if authors and all(BOT_AUTHOR in author for author in authors):
            # The scheduled format job's own pull request: machine edits, checked by lint in its build.
            print("House rules: skipped for a bot pull request")
            return 0
        findings, changed = check_change([f"{base}...HEAD"], lambda p: f"{base}:{p}", lambda p: f"HEAD:{p}", denylist)
        findings += check_localization(changed, "HEAD")
        findings += check_comments(changed, "HEAD")
        for sha in git("rev-list", "--no-merges", f"{base}..HEAD").split():
            for finding in check_commit_message(git("log", "-1", "--format=%B", sha), denylist):
                findings.append(f"{sha[:8]}: {finding}")

    for finding in findings:
        print(finding)
    if findings:
        print(f"House rules: {len(findings)} finding(s)")
        return 1
    print("House rules: clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
