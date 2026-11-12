import CoreModels
import Dependencies
@testable import FilesClient
import Foundation
import NetworkClient
import Testing
import TestUtils

/// File version history routes through `FilesClient.live` against a stubbed `URLSession`. Nested in `FilesClientLiveTests` so it inherits `.serialized`: every live client suite shares
/// `StubURLProtocol`'s statics.
extension FilesClientLiveTests {
    @Suite
    struct FilesClientVersionsTests: FilesClientLiveHarness {
        func capturedJSON() throws -> [String: Any] {
            let body = try #require(StubURLProtocol.capturedRequestBody)
            return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        }

        @Test
        func fetchVersionsSendsThePathAsAQueryAndDecodesTheHistory() async throws {
            // Shape of `listVersions` in backend/src/services/versions/index.js.
            stub(statusCode: 200, body: try FilesClientFixture.versionsListNotesTwoVersions.data())
            StubURLProtocol.capturedRequest = nil
            let history = try await makeClient().fetchVersions(serverURL, "Docs/notes.txt")
            let requestURL = try #require(StubURLProtocol.capturedRequest?.url)
            #expect(requestURL.path == "/api/versions")
            #expect(URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "path", value: "Docs/notes.txt")])
            #expect(history.isEnabled)
            #expect(history.versions.map(\.id) == ["v2", "v1"])
            #expect(history.versions[0].author?.label == "Phillip")
            #expect(history.versions[1].label == "Draft")
            #expect(history.versions[1].isAvailable == false)
            #expect(!history.rights.canRestore)
        }

        @Test
        func restoreVersionPostsThePathToTheVersionRoute() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.versionsRestoreResult.data())
            StubURLProtocol.capturedRequest = nil
            try await makeClient().restoreVersion(serverURL, "Docs/notes.txt", "v1")
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.url?.path == "/api/versions/v1/restore")
            #expect(request.httpMethod == "POST")
        }

        @Test
        func copyVersionPostsTheDestinationAndReturnsTheNewPath() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.versionsSaveAsCopyResult.data())
            let newPath = try await makeClient().copyVersion(serverURL, "Docs/notes.txt", "v1", "Docs")
            #expect(newPath == "Docs/notes (v1).txt")
            #expect(StubURLProtocol.capturedRequest?.url?.path == "/api/versions/v1/copy")
            let json = try capturedJSON()
            #expect(json["path"] as? String == "Docs/notes.txt")
            #expect(json["destination"] as? String == "Docs")
        }

        @Test
        func updateVersionLeavesOutTheFieldsNotBeingChanged() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.versionsVersionPinned.data())
            let updated = try await makeClient().updateVersion(serverURL, "Docs/notes.txt", "v1", nil, true)
            #expect(updated.isPinned)
            #expect(StubURLProtocol.capturedRequest?.httpMethod == "PATCH")
            let json = try capturedJSON()
            #expect(json["pinned"] as? Bool == true)
            #expect(json["label"] == nil)
        }

        @Test
        func deleteAllVersionsSendsAllWithoutIDs() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.versionsDeletionResult.data())
            try await makeClient().deleteVersions(serverURL, "Docs/notes.txt", [], true)
            #expect(StubURLProtocol.capturedRequest?.url?.path == "/api/versions/delete")
            let json = try capturedJSON()
            #expect(json["all"] as? Bool == true)
            #expect(json["ids"] == nil)
        }

        @Test
        func downloadVersionReadsTheContentRouteIntoTheDestination() async throws {
            stub(statusCode: 200, body: Data("old text".utf8))
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("\(TestID.name()).txt")
            defer { try? FileManager.default.removeItem(at: destination) }
            try await makeClient().downloadVersion(serverURL, "Docs/notes.txt", "v1", destination)
            let url = try #require(StubURLProtocol.capturedRequest?.url)
            #expect(url.path == "/api/versions/v1/content")
            #expect(url.query?.contains("path=Docs/notes.txt") == true)
            #expect(try String(contentsOf: destination, encoding: .utf8) == "old text")
        }
    }
}
