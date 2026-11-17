import CoreModels
import Dependencies
@testable import FilesClient
import Foundation
import NetworkClient
import Testing
import TestUtils

/// The person's trash routes through `FilesClient.live` against a stubbed `URLSession`. Nested in
/// `FilesClientLiveTests` so it inherits `.serialized`: both share `StubURLProtocol`'s statics.
extension FilesClientLiveTests {
    @Suite("Trash routes")
    struct TrashRoutes: FilesClientLiveHarness {
        private enum Constants {
            static let itemID = "t1"
            static let slashedID = "a/b"
            static let destination = "Files/Restored"
            static let entryPath = "2026/beach.jpg"
        }

        @Test
        func listingIsReadFromTheTrashRoute() async throws {
            try prepare(statusCode: 200, fixture: .trashListing)

            let listing = try await makeClient().fetchTrash(serverURL)

            #expect(listing.items.map(\.id) == ["t1", "t2", "t3"])
            try expectRequest(.get, "/api/trash")
        }

        @Test
        func entriesEncodeTheIdAsOneSegmentAndThePathAsAQuery() async throws {
            try prepare(statusCode: 200, fixture: .trashFolderEntries)

            let listing = try await makeClient().fetchTrashEntries(serverURL, Constants.slashedID, "2026/a&b")

            #expect(listing.entries.count == 3)
            let url = try #require(StubURLProtocol.capturedRequest?.url?.absoluteString)
            #expect(url.hasSuffix("/api/trash/items/a%2Fb/entries?path=2026%2Fa%26b"))
        }

        @Test
        func textIsReadAsJSON() async throws {
            try prepare(statusCode: 200, fixture: .trashTextNotes)

            let text = try await makeClient().fetchTrashText(serverURL, Constants.itemID, "")

            #expect(text == TrashText(name: "notes.txt", content: "hello"))
            let url = try #require(StubURLProtocol.capturedRequest?.url?.absoluteString)
            #expect(url.hasSuffix("/api/trash/items/t1/text?path="))
        }

        @Test
        func restoreAlwaysSendsTheShareChoice() async throws {
            try prepare(statusCode: 200, fixture: .trashRestoreRenamed)

            let result = try await makeClient().restoreTrash(serverURL, .items([Constants.itemID]), nil, .drop) { _ in }

            #expect(result.items.first?.isRenamed == true)
            try expectRequest(.post, "/api/trash/restore")
            try expectJSONBody(["ids": [Constants.itemID], "shares": "drop"])
        }

        @Test
        func entriesRestoreToTheItemsRoute() async throws {
            try prepare(statusCode: 200, fixture: .trashRestoreRenamed)

            _ = try await makeClient().restoreTrash(
                serverURL,
                .entries(itemID: Constants.itemID, paths: [Constants.entryPath]),
                nil,
                .restore
            ) { _ in }

            try expectRequest(.post, "/api/trash/items/t1/restore")
            try expectJSONBody(["paths": [Constants.entryPath], "shares": "restore"])
        }

        @Test
        func restoreIntoAFolderReadsTheStreamedResult() async throws {
            try prepare(statusCode: 200, fixture: .trashRestoreToDone)
            let fractions = LockIsolated<[Double]>([])

            let result = try await makeClient().restoreTrash(
                serverURL,
                .items([Constants.itemID]),
                Constants.destination,
                .restore
            ) { fraction in fractions.withValue { $0.append(fraction) } }

            #expect(fractions.value == [0.5, 1])
            #expect(result.succeeded.count == 1)
            #expect(result.items.first?.path == Constants.destination)
            try expectRequest(.post, "/api/trash/restore-to")
            try expectJSONBody(["ids": [Constants.itemID], "destination": Constants.destination, "shares": "restore"])
        }

        @Test
        func entriesRestoreIntoAFolderUseTheItemsStreamedRoute() async throws {
            try prepare(statusCode: 200, fixture: .trashRestoreToDone)

            _ = try await makeClient().restoreTrash(
                serverURL,
                .entries(itemID: Constants.itemID, paths: [Constants.entryPath]),
                Constants.destination,
                .drop
            ) { _ in }

            try expectRequest(.post, "/api/trash/items/t1/restore-to")
        }

        @Test
        func aStreamedErrorBecomesTheServersMessage() async throws {
            try prepare(statusCode: 200, fixture: .trashRestoreToError)

            await #expect(throws: FilesClientError.serverMessage(statusCode: 500, message: "The disk is full.")) {
                _ = try await makeClient().restoreTrash(
                    serverURL,
                    .items([Constants.itemID]),
                    Constants.destination,
                    .drop
                ) { _ in }
            }
        }

        @Test
        func aRefusalBeforeTheStreamCarriesItsMessage() async throws {
            try prepare(statusCode: 403, fixture: .commonErrorAdminRequired)

            await #expect(throws: FilesClientError.self) {
                _ = try await makeClient().restoreTrash(
                    serverURL,
                    .items([Constants.itemID]),
                    Constants.destination,
                    .drop
                ) { _ in }
            }
        }

        @Test
        func moreIdsThanTheServerTakesGoInBatches() async throws {
            try prepare(statusCode: 200, fixture: .trashRestoreRenamed)
            let ids = (0 ... FilesService.trashBatchLimit).map(String.init)

            let result = try await makeClient().restoreTrash(serverURL, .items(ids), nil, .drop) { _ in }

            #expect(StubURLProtocol.requests.count == 2)
            #expect(result.items.count == 2)
            try expectJSONBody(["ids": [String(FilesService.trashBatchLimit)], "shares": "drop"])
        }

        @Test
        func purgeSendsForgetOnlyWhenAsked() async throws {
            try prepare(statusCode: 200, fixture: .trashRestoreRenamed)

            _ = try await makeClient().purgeTrash(serverURL, [Constants.itemID], false)
            try expectRequest(.post, "/api/trash/delete")
            try expectJSONBody(["ids": [Constants.itemID]])

            _ = try await makeClient().purgeTrash(serverURL, [Constants.itemID], true)
            try expectJSONBody(["ids": [Constants.itemID], "forgetUnavailable": true])
        }

        @Test
        func emptyPostsAndReadsTheSummary() async throws {
            try prepare(statusCode: 200, fixture: .trashEmptySummary)

            let summary = try await makeClient().emptyTrash(serverURL)

            #expect(summary == TrashEmptySummary(purged: 4, unavailable: 1, failed: 2))
            try expectRequest(.post, "/api/trash/empty")
            expectNoBody()
        }

        @Test
        func anExpiredSessionIsReported() async throws {
            prepareEmpty(statusCode: 401)

            await #expect(throws: FilesClientError.sessionExpired) {
                _ = try await makeClient().fetchTrash(serverURL)
            }
        }
    }
}

@Suite("Trash batches")
struct TrashBatchTests {
    @Test
    func batchesSplitAtTheServerLimitAndKeepTheFolder() {
        let paths = (0 ..< 2001).map(String.init)

        let batches = FilesService.trashBatches(.entries(itemID: "t1", paths: paths))

        #expect(batches.map(\.count) == [1000, 1000, 1])
        #expect(batches.allSatisfy {
            if case .entries("t1", _) = $0 {
                true
            } else {
                false
            }
        })
        #expect(FilesService.trashBatches(.items([])).isEmpty)
    }
}
