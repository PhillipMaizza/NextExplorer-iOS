#!/usr/bin/env python3
"""Machine-translate strings.tsv into Packages/Localization/translations/<lang>.tsv using
deep-translator's MyMemory backend (keyless). Format specifiers (%@, %lld, %1$@, …) are masked to
private-use characters before translation and restored after, so no specifier is dropped. Identical
English strings are translated once per language (cache). A per-string failure is skipped, leaving
that key to fall back to English in the catalog. Placeholder integrity is re-checked by gen-l10n.py.

    /tmp/xlate-venv/bin/python Scripts/machine-translate.py [lang ...]

Default targets are the languages NOT hand-authored (es/it/pt are kept as-is).
"""
import re
import sys
import time
import pathlib

from deep_translator import MyMemoryTranslator

ROOT = pathlib.Path(__file__).resolve().parent.parent
TSV = ROOT / "Packages" / "Localization" / "strings.tsv"
OUT = ROOT / "Packages" / "Localization" / "translations"

# Our code -> MyMemory locale code.
MYMEMORY = {
    "de": "de-DE", "es": "es-ES", "fr": "fr-FR", "hi": "hi-IN", "it": "it-IT",
    "ko": "ko-KR", "nl": "nl-NL", "pl": "pl-PL", "pt": "pt-PT", "ro": "ro-RO",
    "ru": "ru-RU", "sv": "sv-SE", "zh-CN": "zh-CN", "zh-TW": "zh-TW",
}
DEFAULT_TARGETS = ["de", "fr", "hi", "ko", "nl", "pl", "ro", "ru", "sv", "zh-CN", "zh-TW"]

SPEC = re.compile(r"%(?:\d+\$)?(?:@|lld|ld|d|lf|f)")


def read_en():
    entries = []
    for raw in TSV.read_text().splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        key, tab, value = raw.partition("\t")
        if tab:
            entries.append((key.strip(), value))
    return entries


def mask(value):
    """Replace each format specifier with a `{n}` token — MyMemory preserves these verbatim across
    every language and may reorder them, which the id-based restore below handles correctly."""
    specs = []

    def repl(m):
        specs.append(m.group(0))
        return "{%d}" % (len(specs) - 1)

    return SPEC.sub(repl, value), specs


def unmask(text, specs):
    for i, spec in enumerate(specs):
        text = text.replace("{%d}" % i, spec)
    return text


def looks_like_error(text):
    if not text:
        return True
    upper = text.upper()
    return "MYMEMORY WARNING" in upper or "QUERY LENGTH LIMIT" in upper or "INVALID" in upper and "EMAIL" in upper


def load_existing(code):
    """Existing {key: value} for a language, so a re-run only fills keys added since."""
    path = OUT / f"{code}.tsv"
    if not path.exists():
        return {}
    existing = {}
    for raw in path.read_text().splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        key, tab, value = raw.partition("\t")
        if tab:
            existing[key.strip()] = value
    return existing


def translate_lang(code, entries):
    translator = MyMemoryTranslator(source="en-GB", target=MYMEMORY[code])
    existing = load_existing(code)
    cache = {}
    lines = [f"# NextExplorer — {code}. Machine-translated (MyMemory) via Scripts/machine-translate.py."]
    done = 0
    failed = 0
    for key, value in entries:
        if key in existing:
            lines.append(f"{key}\t{existing[key]}")
            done += 1
            continue
        masked, specs = mask(value)
        if masked in cache:
            translated = cache[masked]
        else:
            translated = None
            for attempt in range(3):
                try:
                    res = translator.translate(masked)
                    if looks_like_error(res):
                        raise RuntimeError(res)
                    translated = res
                    break
                except Exception:  # noqa: BLE001
                    time.sleep(1.5 * (attempt + 1))
            cache[masked] = translated
            time.sleep(0.12)
        if translated is None:
            failed += 1
            continue  # leave key to fall back to English
        restored = unmask(translated, specs).replace("\n", " ").strip()
        lines.append(f"{key}\t{restored}")
        done += 1
    (OUT / f"{code}.tsv").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{code}: {done} translated, {failed} fell back to English")


def main():
    OUT.mkdir(exist_ok=True)
    entries = read_en()
    targets = sys.argv[1:] or DEFAULT_TARGETS
    for code in targets:
        if code not in MYMEMORY:
            print(f"skip unknown {code}")
            continue
        translate_lang(code, entries)


if __name__ == "__main__":
    main()
