import CoreModels
import Dependencies
@testable import FilesClient
import Foundation
import NetworkClient
import Testing

/// `updateSystemSettings` through `FilesClient.live` against a stubbed `URLSession`. Nested in
/// `FilesClientLiveTests` so it inherits `.serialized`: both share `StubURLProtocol`'s statics.
extension FilesClientLiveTests {
    @Suite("System settings patch")
    struct SystemSettingsPatchRoutes {
        private let serverURL = URL(string: "https://example.com")!

        private func makeClient() -> FilesClient {
            .live(
                networkClient: .live(protocolClasses: [StubURLProtocol.self]),
                directoryCacheStore: .testValue
            )
        }

        private func stub(statusCode: Int, body: String = "") {
            StubURLProtocol.failure = nil
            StubURLProtocol.stub = .init(statusCode: statusCode, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
        }

        @Test
        func patchSendsOnlyTheSectionsSetAndDecodesTheEcho() async throws {
            stub(statusCode: 200, body: #"{"searchIndex":{"enabled":true,"excludedPaths":["a"],"environmentExcludedPaths":[]}}"#)

            let echoed = try await makeClient().updateSystemSettings(serverURL, SystemSettingsPatch(searchIndex: .init(enabled: true)))

            #expect(echoed.searchIndex?.isEnabled == true)
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == "PATCH")
            #expect(request.url?.path == "/api/settings")
            let body = try #require(StubURLProtocol.capturedRequestBody)
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: [String: Bool]])
            #expect(json == ["searchIndex": ["enabled": true]])
        }

        @Test
        func aNonAdminPatchSurfacesTheServersMessage() async throws {
            stub(statusCode: 403, body: #"{"error":"Admin access required."}"#)

            await #expect(throws: FilesClientError.self) {
                _ = try await makeClient().updateSystemSettings(serverURL, SystemSettingsPatch(ffmpeg: .init(ffmpegPath: "/a")))
            }
        }

        @Test
        func theUploadsEchoCarriesTheSavedChunkSize() async throws {
            stub(statusCode: 200, body: #"{"uploads":{"chunkedEnabled":true,"chunkedAutoFallback":false,"chunkSizeBytes":33554432}}"#)

            let echoed = try await makeClient().updateSystemSettings(
                serverURL, SystemSettingsPatch(uploads: UploadSettings(isChunkedEnabled: true, chunkSizeBytes: 33_554_432))
            )

            #expect(echoed.uploads?.chunkSizeBytes == 33_554_432)
            #expect(echoed.uploads?.isChunkedEnabled == true)
        }
    }
}

extension FilesClientLiveTests {
    @Suite("Activity log routes")
    struct ActivityRoutes {
        private let serverURL = URL(string: "https://example.com")!

        private func makeClient() -> FilesClient {
            .live(
                networkClient: .live(protocolClasses: [StubURLProtocol.self]),
                directoryCacheStore: .testValue
            )
        }

        private func stub(statusCode: Int, body: String = "") {
            StubURLProtocol.failure = nil
            StubURLProtocol.stub = .init(statusCode: statusCode, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
        }

        @Test
        func fetchSendsOnlyTheFiltersThatAreSetAndEncodesTheSearch() async throws {
            stub(statusCode: 200, body: #"{"events":[],"nextBefore":null,"enabled":true,"actions":[]}"#)

            _ = try await makeClient().fetchActivity(
                serverURL, ActivityFilter(action: "file.delete", outcome: .refused, query: " a+b&c "), "2026-11-11T07:10:00.000Z"
            )

            let url = try #require(StubURLProtocol.capturedRequest?.url)
            #expect(url.path == "/api/activity")
            let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            #expect(items["action"] == "file.delete")
            #expect(items["outcome"] == "refused")
            #expect(items["q"] == "a+b&c")
            #expect(items["before"] == "2026-11-11T07:10:00.000Z")
            #expect(items["limit"] == "100")
            #expect(url.absoluteString.contains("q=a%2Bb%26c"))
        }

        @Test
        func anEmptyFilterSendsOnlyTheLimit() async throws {
            stub(statusCode: 200, body: #"{"events":[],"nextBefore":null,"enabled":false,"actions":[]}"#)

            _ = try await makeClient().fetchActivity(serverURL, ActivityFilter(), nil)

            let query = try #require(StubURLProtocol.capturedRequest?.url?.query)
            #expect(query == "limit=100")
        }

        @Test
        func aNonAdminFetchFails() async throws {
            stub(statusCode: 403, body: #"{"error":"Admin access required."}"#)

            await #expect(throws: FilesClientError.self) {
                _ = try await makeClient().fetchActivity(serverURL, ActivityFilter(), nil)
            }
        }

        @Test
        func clearIssuesADeleteToTheActivityRoute() async throws {
            stub(statusCode: 200, body: #"{"removed":12}"#)

            try await makeClient().clearActivity(serverURL)

            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == "DELETE")
            #expect(request.url?.path == "/api/activity")
        }

        @Test
        func clearSurfacesAFailure() async throws {
            stub(statusCode: 500, body: "")

            await #expect(throws: FilesClientError.self) {
                try await makeClient().clearActivity(serverURL)
            }
        }
    }
}

extension FilesClientLiveTests {
    @Suite("Trash admin routes")
    struct TrashAdminRoutes {
        private let serverURL = URL(string: "https://example.com")!

