@testable import CoreModels
import Foundation
import Testing
import TestUtils

@Suite("UserPreferences decoding")
struct UserPreferencesDecodingTests {
    @Test("happy path: explicit values override the defaults")
    func decodesExplicitValues() throws {
        let prefs = try CoreModelsFixture.userPreferencesExplicitValues.decode(UserPreferences.self)
        #expect(prefs.showHiddenFiles == true)
        #expect(prefs.showThumbnails == false)
    }

    @Test("edge case: a brand-new user with no settings row decodes to client defaults")
    func decodesEmptyObjectToDefaults() throws {
        let prefs = try CoreModelsFixture.userPreferencesEmptyObject.decode(UserPreferences.self)
        #expect(prefs.showHiddenFiles == false)
        #expect(prefs.showThumbnails == true)
    }

    @Test("edge case: only one key present, the other still falls back to default")
    func decodesPartialObject() throws {
        let prefs = try CoreModelsFixture.userPreferencesPartialObject.decode(UserPreferences.self)
        #expect(prefs.showHiddenFiles == true)
        #expect(prefs.showThumbnails == true)
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

    @Test("share expiration resolves to a calendar date, respecting the unit")
    func shareExpirationResolvesToADate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let now = MockDate.date // 2023-11-14T22:13:20Z, so one month is November's 30 days

        let inThreeDays = UserPreferences.ShareExpiration(value: 3, unit: .days).expirationDate(from: now, calendar: calendar)
        #expect(inThreeDays == now.addingTimeInterval(3 * 86_400))

        let inTwoWeeks = UserPreferences.ShareExpiration(value: 2, unit: .weeks).expirationDate(from: now, calendar: calendar)
        #expect(inTwoWeeks == now.addingTimeInterval(14 * 86_400))

        let inOneMonth = UserPreferences.ShareExpiration(value: 1, unit: .months).expirationDate(from: now, calendar: calendar)
        #expect(inOneMonth == now.addingTimeInterval(30 * 86_400)) // November has 30 days

        #expect(UserPreferences.ShareExpiration(value: 0, unit: .days).expirationDate(from: now, calendar: calendar) == nil)
    }
}
