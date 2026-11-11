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
TRANSLATIONS = PKG / "translations"

# Non-English languages, mirroring the web app's set (frontend/src/i18n). `en` is the source in
# strings.tsv; each of these has an optional translations/<code>.tsv (key<TAB>value). Missing keys
# fall back to the English source automatically at lookup time.
# The web app ships de/es/fr/hi/it/ko/pl/ro/ru/sv/zh-CN/zh-TW; nl, pt, ja and ar are added beyond
# that set (Portuguese + main European per request, plus Japanese and Arabic as major world
# languages: Arabic is right to left and exercises the RTL layout path).
PLURAL_CATEGORIES = ("zero", "one", "two", "few", "many", "other")
PLURAL_KEY = re.compile(r"^(?P<base>.+)#(?P<category>" + "|".join(PLURAL_CATEGORIES) + ")$")

LANGUAGES = ["ar", "cs", "da", "de", "el", "es", "fi", "fr", "he", "hi", "hu", "id", "it", "ja", "ko", "nb", "nl", "pl", "pt", "pt-BR", "ro", "ru", "sv", "th", "tr", "uk", "vi", "zh-CN", "zh-TW"]


def _parse_tsv(path):
    entries = []
    for raw in path.read_text().splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        key, tab, value = raw.partition("\t")
        if not tab:
            raise SystemExit(f"{path.name}: missing tab: {raw!r}")
        key = key.strip()
        value = value.replace("\\n", "\n")
        if not key or not value:
            raise SystemExit(f"{path.name}: bad line: {raw!r}")
        entries.append((key, value))
    keys = [k for k, _ in entries]
    dupes = {k for k in keys if keys.count(k) > 1}
    if dupes:
        raise SystemExit(f"{path.name}: duplicate keys: {sorted(dupes)}")
    return entries


def parse():
    return _parse_tsv(TSV)


def split_plurals(entries):
    """Plural strings are written as `base#category<TAB>value` lines (CLDR categories). Returns the
    plain entries and `{base: {category: value}}`; every plural needs at least `other`."""
    plain, plurals = [], {}
    for key, value in entries:
        match = PLURAL_KEY.match(key)
        if match:
            plurals.setdefault(match["base"], {})[match["category"]] = value
        else:
            plain.append((key, value))
    for base, forms in plurals.items():
        if "other" not in forms:
            raise SystemExit(f"{base}: plural needs an #other form")
    return plain, plurals


def _format_tokens(value):
    """The multiset of printf specifiers in a string, e.g. %@ %lld %1$@, order insensitive so a
    language may reorder arguments (positional %n$@) but must keep the same set."""
    return sorted(re.findall(r"%(?:\d+\$)?(?:@|lld|ld|d|lf|f)", value))


def parse_translations(en_map):
    """Load translations/<lang>.tsv into {lang: {key: value}}. Skips any key not in the English
    source (a stale key from a rename shouldn't leak into the catalog) and fails on a translation
    whose format specifiers don't match the English source (a dropped %@/%lld would crash at
    interpolation)."""
    result = {}
    problems = []
    for lang in LANGUAGES:
        path = TRANSLATIONS / f"{lang}.tsv"
        if not path.exists():
            continue
        mapping = {}
        for key, value in _parse_tsv(path):
            match = PLURAL_KEY.match(key)
            source = f"{match['base']}#other" if match else key
            if source not in en_map:
                continue
            if _format_tokens(value) != _format_tokens(en_map[source]):
                problems.append(f"{lang}/{key}: placeholders {_format_tokens(value)} != en {_format_tokens(en_map[source])}")
            mapping[key] = value
        result[lang] = mapping
    if problems:
        raise SystemExit("placeholder mismatch:\n  " + "\n  ".join(problems))
    missing_other = missing_other_forms(result)
    if missing_other:
        raise SystemExit("plural translation needs an #other form:\n  " + "\n  ".join(missing_other))
    return result


def missing_other_forms(translations):
    """`lang/base` for every language that translates some plural forms of a key but not `#other`.
    Such a language would otherwise be dropped from the catalog without a word."""
    problems = []
    for lang, mapping in translations.items():
        bases = {}
        for key in mapping:
            match = PLURAL_KEY.match(key)
            if match:
                bases.setdefault(match["base"], set()).add(match["category"])
        problems += [f"{lang}/{base}" for base, forms in sorted(bases.items()) if "other" not in forms]
    return problems


def write_catalog(entries, plurals, translations):
    def localizations(key, en_value):
        locs = {"en": {"stringUnit": {"state": "translated", "value": en_value}}}
        for lang in LANGUAGES:
            value = translations.get(lang, {}).get(key)
            if value is not None:
                locs[lang] = {"stringUnit": {"state": "translated", "value": value}}
        return locs

    strings = {
        key: {"extractionState": "manual", "localizations": localizations(key, value)}
        for key, value in entries
    }
    def plural_localizations(base, forms):
        def variations(values):
            return {"plural": {c: {"stringUnit": {"state": "translated", "value": values[c]}} for c in PLURAL_CATEGORIES if c in values}}

        locs = {"en": {"variations": variations(forms)}}
        for lang in LANGUAGES:
            values = {c: translations.get(lang, {}).get(f"{base}#{c}") for c in PLURAL_CATEGORIES}
            values = {c: v for c, v in values.items() if v is not None}
            if "other" in values:
                locs[lang] = {"variations": variations(values)}
        return locs

    for base, forms in plurals.items():
        strings[base] = {"extractionState": "manual", "localizations": plural_localizations(base, forms)}
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
        "// Looks up through `LocalizationOverride.bundle` so an in-app language switch resolves live",
        "// (it points at the chosen language's compiled `.lproj`); with no override it is `.module`,",
        "// i.e. the system-resolved language. The key itself is the fallback when a language is",
        "// missing an entry, which the String Catalog only fills for `en`.",
        "private func tr(_ key: String) -> String {",
        '    LocalizationOverride.bundle.localizedString(forKey: key, value: key, table: "Localizable")',
        "}",
        "",
        "private func tr(_ key: String, _ arguments: CVarArg...) -> String {",
        "    String(format: tr(key), locale: LocalizationOverride.locale, arguments: arguments)",
        "}",
    ]
    L10N.write_text("\n".join(lines) + "\n")


def main():
    raw = parse()
    en_map = dict(raw)
    entries, plurals = split_plurals(raw)
    translations = parse_translations(en_map)
    write_catalog(entries, plurals, translations)
    write_l10n(entries + [(base, forms["other"]) for base, forms in plurals.items()])
    counts = ", ".join(f"{lang}:{len(translations.get(lang, {}))}" for lang in LANGUAGES)
    print(f"{len(entries) + len(plurals)} keys (en) -> {CATALOG.name}, {L10N.name}")
    print(f"translations: {counts}")


if __name__ == "__main__":
    main()
