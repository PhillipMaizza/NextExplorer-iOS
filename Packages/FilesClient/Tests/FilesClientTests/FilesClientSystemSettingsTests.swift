import CoreModels
import Dependencies
@testable import FilesClient
import Foundation
import NetworkClient
import Testing
import TestUtils

/// `updateSystemSettings` through `FilesClient.live` against a stubbed `URLSession`. Nested in
/// `FilesClientLiveTests` so it inherits `.serialized`: both share `StubURLProtocol`'s statics.
extension FilesClientLiveTests {
    @Suite("System settings patch")
    struct SystemSettingsPatchRoutes {
        private let serverURL = URL(string: TestHost.exampleURLString)!

        private func makeClient() -> FilesClient {
            .live(
                networkClient: .live(protocolClasses: [StubURLProtocol.self]),
                directoryCacheStore: .testValue
            )
        }

        private func stub(statusCode: Int, body: String = "") {
            StubURLProtocol.failure = nil
            StubURLProtocol.stub = .init(
                statusCode: statusCode,
                headers: [HTTPHeaderField.contentType: MIMEType.json],
                body: Data(body.utf8)
            )
        }

        @Test
        func patchSendsOnlyTheSectionsSetAndDecodesTheEcho() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.systemSettingsSearchIndex.string())

            let echoed = try await makeClient().updateSystemSettings(
                serverURL,
                SystemSettingsPatch(searchIndex: .init(enabled: true))
            )

            #expect(echoed.searchIndex?.isEnabled == true)
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == HTTPMethod.patch.rawValue)
            #expect(request.url?.path == "/api/settings")
            let body = try #require(StubURLProtocol.capturedRequestBody)
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: [String: Bool]])
            #expect(json == ["searchIndex": ["enabled": true]])
        }

        @Test
        func aNonAdminPatchSurfacesTheServersMessage() async throws {
            try stub(statusCode: 403, body: FilesClientFixture.commonErrorAdminRequired.string())

            await #expect(throws: FilesClientError.self) {
                _ = try await makeClient().updateSystemSettings(
                    serverURL,
                    SystemSettingsPatch(ffmpeg: .init(ffmpegPath: "/a"))
                )
            }
        }

        @Test
        func theUploadsEchoCarriesTheSavedChunkSize() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.systemSettingsUploadsChunked.string())

            let echoed = try await makeClient().updateSystemSettings(
                serverURL, SystemSettingsPatch(uploads: UploadSettings(
                    isChunkedEnabled: true,
                    chunkSizeBytes: 33_554_432
                ))
            )

            #expect(echoed.uploads?.chunkSizeBytes == 33_554_432)
            #expect(echoed.uploads?.isChunkedEnabled == true)
        }
    }
}

extension FilesClientLiveTests {
    @Suite("Activity log routes")
    struct ActivityRoutes {
        private let serverURL = URL(string: TestHost.exampleURLString)!

        private func makeClient() -> FilesClient {
            .live(
                networkClient: .live(protocolClasses: [StubURLProtocol.self]),
                directoryCacheStore: .testValue
            )
        }

        private func stub(statusCode: Int, body: String = "") {
            StubURLProtocol.failure = nil
            StubURLProtocol.stub = .init(
                statusCode: statusCode,
                headers: [HTTPHeaderField.contentType: MIMEType.json],
                body: Data(body.utf8)
            )
        }

        @Test
        func fetchSendsOnlyTheFiltersThatAreSetAndEncodesTheSearch() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.activityLogEnabledEmpty.string())

            _ = try await makeClient().fetchActivity(
                serverURL, ActivityFilter(action: "file.delete", outcome: .refused, query: " a+b&c "),
                "2026-11-11T07:10:00.000Z"
            )

