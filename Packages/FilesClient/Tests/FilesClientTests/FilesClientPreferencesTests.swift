import CoreModels
import Dependencies
@testable import FilesClient
import Foundation
import NetworkClient
import Testing
import TestUtils

/// User preferences and admin system settings through `FilesClient.live` against a stubbed `URLSession`. Nested in `FilesClientLiveTests` so it inherits `.serialized`: every live client suite shares
/// `StubURLProtocol`'s statics.
extension FilesClientLiveTests {
    @Suite
    struct FilesClientPreferencesTests: FilesClientLiveHarness {
        @Test
        func fetchPreferencesFallsBackToDefaultsWhenUserKeyIsMissing() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.preferencesEmptyBranding.data())
            let preferences = try await makeClient().fetchPreferences(serverURL)
            #expect(preferences == UserPreferences())
        }

        @Test
        func fetchPreferencesFallsBackPerFieldWhenOnlyOneKeyIsPresent() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.preferencesShowHiddenFiles.data())
            let preferences = try await makeClient().fetchPreferences(serverURL)
            #expect(preferences == UserPreferences(showHiddenFiles: true, showThumbnails: true))
        }

        @Test
        func updatePreferenceEncodesTheKeyAndValueInThePATCHBody() async throws {
            stub(statusCode: 200, body: Data())
            StubURLProtocol.capturedRequest = nil
            try await makeClient().updatePreference(serverURL, .showHiddenFiles, true)
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == "PATCH")
            let body = try #require(StubURLProtocol.capturedRequestBody)
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: [String: Bool]])
            #expect(json["user"]?["showHiddenFiles"] == true)
        }

        @Test
        func fetchSystemSettingsExtractsThumbnailsAndAccessRules() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.systemSettingsThumbnailsAndAccessRules.data())

            let settings = try await makeClient().fetchSystemSettings(serverURL)

            #expect(settings.thumbnails?.size == 300)
            #expect(settings.thumbnails?.quality == 80)
            #expect(settings.accessRules.count == 1)
            #expect(settings.accessRules[0].permission == .readOnly)
            #expect(StubURLProtocol.capturedRequest?.url?.path == "/api/settings")
        }

        @Test
        func updateThumbnailSettingsPatchesTheThumbnailsObjectAndDecodesTheEcho() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.systemSettingsThumbnailsDisabledEcho.data())
            StubURLProtocol.capturedRequest = nil

            let echoed = try await makeClient().updateThumbnailSettings(
                serverURL, ThumbnailSettings(isEnabled: false, size: 128, quality: 50, concurrency: 2)
            )

            #expect(echoed.isEnabled == false)
            #expect(echoed.size == 128)
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == "PATCH")
            let body = try #require(StubURLProtocol.capturedRequestBody)
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: [String: Int]])
            #expect(json["thumbnails"]?["size"] == 128)
            #expect(json["thumbnails"]?["quality"] == 50)
        }

        @Test
        func updateAccessRulesSendsTheWholeArrayUnderAccessRules() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.systemSettingsHiddenAccessRuleEcho.data())
            StubURLProtocol.capturedRequest = nil

            let rules = [AccessRule(id: "local1", path: "Docs", isRecursive: false, permission: .hidden)]
            let echoed = try await makeClient().updateAccessRules(serverURL, rules)

            #expect(echoed == [AccessRule(id: "srv1", path: "Docs", isRecursive: false, permission: .hidden)])
            let body = try #require(StubURLProtocol.capturedRequestBody)
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            let access = try #require(json["access"] as? [String: Any])
            let sent = try #require(access["rules"] as? [[String: Any]])
            #expect(sent.count == 1)
            #expect(sent[0]["permissions"] as? String == "hidden")
            #expect(sent[0]["recursive"] as? Bool == false)
        }

        @Test
        func aNonAdminSettingsPatchSurfacesThe403Message() async throws {
            stub(statusCode: 403, body: try FilesClientFixture.systemSettingsErrorAdminRequired.data())
            await #expect(throws: FilesClientError.forbidden(message: "Admin access required for system settings.")) {
                _ = try await makeClient().updateAccessRules(serverURL, [])
            }
        }
    }
}
