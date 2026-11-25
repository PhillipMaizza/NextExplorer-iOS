@testable import CoreModels
import Foundation
import Testing
import TestUtils

@Suite("UserPreferences decoding")
struct UserPreferencesDecodingTests {
    @Test("happy path: explicit values override the defaults")
    func decodesExplicitValues() throws {
        let prefs = try CoreModelsFixture.userPreferencesExplicitValues.decode(UserPreferences.self)
        #expect(prefs.shouldShowHiddenFiles == true)
        #expect(prefs.shouldShowThumbnails == false)
    }

    @Test("edge case: a brand-new user with no settings row decodes to client defaults")
    func decodesEmptyObjectToDefaults() throws {
        let prefs = try CoreModelsFixture.userPreferencesEmptyObject.decode(UserPreferences.self)
        #expect(prefs.shouldShowHiddenFiles == false)
        #expect(prefs.shouldShowThumbnails == true)
    }

    @Test("edge case: only one key present, the other still falls back to default")
    func decodesPartialObject() throws {
        let prefs = try CoreModelsFixture.userPreferencesPartialObject.decode(UserPreferences.self)
        #expect(prefs.shouldShowHiddenFiles == true)
        #expect(prefs.shouldShowThumbnails == true)
        #expect(prefs.defaultShareExpiration == nil)
    }

    @Test("decodes a default share expiration object")
    func decodesDefaultShareExpiration() throws {
        let prefs = try CoreModelsFixture.userPreferencesShareExpirationWeeks.decode(UserPreferences.self)
        #expect(prefs.defaultShareExpiration == UserPreferences.ShareExpiration(value: 2, unit: .weeks))
    }

    @Test("a null default share expiration decodes to nil")
    func decodesNullDefaultShareExpiration() throws {
        let prefs = try CoreModelsFixture.userPreferencesShareExpirationNull.decode(UserPreferences.self)
        #expect(prefs.defaultShareExpiration == nil)
    }

    @Test("each folder sort decodes on its own, keyed without outer slashes, and a bad one is dropped")
    func decodesFolderSorts() throws {
        let prefs = try CoreModelsFixture.userPreferencesFolderSorts.decode(UserPreferences.self)
        #expect(prefs.shouldShowHiddenFiles == true)
        let work = FolderSort(field: "dateModified", isAscending: false, updatedAt: MockDate.milliseconds)
        let photos = FolderSort(field: "size", isAscending: true, updatedAt: MockDate.milliseconds + 1)
        let media = FolderSort(field: "bitrate", isAscending: true, updatedAt: MockDate.milliseconds + 2)
        #expect(prefs.folderSorts == [
            TestPath.documentsWork: work,
            TestPath.photos2026: photos,
            TestFolder.media: media,
        ])
        #expect(prefs.folderSort(for: "/" + TestPath.photos2026) == photos)
    }

    @Test("a server that sends no folder sorts is told apart from one that has none saved")
    func missingFolderSortsStayNil() throws {
        let missing = try CoreModelsFixture.userPreferencesExplicitValues.decode(UserPreferences.self)
        let empty = try CoreModelsFixture.userPreferencesFolderSortsEmpty.decode(UserPreferences.self)
        #expect(missing.folderSorts == nil)
        #expect(empty.folderSorts == [:])
    }

    @Test("folder sorts of the wrong shape drop alone, the other preferences still decode")
    func malformedFolderSortsKeepTheRest() throws {
        let prefs = try CoreModelsFixture.userPreferencesFolderSortsMalformed.decode(UserPreferences.self)
        #expect(prefs.folderSorts == nil)
        #expect(prefs.shouldShowHiddenFiles == true)
        #expect(prefs.shouldShowThumbnails == false)
    }

    @Test("adopting a fetch keeps this session's folder sorts only when the server sent none")
    func adoptKeepsFolderSortsTheServerDoesNotKnow() {
        let sort = FolderSort(field: "size", isAscending: false)
        var current = UserPreferences()
        current.setFolderSort(sort, for: TestPath.documentsWork)

        var fromOldServer = current
        fromOldServer.adopt(UserPreferences(shouldShowHiddenFiles: true))
        #expect(fromOldServer.shouldShowHiddenFiles)
        #expect(fromOldServer.folderSort(for: TestPath.documentsWork) == sort)

        var fromNewServer = current
        fromNewServer.adopt(UserPreferences(folderSorts: [:]))
        #expect(fromNewServer.folderSorts == [:])
    }

    @Test("a fetch that left before a save keeps the saved sort, a later change from the web replaces it")
    func adoptKeepsTheNewestStampedSort() {
        let saved = FolderSort(field: "size", isAscending: false, updatedAt: MockDate.milliseconds + 1)
        let older = FolderSort(field: "name", isAscending: true, updatedAt: MockDate.milliseconds)
        let newer = FolderSort(field: "kind", isAscending: true, updatedAt: MockDate.milliseconds + 2)
        var current = UserPreferences()
        current.setFolderSort(saved, for: TestPath.documentsWork)

        var afterStaleFetch = current
        afterStaleFetch.adopt(UserPreferences(folderSorts: [TestPath.documentsWork: older]))
        #expect(afterStaleFetch.folderSort(for: TestPath.documentsWork) == saved)

        var afterFetchMissingIt = current
        afterFetchMissingIt.adopt(UserPreferences(folderSorts: [:]))
        #expect(afterFetchMissingIt.folderSort(for: TestPath.documentsWork) == saved)

        var afterWebChange = current
        afterWebChange.adopt(UserPreferences(folderSorts: [TestPath.documentsWork: newer]))
        #expect(afterWebChange.folderSort(for: TestPath.documentsWork) == newer)
    }

    @Test("share expiration resolves to a calendar date, respecting the unit")
    func shareExpirationResolvesToADate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let now = MockDate.date // 2023-11-14T22:13:20Z, so one month is November's 30 days

        let inThreeDays = UserPreferences.ShareExpiration(value: 3, unit: .days).expirationDate(
            from: now,
            calendar: calendar
        )
        #expect(inThreeDays == now.addingTimeInterval(3 * 86_400))

        let inTwoWeeks = UserPreferences.ShareExpiration(value: 2, unit: .weeks).expirationDate(
            from: now,
            calendar: calendar
        )
        #expect(inTwoWeeks == now.addingTimeInterval(14 * 86_400))

        let inOneMonth = UserPreferences.ShareExpiration(value: 1, unit: .months).expirationDate(
            from: now,
            calendar: calendar
        )
        #expect(inOneMonth == now.addingTimeInterval(30 * 86_400)) // November has 30 days

        #expect(UserPreferences.ShareExpiration(value: 0, unit: .days)
            .expirationDate(from: now, calendar: calendar) == nil)
    }
}