            let url = try #require(StubURLProtocol.capturedRequest?.url)
            #expect(url.path == "/api/activity")
            let items =
                Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems ?? []).map { (
                    $0.name,
                    $0.value ?? ""
                ) })
            #expect(items["action"] == "file.delete")
            #expect(items["outcome"] == "refused")
            #expect(items["q"] == "a+b&c")
            #expect(items["before"] == "2026-11-11T07:10:00.000Z")
            #expect(items["limit"] == "100")
            #expect(url.absoluteString.contains("q=a%2Bb%26c"))
        }

        @Test
        func anEmptyFilterSendsOnlyTheLimit() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.activityLogDisabledEmpty.string())

            _ = try await makeClient().fetchActivity(serverURL, ActivityFilter(), nil)

            let query = try #require(StubURLProtocol.capturedRequest?.url?.query)
            #expect(query == "limit=100")
        }

        @Test
        func aNonAdminFetchFails() async throws {
            try stub(statusCode: 403, body: FilesClientFixture.commonErrorAdminRequired.string())

            await #expect(throws: FilesClientError.self) {
                _ = try await makeClient().fetchActivity(serverURL, ActivityFilter(), nil)
            }
        }

        @Test
        func clearIssuesADeleteToTheActivityRoute() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.activityLogClearedTwelve.string())

            try await makeClient().clearActivity(serverURL)

            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == HTTPMethod.delete.rawValue)
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
        private let serverURL = URL(string: TestHost.exampleURLString)!

        private func makeClient() -> FilesClient {
            .live(
                networkClient: .live(protocolClasses: [StubURLProtocol.self]),
                directoryCacheStore: .testValue
            )
        }

        private func stub(statusCode: Int, body: String = "") {
            StubURLProtocol.failure = nil
            StubURLProtocol.stub = .init(
                statusCode: statusCode,
                headers: [HTTPHeaderField.contentType: MIMEType.json],
                body: Data(body.utf8)
            )
        }

        @Test
        func zonesAreReadFromTheZonesRoute() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.trashZonesOneVolume.string())

            let zones = try await makeClient().fetchTrashZones(serverURL)

            #expect(zones.map(\.id) == ["z1"])
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == HTTPMethod.get.rawValue)
            #expect(request.url?.path == "/api/trash/zones")
        }

        @Test
        func aNonAdminZonesRequestFails() async throws {
            try stub(statusCode: 403, body: FilesClientFixture.commonErrorAdminRequired.string())

            await #expect(throws: FilesClientError.self) {
                _ = try await makeClient().fetchTrashZones(serverURL)
            }
        }

        @Test
        func verifyPostsAndReadsEachZonesViolations() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.trashVerificationViolations.string())

            let results = try await makeClient().verifyTrash(serverURL)

            #expect(results.map(\.violationCount) == [2, 0])
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == HTTPMethod.post.rawValue)
            #expect(request.url?.path == "/api/trash/verify")
        }

        @Test
        func maintenancePostsToTheMaintenanceRoute() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.trashZonesEmpty.string())

            try await makeClient().runTrashMaintenance(serverURL)

            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == HTTPMethod.post.rawValue)
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
            try stub(statusCode: 200, body: FilesClientFixture.trashTrashAndVersionsSettings.string())

            let echoed = try await makeClient().updateSystemSettings(
                serverURL,
                SystemSettingsPatch(
                    trash: TrashSettings(retentionDays: 7),
                    versions: VersionsSettings(isEnabled: false)
                )
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
        private let serverURL = URL(string: TestHost.exampleURLString)!

        private func makeClient() -> FilesClient {
            .live(
                networkClient: .live(protocolClasses: [StubURLProtocol.self]),
                directoryCacheStore: .testValue
            )
        }

        private func stub(statusCode: Int, body: String = "") {
            StubURLProtocol.failure = nil
            StubURLProtocol.stub = .init(
                statusCode: statusCode,
                headers: [HTTPHeaderField.contentType: MIMEType.json],
                body: Data(body.utf8)
            )
        }

        private func queryItems() throws -> [String: String] {
            let url = try #require(StubURLProtocol.capturedRequest?.url)
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        }

        @Test
        func theListSendsTheFiltersTheSortAndThePage() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.versionedFilesPageEmpty.string())

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
            try stub(statusCode: 200, body: FilesClientFixture.versionedFilesFilesEmpty.string())

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
            try stub(statusCode: 403, body: FilesClientFixture.commonErrorAdminRequired.string())

            await #expect(throws: FilesClientError.self) {
                _ = try await makeClient().fetchVersionedFiles(serverURL, VersionedFilesFilter(), 0, 25)
            }
        }

        @Test
        func oneHistoryIsReadByItsID() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.versionsEmptyWithTotals.string())

            _ = try await makeClient().fetchVersionedFile(serverURL, "f1")

            #expect(StubURLProtocol.capturedRequest?.url?.path == "/api/versions/admin/files/f1")
            #expect(StubURLProtocol.capturedRequest?.httpMethod == HTTPMethod.get.rawValue)
        }

        @Test
        func deletingNamedVersionsPostsTheirIDs() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.versionsDeletionRemainingOne.string())

            let outcome = try await makeClient().deleteVersionsOfFile(
                serverURL,
                "f1",
                [TestETag.first, TestETag.second]
            )

            #expect(outcome == VersionsDeletion(deleted: 2, remaining: 1))
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == HTTPMethod.post.rawValue)
            #expect(request.url?.path == "/api/versions/admin/files/f1/delete")
            let body = try #require(StubURLProtocol.capturedRequestBody)
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(json["ids"] as? [String] == [TestETag.first, TestETag.second])
            #expect(json["all"] == nil)
        }

        @Test
        func deletingEveryVersionPostsAllTrueAndNoIDs() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.versionsDeletionRemainingZero.string())

            _ = try await makeClient().deleteVersionsOfFile(serverURL, "f1", nil)

            let body = try #require(StubURLProtocol.capturedRequestBody)
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(json["all"] as? Bool == true)
            #expect(json["ids"] == nil)
        }

        @Test
        func aFailedDeletionSurfacesTheMessage() async throws {
            try stub(statusCode: 404, body: FilesClientFixture.versionsErrorHistoryMissing.string())

            await #expect(throws: FilesClientError.self) {
                _ = try await makeClient().deleteVersionsOfFile(serverURL, "gone", nil)
            }
        }

        @Test
        func anIDWithASlashStaysOneSegmentOfTheRoute() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.versionsEmptyWithTotals.string())

            _ = try await makeClient().fetchVersionedFile(serverURL, "a/../b")

            let url = try #require(StubURLProtocol.capturedRequest?.url?.absoluteString)
            #expect(url == "https://example.com/api/versions/admin/files/a%2F..%2Fb")
        }
    }
}
