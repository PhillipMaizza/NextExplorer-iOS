#!/usr/bin/env python3
"""Self check for gen-l10n.py: python3 Scripts/test_gen_l10n.py"""
import importlib.util
import pathlib
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent / "gen-l10n.py"
spec = importlib.util.spec_from_file_location("gen_l10n", SCRIPT)
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)


class PluralTranslationTests(unittest.TestCase):
    def test_language_with_plural_forms_but_no_other_is_reported(self):
        problems = gen.missing_other_forms({"de": {"files#one": "Datei"}, "fr": {"files#one": "a", "files#other": "b"}})
        self.assertEqual(problems, ["de/files"])

    def test_complete_plurals_and_plain_keys_pass(self):
        self.assertEqual(gen.missing_other_forms({"ar": {"files#few": "a", "files#other": "b", "ok": "c"}}), [])

    def test_parse_translations_exits_with_key_and_language(self):
        with tempfile.TemporaryDirectory() as folder:
            (pathlib.Path(folder) / "de.tsv").write_text("files#one\t%lld Datei\n")
            original = gen.TRANSLATIONS
            gen.TRANSLATIONS = pathlib.Path(folder)
            try:
                with self.assertRaises(SystemExit) as raised:
                    gen.parse_translations({"files#other": "%lld files", "files#one": "%lld file"})
            finally:
                gen.TRANSLATIONS = original
        self.assertIn("de/files", str(raised.exception))


class CatalogFallbackTests(unittest.TestCase):
    def test_every_language_gets_every_key_with_english_as_fallback(self):
        with tempfile.TemporaryDirectory() as folder:
            original = (gen.CATALOG, gen.LANGUAGES)
            gen.CATALOG = pathlib.Path(folder) / "Localizable.xcstrings"
            gen.LANGUAGES = ["de", "fr"]
            try:
                entries = [("ok", "OK"), ("only.de", "Only German")]
                plurals = {"files": {"one": "%lld file", "other": "%lld files"}}
                gen.write_catalog(entries, plurals, {"de": {"only.de": "Nur Deutsch", "files#one": "%lld Datei", "files#other": "%lld Dateien"}, "fr": {}})
                import json
                strings = json.loads(gen.CATALOG.read_text())["strings"]
            finally:
                gen.CATALOG, gen.LANGUAGES = original
        self.assertEqual(strings["ok"]["localizations"]["de"]["stringUnit"]["value"], "OK")
        self.assertEqual(strings["only.de"]["localizations"]["de"]["stringUnit"]["value"], "Nur Deutsch")
        self.assertEqual(strings["only.de"]["localizations"]["fr"]["stringUnit"]["value"], "Only German")
        self.assertEqual(strings["files"]["localizations"]["fr"]["variations"]["plural"]["other"]["stringUnit"]["value"], "%lld files")
        self.assertEqual(strings["files"]["localizations"]["de"]["variations"]["plural"]["one"]["stringUnit"]["value"], "%lld Datei")


if __name__ == "__main__":
    unittest.main()
