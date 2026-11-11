import Foundation
@testable import Localization
import Testing

/// Reads the checked in String Catalog itself, so a plural that lost a form or a translation that
/// dropped a placeholder is caught here rather than as a wrong sentence on a device.
@Suite("String catalog")
struct CatalogTests {
    private struct Catalog: Decodable {
        let strings: [String: Entry]
    }

    private struct Entry: Decodable {
        let localizations: [String: Localization]?
    }

    private struct Localization: Decodable {
        let stringUnit: Unit?
        let variations: Variations?
    }

    private struct Variations: Decodable {
        let plural: [String: Form]?
    }

    private struct Form: Decodable {
        let stringUnit: Unit
    }

    private struct Unit: Decodable {
        let value: String
    }

    /// The plural categories a language needs for whole numbers, from the CLDR plural rules.
    private static let requiredCategories: [String: Set<String>] = [
        "en": ["one", "other"], "de": ["one", "other"], "es": ["one", "other"], "fr": ["one", "other"],
        "it": ["one", "other"], "nl": ["one", "other"], "pt": ["one", "other"], "pt-BR": ["one", "other"], "tr": ["one", "other"], "id": ["other"], "vi": ["other"], "sv": ["one", "other"],
        "hi": ["one", "other"],
        "ru": ["one", "few", "many", "other"], "pl": ["one", "few", "many", "other"],
        "uk": ["one", "few", "many", "other"], "he": ["one", "two", "other"], "da": ["one", "other"], "nb": ["one", "other"], "fi": ["one", "other"], "el": ["one", "other"], "hu": ["one", "other"], "th": ["other"], "cs": ["one", "few", "many", "other"],
        "ro": ["one", "few", "other"],
        "ar": ["zero", "one", "two", "few", "many", "other"],
        "ja": ["other"], "ko": ["other"], "zh-CN": ["other"], "zh-TW": ["other"],
    ]

    private static func catalog() throws -> Catalog {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Localization/Resources/Localizable.xcstrings")
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }

    /// The placeholders of a format, order and positions ignored: a language may reorder arguments.
    private static func placeholders(of value: String) -> [String] {
        let placeholder = /%(?:\d+\$)?(?:@|lld|ld|d|lf|f)/
        return value.matches(of: placeholder).map { String($0.output.replacing(/\d+\$/, with: "")) }.sorted()
    }

    @Test("the table covers every language the app ships")
    func tableCoversEveryLanguage() {
        #expect(Set(Self.requiredCategories.keys) == Set(LocalizationOverride.supportedLanguages))
    }

    @Test("every plural string has all the forms its language needs, in every language")
    func pluralsAreComplete() throws {
        let catalog = try Self.catalog()
        let plurals = catalog.strings.filter { $0.value.localizations?["en"]?.variations?.plural != nil }
        #expect(!plurals.isEmpty)
        for (key, entry) in plurals {
            for language in LocalizationOverride.supportedLanguages {
                let forms = Set(entry.localizations?[language]?.variations?.plural?.keys.map { $0 } ?? [])
                let missing = (Self.requiredCategories[language] ?? []).subtracting(forms)
                #expect(missing.isEmpty, "\(key) in \(language) lacks \(missing.sorted())")
            }
        }
    }

    @Test("every form of every plural keeps the placeholders of the English text, in every language")
    func pluralPlaceholdersMatch() throws {
        let catalog = try Self.catalog()
        for (key, entry) in catalog.strings {
            guard
                let english = entry.localizations?["en"]?.variations?.plural,
                let reference = english["other"].map({ Self.placeholders(of: $0.stringUnit.value) })
            else { continue }
            for (language, localization) in entry.localizations ?? [:] {
                for (category, form) in localization.variations?.plural ?? [:] {
                    #expect(Self.placeholders(of: form.stringUnit.value) == reference, "\(key) \(language) \(category)")
                }
            }
        }
    }

    @Test("every translated plain string keeps the placeholders of its English source")
    func plainPlaceholdersMatch() throws {
        let catalog = try Self.catalog()
        for (key, entry) in catalog.strings {
            guard let english = entry.localizations?["en"]?.stringUnit?.value else { continue }
            let reference = Self.placeholders(of: english)
            for (language, localization) in entry.localizations ?? [:] {
                guard let value = localization.stringUnit?.value else { continue }
                #expect(Self.placeholders(of: value) == reference, "\(key) \(language)")
            }
        }
    }
}
