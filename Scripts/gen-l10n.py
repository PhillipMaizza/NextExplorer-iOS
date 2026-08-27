#!/usr/bin/env python3
"""Regenerate the Localization package from its `strings.tsv`.

`strings.tsv` (one `key<TAB>English value` per line, `#` comments, `\\n` for newlines) is the
human-edited source. This writes:
  - Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings
  - Packages/Localization/Sources/Localization/L10n.swift  (two-level: L10n.<Namespace>.<accessor>)

Run from anywhere: `python3 Scripts/gen-l10n.py`
"""
import json, re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
PKG = ROOT / "Packages" / "Localization"
TSV = PKG / "strings.tsv"
CATALOG = PKG / "Sources" / "Localization" / "Resources" / "Localizable.xcstrings"
L10N = PKG / "Sources" / "Localization" / "L10n.swift"


def parse():
    entries = []
    for raw in TSV.read_text().splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        key, tab, value = raw.partition("\t")
        if not tab:
            raise SystemExit(f"missing tab: {raw!r}")
        key = key.strip()
        value = value.replace("\\n", "\n")
        if not key or not value:
            raise SystemExit(f"bad line: {raw!r}")
        entries.append((key, value))
    keys = [k for k, _ in entries]
    dupes = {k for k in keys if keys.count(k) > 1}
    if dupes:
        raise SystemExit(f"duplicate keys: {sorted(dupes)}")
    return entries


def write_catalog(entries):
    strings = {
        key: {
            "extractionState": "manual",
            "localizations": {"en": {"stringUnit": {"state": "translated", "value": value}}},
        }
        for key, value in entries
    }
    catalog = {"sourceLanguage": "en", "strings": dict(sorted(strings.items())), "version": "1.0"}
    CATALOG.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n")


def write_l10n(entries):
    def pascal(s):
        return s[:1].upper() + s[1:]

    def camel_join(parts):
        return parts[0] + "".join(p[:1].upper() + p[1:] for p in parts[1:])

    ns = {}
    for key, value in entries:
        segs = key.split(".")
        namespace = pascal(segs[0])
        accessor = camel_join(segs[1:]) if len(segs) > 1 else segs[0]
        pos = re.findall(r"%(\d+)\$", value)
        nargs = len(set(pos)) if pos else len(re.findall(r"%(?:lld|@|d)", value))
        ns.setdefault(namespace, []).append((accessor, key, nargs, value))

    lines = [
        "import Foundation",
        "",
        "// Generated from strings.tsv by Scripts/gen-l10n.py. Do not edit by hand.",
        "",
        "public enum L10n {",
    ]
    for namespace in sorted(ns):
        lines.append(f"    public enum {namespace} {{")
        for accessor, key, nargs, value in sorted(ns[namespace]):
            note = f'  // "{value}"' if "\n" not in value and len(value) <= 60 else ""
            if nargs == 0:
                lines.append(f'        public static var {accessor}: String {{ tr("{key}") }}{note}')
            else:
                params = ", ".join(f"_ a{i}: CVarArg" for i in range(nargs))
                args = ", ".join(f"a{i}" for i in range(nargs))
                lines.append(
                    f'        public static func {accessor}({params}) -> String {{ tr("{key}", {args}) }}'
                )
        lines.append("    }")
    lines += [
        "}",
        "",
        "private func tr(_ key: String) -> String {",
        '    String(localized: String.LocalizationValue(key), table: "Localizable", bundle: .module)',
        "}",
        "",
        "private func tr(_ key: String, _ arguments: CVarArg...) -> String {",
        "    String(format: tr(key), locale: .current, arguments: arguments)",
        "}",
    ]
    L10N.write_text("\n".join(lines) + "\n")


def main():
    entries = parse()
    write_catalog(entries)
    write_l10n(entries)
    print(f"{len(entries)} keys -> {CATALOG.name}, {L10N.name}")


if __name__ == "__main__":
    main()
