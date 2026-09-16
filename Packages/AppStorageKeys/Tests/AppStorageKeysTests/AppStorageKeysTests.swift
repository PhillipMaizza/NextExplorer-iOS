@testable import AppStorageKeys
import Testing

/// The key strings are a storage contract — changing one silently orphans every existing
/// user's saved preference. This pins them so a rename can't happen by accident.
@Suite("AppStorageKeys")
struct AppStorageKeysTests {
    @Test func keysMatchTheirPersistedStrings() {
        #expect(AppStorageKeys.appearanceOverrideSet == "hasSetAppearanceOverride")
        #expect(AppStorageKeys.prefersDarkMode == "prefersDarkMode")
        #expect(AppStorageKeys.dateDisplayFormat == "dateDisplayFormat")
        #expect(AppStorageKeys.includeTimeInDates == "includeTimeInDates")
        #expect(AppStorageKeys.thumbnailSize == "thumbnailSize")
        #expect(AppStorageKeys.renderHTMLPages == "renderHTMLPages")
        #expect(AppStorageKeys.renderMarkdownPages == "renderMarkdownPages")
        #expect(AppStorageKeys.hapticsEnabled == "hapticsEnabled")
        #expect(AppStorageKeys.showFilenameExtensions == "showFilenameExtensions")
        #expect(AppStorageKeys.removeArchiveAfterDownload == "removeArchiveAfterDownload")
        #expect(AppStorageKeys.keepClipboardAfterCopy == "keepClipboardAfterCopy")
        #expect(AppStorageKeys.browseViewMode == "browseViewMode")
        #expect(AppStorageKeys.favoritesViewMode == "favoritesViewMode")
        #expect(AppStorageKeys.downloadsViewMode == "downloadsViewMode")
    }
}
