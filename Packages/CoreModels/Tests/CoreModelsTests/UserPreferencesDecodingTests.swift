import Foundation
import Testing
@testable import CoreModels

@Suite("UserPreferences decoding")
struct UserPreferencesDecodingTests {
    @Test("happy path: explicit values override the defaults")
    func decodesExplicitValues() throws {
        let json = #"{"showHiddenFiles": true, "showThumbnails": false}"#
        let prefs = try JSONDecoder().decode(UserPreferences.self, from: Data(json.utf8))
        #expect(prefs.showHiddenFiles == true)
        #expect(prefs.showThumbnails == false)
    }

    @Test("edge case: a brand-new user with no settings row decodes to client defaults")
    func decodesEmptyObjectToDefaults() throws {
        let json = #"{}"#
        let prefs = try JSONDecoder().decode(UserPreferences.self, from: Data(json.utf8))
        #expect(prefs.showHiddenFiles == false)
        #expect(prefs.showThumbnails == true)
    }

    @Test("edge case: only one key present, the other still falls back to default")
    func decodesPartialObject() throws {
        let json = #"{"showHiddenFiles": true}"#
        let prefs = try JSONDecoder().decode(UserPreferences.self, from: Data(json.utf8))
        #expect(prefs.showHiddenFiles == true)
        #expect(prefs.showThumbnails == true)
    }
}
