import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// A mutation that timed out, or that a gateway answered for, may still have finished on the server,
/// so the folder is refetched to show what really happened. Every other failure is believed.
@Suite(.isolatedDependencies)
@MainActor
struct BrowseMutationFailureTests {
    struct AmbiguityCase: Sendable, CustomTestStringConvertible {
        let error: FilesClientError
        let isAmbiguous: Bool
        var testDescription: String {
            "\(error)"
        }
    }

    private nonisolated static let ambiguityCases: [AmbiguityCase] =
        [502, 503, 504, 524].flatMap { status in
            [
                AmbiguityCase(error: .server(statusCode: status), isAmbiguous: true),
                AmbiguityCase(error: .serverMessage(statusCode: status, message: "Gateway"), isAmbiguous: true),
            ]
        }
        + [400, 401, 403, 404, 409, 413, 415, 429, 500, 501].flatMap { status in
            [
                AmbiguityCase(error: .server(statusCode: status), isAmbiguous: false),
                AmbiguityCase(error: .serverMessage(statusCode: status, message: "No"), isAmbiguous: false),
            ]
        }
        + [
            AmbiguityCase(error: .timedOut, isAmbiguous: true),
            AmbiguityCase(error: .offline, isAmbiguous: false),
            AmbiguityCase(error: .sessionExpired, isAmbiguous: false),
            AmbiguityCase(error: .rateLimited, isAmbiguous: false),
            AmbiguityCase(error: .changedOnServer, isAmbiguous: false),
        ]

    private nonisolated static let ambiguousErrors: [FilesClientError] = [
        .timedOut,
        .server(statusCode: 502),
        .server(statusCode: 503),
        .server(statusCode: 504),
        .server(statusCode: 524),
        .serverMessage(statusCode: 504, message: "Gateway Timeout"),
    ]

    private let kept = BrowseFixtures.file(TestFile.aText, in: TestPath.docsLowercase)

    /// The refetch that follows an ambiguous failure: the listing is loaded again and the favorites follow.
    private func receiveRefetch(
        _ store: TestStoreOf<BrowseFeature>, listing: [FileItem], favorites: AsyncGate
    ) async {
        await store.receive(\.itemsResponse.success) {
            $0.phase = .loaded
            $0.items = IdentifiedArray(uniqueElements: listing)
            $0.access = BrowseTestSupport.readOnlyAccess
        }
        if !listing.isEmpty {
            await store.receive(\.offlineAvailabilityComputed)
        }
        favorites.open()
        await store.receive(\.favoritesResponse) {
            $0.hasLoadedFavorites = true
        }
    }

    @Test(
        "A delete that may have applied refetches the folder instead of assuming it failed",
        arguments: ambiguousErrors
    )
    func anAmbiguousDeleteFailureRefetchesTheFolder(error: FilesClientError) async {
        let browseCalls = LockIsolated(0)
        let favorites = AsyncGate()
        let store = BrowseFixtures.store(BrowseFixtures.loadedState(TestPath.docsLowercase, items: [kept])) {
            $0.serveEmptyFolders()
            $0.filesClient.browse = { _, path in
                browseCalls.withValue { $0 += 1 }
                return BrowseResult(items: [], access: BrowseTestSupport.readOnlyAccess, path: path)
            }
            $0.holdFavorites(favorites)
        }

        await store.send(.deleteResponse(.failure(error))) {
            $0.fileActionErrorMessage = error.userMessage
            $0.phase = .loading
        }
        await receiveRefetch(store, listing: [], favorites: favorites)
        #expect(browseCalls.value == 1)
    }

    @Test(
        "A transfer that may have applied refetches the folder and shows what the server holds",
        arguments: ambiguousErrors
    )
    func anAmbiguousTransferFailureRefetchesTheFolder(error: FilesClientError) async {
        let copy = BrowseFixtures.file("a (2).txt", in: TestPath.docsLowercase)
        let browseCalls = LockIsolated(0)
        let favorites = AsyncGate()
        let store = BrowseFixtures.store(BrowseFixtures.loadedState(TestPath.docsLowercase, items: [kept])) {
            $0.serveEmptyFolders()
            $0.filesClient.browse = { _, path in
                browseCalls.withValue { $0 += 1 }
                return BrowseResult(items: [kept, copy], access: BrowseTestSupport.readOnlyAccess, path: path)
            }
            $0.holdFavorites(favorites)
        }

        await store.send(.transferResponse(.failure(error))) {
            $0.transferErrorMessage = error.userMessage
            $0.phase = .loading
        }
        // The server numbers the copy "a (2).txt", which sorts before "a.txt".
        await receiveRefetch(store, listing: [copy, kept], favorites: favorites)
        #expect(browseCalls.value == 1)
    }

    @Test("An ordinary server failure on a delete is shown without a refetch")
    func anOrdinaryServerFailureDoesNotRefetch() async {
        // No filesClient override: a refetch fails the test as unimplemented.
        let store = BrowseFixtures.store(BrowseFixtures.loadedState(TestPath.docsLowercase, items: [kept]))

        await store.send(.deleteResponse(.failure(.server(statusCode: 500)))) {
            $0.fileActionErrorMessage = FilesClientError.server(statusCode: 500).userMessage
        }
    }

    @Test("Only a timeout or a gateway answer may have been applied on the server", arguments: ambiguityCases)
    func mayHaveAppliedOnServerFollowsTheError(_ testCase: AmbiguityCase) {
        #expect(BrowseFeature.mayHaveAppliedOnServer(testCase.error) == testCase.isAmbiguous)
    }
}
