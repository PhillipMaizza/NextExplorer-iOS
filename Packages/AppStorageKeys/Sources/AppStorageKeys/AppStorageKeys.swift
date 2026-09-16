import Foundation

/// Every `UserDefaults` key the app reads through `@AppStorage`, spelled once. Its own
/// package because the app target, every feature package and DesignSystem's haptics modifier
/// all need it.
///
/// These are lightweight per-device UI preferences only. Anything the server owns, or that
/// must round-trip through a reducer, belongs in TCA state, not here.
public enum AppStorageKeys {
    /// Whether the user has ever chosen a light/dark override; until then the app follows the system.
    public static let appearanceOverrideSet = "hasSetAppearanceOverride"
    /// The chosen override, meaningful only once `appearanceOverrideSet` is true.
    public static let prefersDarkMode = "prefersDarkMode"

    /// `DateDisplayFormat.rawValue`.
    public static let dateDisplayFormat = "dateDisplayFormat"
    public static let includeTimeInDates = "includeTimeInDates"

    /// `ThumbnailSize.rawValue`.
    public static let thumbnailSize = "thumbnailSize"

    public static let renderHTMLPages = "renderHTMLPages"
    public static let renderMarkdownPages = "renderMarkdownPages"

    public static let hapticsEnabled = "hapticsEnabled"
    public static let showFilenameExtensions = "showFilenameExtensions"
    /// Whether the tab bar shows a text title under each icon. On by default.
    public static let showTabLabels = "showTabLabels"
    public static let removeArchiveAfterDownload = "removeArchiveAfterDownload"
    public static let keepClipboardAfterCopy = "keepClipboardAfterCopy"

    /// Chosen UI language code (e.g. "fr", "zh-CN"). Empty string means follow the system
    /// language. Read by `LocalizationOverride` at launch and by the app root to rebind the locale.
    public static let appLanguage = "appLanguage"

    /// Per-tab list/grid choice; the value is that tab's own `…ViewMode.rawValue`.
    public static let browseViewMode = "browseViewMode"
    public static let favoritesViewMode = "favoritesViewMode"
    public static let downloadsViewMode = "downloadsViewMode"

    /// Preferences reset to their defaults on sign out, so a new session on this device starts
    /// clean instead of inheriting the previous account's view modes and display choices.
    /// Device-level chrome the user sets for themselves, not per account (appearance, language,
    /// haptics), is deliberately left untouched.
    public static let sessionScopedKeys: [String] = [
        browseViewMode, favoritesViewMode, downloadsViewMode,
        thumbnailSize, showFilenameExtensions, showTabLabels,
        renderHTMLPages, renderMarkdownPages,
        removeArchiveAfterDownload, keepClipboardAfterCopy,
        dateDisplayFormat, includeTimeInDates,
    ]

    /// Clears every `sessionScopedKeys` entry so each `@AppStorage` falls back to its declared
    /// default. Called at sign out / session end alongside the cache clears.
    public static func resetSessionPreferences(in defaults: UserDefaults = .standard) {
        for key in sessionScopedKeys {
            defaults.removeObject(forKey: key)
        }
    }
}
