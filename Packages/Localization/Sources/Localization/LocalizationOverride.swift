import Foundation
import os

/// Runtime language override backing the in-app language switch. `apply(_:)` points every `tr()`
/// lookup at the chosen language's compiled `.lproj` inside this package's bundle; with no override
/// (or an unknown code) it falls back to `.module`, i.e. the system-resolved language. Generated
/// `L10n.swift` reads `bundle`/`locale` here.
public enum LocalizationOverride {
    /// The app's UI languages, mirroring the web app's set. `en` is the source language.
    public static let supportedLanguages = ["en", "ar", "de", "es", "fr", "hi", "it", "ja", "ko", "nl", "pl", "pt", "ro", "ru", "sv", "zh-CN", "zh-TW"]

    /// Each language's own name (endonym), shown in the picker so a speaker recognizes their
    /// language regardless of the current UI language.
    public static let displayNames: [String: String] = [
        "en": "English", "ar": "العربية", "de": "Deutsch", "es": "Español", "fr": "Français",
        "hi": "हिन्दी", "it": "Italiano", "ja": "日本語", "ko": "한국어", "nl": "Nederlands",
        "pl": "Polski", "pt": "Português", "ro": "Română", "ru": "Русский",
        "sv": "Svenska", "zh-CN": "简体中文", "zh-TW": "繁體中文",
    ]

    public static func displayName(for code: String) -> String {
        displayNames[code] ?? code
    }

    private struct Override {
        var bundle: Bundle?
        var locale: Locale?
    }

    /// `tr()` reads this on every string lookup and it is written only on a language switch, so an
    /// unfair lock keeps the hot read path close to free while staying correct if a lookup ever
    /// races the switch.
    private static let state = OSAllocatedUnfairLock(initialState: Override())

    /// Bundle every `tr()` lookup resolves through. The chosen language's `.lproj`, or `.module`.
    public static var bundle: Bundle {
        (state.withLock { $0.bundle }) ?? .module
    }

    /// Locale used to format interpolated numbers/dates in `tr(_:_ :)`. Follows the override so a
    /// switched language also formats its arguments in that locale, not the device's.
    public static var locale: Locale {
        (state.withLock { $0.locale }) ?? .current
    }

    /// Point lookups at `language`'s compiled resources. `nil`, `"en"` with no bundle, or an
    /// unknown code clears the override (system language). Safe to call from any thread; the caller
    /// is responsible for refreshing the UI (the app rebinds `\.locale` at its root).
    public static func apply(_ language: String?) {
        guard let language,
              let path = Bundle.module.path(forResource: language, ofType: "lproj"),
              let resolved = Bundle(path: path)
        else {
            state.withLock { $0 = Override() }
            return
        }
        state.withLock { $0 = Override(bundle: resolved, locale: Locale(identifier: language)) }
    }

    /// Whether a language reads right to left, so the UI can flip `\.layoutDirection`. Arabic (`ar`)
    /// is the shipped RTL language; the same path serves any RTL language added later.
    public static func isRTL(_ language: String) -> Bool {
        Locale.Language(identifier: language).characterDirection == .rightToLeft
    }
}
