import CoreModels
import Dependencies
@testable import FilesClient
import Foundation
import NetworkClient
import Testing
import TestUtils

/// Folder size reads and rescans through `FilesClient.live` against a stubbed `URLSession`.
extension FilesClientLiveTests {
    struct FilesClientFolderSizeTests: FilesClientLiveHarness {
        @Test
        func batchPostsThePathsAndKeysTheAnswerByTheRequestedPath() async throws {
            try prepare(statusCode: 200, fixture: .folderSizeBatch)

            let sizes = try await makeClient().folderSizes(serverURL, ["Docs", "Photos"])

            try expectRequest(.post, "/api/folder-size/batch")
            try expectJSONBody(["paths": ["Docs", "Photos"]])
            #expect(sizes["Docs"]?.sizeBytes == 4096)
            #expect(sizes["Photos"]?.hasSize == false)
        }

        @Test
        func refreshPostsTheFolderPathAndDecodesTheAcceptedEntry() async throws {
            try prepare(statusCode: 202, fixture: .folderSizeRefreshAccepted)

            let entry = try await makeClient().refreshFolderSize(serverURL, "Work/Docs")

            try expectRequest(.post, "/api/folder-size/refresh/Work/Docs")
            expectNoBody()
            #expect(entry.dirty)
            #expect(entry.sizeBytes == 4096)
        }

        @Test
        func aRefusedRefreshSurfacesTheServerMessage() async throws {
            try prepare(statusCode: 400, fixture: .folderSizeErrorExcluded)

            let client = makeClient()
            await #expect(throws: FilesClientError.self) {
                _ = try await client.refreshFolderSize(serverURL, "Cache")
            }
        }
    }
}