        private func makeClient() -> FilesClient {
            .live(
                networkClient: .live(protocolClasses: [StubURLProtocol.self]),
                directoryCacheStore: .testValue
            )
        }

        private func stub(statusCode: Int, body: String = "") {
            StubURLProtocol.failure = nil
            StubURLProtocol.stub = .init(statusCode: statusCode, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
        }

        @Test
        func zonesAreReadFromTheZonesRoute() async throws {
            stub(statusCode: 200, body: #"{"zones":[{"id":"z1","kind":"volume","name":"files","available":true,"usedBytes":10}]}"#)

            let zones = try await makeClient().fetchTrashZones(serverURL)

            #expect(zones.map(\.id) == ["z1"])
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/api/trash/zones")
        }

        @Test
        func aNonAdminZonesRequestFails() async throws {
            stub(statusCode: 403, body: #"{"error":"Admin access required."}"#)

            await #expect(throws: FilesClientError.self) {
                _ = try await makeClient().fetchTrashZones(serverURL)
            }
        }

        @Test
        func verifyPostsAndReadsEachZonesViolations() async throws {
            stub(statusCode: 200, body: #"{"zones":[{"zoneId":"z1","violations":[{"invariant":"I1","itemId":"i1","detail":"content missing"},{"invariant":"I4","itemId":"i2","detail":"left in state x"}]},{"zoneId":"z2","violations":[]}]}"#)

            let results = try await makeClient().verifyTrash(serverURL)

            #expect(results.map(\.violationCount) == [2, 0])
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/trash/verify")
        }

        @Test
        func maintenancePostsToTheMaintenanceRoute() async throws {
            stub(statusCode: 200, body: #"{"zones":[]}"#)

            try await makeClient().runTrashMaintenance(serverURL)

            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/trash/maintenance")
        }

        @Test
        func maintenanceSurfacesAFailure() async throws {
            stub(statusCode: 500)

            await #expect(throws: FilesClientError.self) {
                try await makeClient().runTrashMaintenance(serverURL)
            }
        }

        @Test
        func theTrashAndVersionsSectionsGoOutInOnePatch() async throws {
            stub(statusCode: 200, body: #"{"trash":{"enabled":true,"retentionDays":7,"maxPercent":10,"maxBytes":null},"versions":{"enabled":false}}"#)

            let echoed = try await makeClient().updateSystemSettings(
                serverURL,
                SystemSettingsPatch(trash: TrashSettings(retentionDays: 7), versions: VersionsSettings(isEnabled: false))
            )

            #expect(echoed.trash?.retentionDays == 7)
            #expect(echoed.versions?.isEnabled == false)
            let body = try #require(StubURLProtocol.capturedRequestBody)
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(Set(json.keys) == ["trash", "versions"])
            let trash = try #require(json["trash"] as? [String: Any])
            #expect(trash["maxBytes"] is NSNull)
        }
    }
}

extension FilesClientLiveTests {
    @Suite("Versions admin routes")
    struct VersionsAdminRoutes {
        private let serverURL = URL(string: "https://example.com")!

        private func makeClient() -> FilesClient {
            .live(
                networkClient: .live(protocolClasses: [StubURLProtocol.self]),
                directoryCacheStore: .testValue
            )
        }

        private func stub(statusCode: Int, body: String = "") {
            StubURLProtocol.failure = nil
            StubURLProtocol.stub = .init(statusCode: statusCode, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
        }

        private func queryItems() throws -> [String: String] {
            let url = try #require(StubURLProtocol.capturedRequest?.url)
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        }

        @Test
        func theListSendsTheFiltersTheSortAndThePage() async throws {
            stub(statusCode: 200, body: #"{"files":[],"total":0,"totalBytes":0,"totalVersions":0,"limit":25,"offset":50,"zones":[]}"#)

            _ = try await makeClient().fetchVersionedFiles(
                serverURL,
                VersionedFilesFilter(query: " a b&c ", zoneID: "z1", state: .orphaned, sort: .newest),
                50,
                25
            )

            #expect(StubURLProtocol.capturedRequest?.url?.path == "/api/versions/admin/files")
            let items = try queryItems()
            #expect(items["q"] == "a b&c")
            #expect(items["zone"] == "z1")
            #expect(items["state"] == "orphaned")
            #expect(items["sort"] == "newest")
            #expect(items["limit"] == "25")
            #expect(items["offset"] == "50")
        }

        @Test
        func theFirstPageSendsNoOffsetAndNoEmptyFilters() async throws {
            stub(statusCode: 200, body: #"{"files":[]}"#)

            _ = try await makeClient().fetchVersionedFiles(serverURL, VersionedFilesFilter(), 0, 25)

            let items = try queryItems()
            #expect(items["offset"] == nil)
            #expect(items["q"] == nil)
            #expect(items["zone"] == nil)
            #expect(items["state"] == nil)
            #expect(items["sort"] == "bytes")
        }

        @Test
        func aNonAdminListFails() async throws {
            stub(statusCode: 403, body: #"{"error":"Admin access required."}"#)

            await #expect(throws: FilesClientError.self) {
                _ = try await makeClient().fetchVersionedFiles(serverURL, VersionedFilesFilter(), 0, 25)
            }
        }

        @Test
        func oneHistoryIsReadByItsID() async throws {
            stub(statusCode: 200, body: #"{"versions":[],"totalBytes":0}"#)

            _ = try await makeClient().fetchVersionedFile(serverURL, "f1")

            #expect(StubURLProtocol.capturedRequest?.url?.path == "/api/versions/admin/files/f1")
            #expect(StubURLProtocol.capturedRequest?.httpMethod == "GET")
        }

        @Test
        func deletingNamedVersionsPostsTheirIDs() async throws {
            stub(statusCode: 200, body: #"{"items":[],"deleted":2,"remaining":1}"#)

            let outcome = try await makeClient().deleteVersionsOfFile(serverURL, "f1", ["v1", "v2"])

            #expect(outcome == VersionsDeletion(deleted: 2, remaining: 1))
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/versions/admin/files/f1/delete")
            let body = try #require(StubURLProtocol.capturedRequestBody)
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(json["ids"] as? [String] == ["v1", "v2"])
            #expect(json["all"] == nil)
        }

        @Test
        func deletingEveryVersionPostsAllTrueAndNoIDs() async throws {
            stub(statusCode: 200, body: #"{"items":[],"deleted":3,"remaining":0}"#)

            _ = try await makeClient().deleteVersionsOfFile(serverURL, "f1", nil)

            let body = try #require(StubURLProtocol.capturedRequestBody)
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(json["all"] as? Bool == true)
            #expect(json["ids"] == nil)
        }

        @Test
        func aFailedDeletionSurfacesTheMessage() async throws {
            stub(statusCode: 404, body: #"{"error":"This history does not exist."}"#)

            await #expect(throws: FilesClientError.self) {
                _ = try await makeClient().deleteVersionsOfFile(serverURL, "gone", nil)
            }
        }

        @Test
        func anIDWithASlashStaysOneSegmentOfTheRoute() async throws {
            stub(statusCode: 200, body: #"{"versions":[],"totalBytes":0}"#)

            _ = try await makeClient().fetchVersionedFile(serverURL, "a/../b")

            let url = try #require(StubURLProtocol.capturedRequest?.url?.absoluteString)
            #expect(url == "https://example.com/api/versions/admin/files/a%2F..%2Fb")
        }
    }
}
