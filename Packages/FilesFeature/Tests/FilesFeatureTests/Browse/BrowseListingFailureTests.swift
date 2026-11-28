import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct BrowseListingFailureTests {
    private let access = BrowseTestSupport.readOnlyAccess
    private let fetchedAt = MockDate.date.addingTimeInterval(1_000)
    private let savedItem = BrowseFixtures.file("Saved.txt", in: TestPath.docsLowercase, size: 1)

    private func docsStore(configure: (inout DependencyValues) -> Void) -> TestStoreOf<BrowseFeature> {
        BrowseFixtures.store(BrowseFixtures.state(TestPath.docsLowercase, title: TestFolder.docs)) { configure(&$0) }
    }

    @Test("A missing folder is told apart from other failures")
    func aMissingFolderIsToldApart() async {
        let error = FilesClientError.serverMessage(statusCode: 404, message: "Path not found.")
        let store = docsStore {
            $0.serveEmptyFolders()
            $0.filesClient.browse = { _, _ in throw error }
        }

        await store.send(.onAppear) {
            $0.phase = .loading
        }
        await store.receive(\.itemsResponse.failure) {
            $0.phase = .failed(error.userMessage)
            $0.listingFailure = .folderMissing
        }
        await store.receive(\.favoritesResponse) {
            $0.hasLoadedFavorites = true
        }
    }

    @Test(
        "A server error with a saved copy keeps the copy on screen and offers a retry",
        arguments: [500, 503]
    )
    func aServerErrorKeepsTheSavedCopy(statusCode: Int) async {
        let saved = CachedDirectory(
            path: TestPath.docsLowercase,
            items: [savedItem],
            access: access,
            fetchedAt: fetchedAt
        )
        let browse = AsyncGate()
        let favorites = AsyncGate()
        let store = docsStore {
            $0.serveEmptyFolders()
            $0.filesClient.browse = { _, _ in
                try await browse.wait()
                throw FilesClientError.server(statusCode: statusCode)
            }
            $0.holdFavorites(favorites)
            $0.directoryCacheStore.read = { _, _ in saved }
        }

        await store.send(.onAppear) {
            $0.phase = .loading
        }
        await store.receive(\.cachedListingPainted) {
            $0.items = [savedItem]
            $0.access = access
            $0.isShowingCachePaint = true
        }
        browse.open()
        await store.receive(\.itemsResponse.failure) {
            $0.listingFailure = .serverProblem(statusCode: statusCode)
        }
        await store.receive(\.offlineListingResolved) {
            $0.isShowingCachePaint = false
            $0.phase = .loaded
            $0.dataSource = .cached(fetchedAt: fetchedAt)
        }
        await store.receive(\.offlineAvailabilityComputed)
        favorites.open()
        await store.receive(\.favoritesResponse) {
            $0.hasLoadedFavorites = true
        }
    }

    @Test("A server error on a refresh keeps the items on screen as a saved copy")
    func aServerErrorOnARefreshKeepsTheItems() async {
        let favorites = AsyncGate()
        let store = BrowseFixtures.store(BrowseFixtures.loadedState(TestPath.docsLowercase, items: [savedItem])) {
            $0.serveEmptyFolders()
            $0.filesClient.browse = { _, _ in throw FilesClientError.server(statusCode: 502) }
            $0.holdFavorites(favorites)
        }

        await store.send(.refreshButtonTapped) {
            $0.phase = .loading
        }
        await store.receive(\.itemsResponse.failure) {
            $0.listingFailure = .serverProblem(statusCode: 502)
        }
        await store.receive(\.offlineListingResolved) {
            $0.phase = .loaded
            $0.access = $0.access.map { BrowseFeature.shownAccess($0, isNarrowed: true) }
            $0.dataSource = .cached(fetchedAt: MockDate.date)
        }
        await store.receive(\.offlineAvailabilityComputed)
        favorites.open()
        await store.receive(\.favoritesResponse) {
            $0.hasLoadedFavorites = true
        }
    }

    @Test("A server error with nothing saved fails, and Try Again clears the failure")
    func aServerErrorWithNothingSavedFailsUntilRetried() async {
        let serverError = FilesClientError.server(statusCode: 500)
        let refused = FilesClientError.server(statusCode: 403)
        let answers = LockIsolated([serverError, refused])
        let favorites = AsyncGate()
        let store = docsStore {
            $0.serveEmptyFolders()
            $0.filesClient.browse = { _, _ in
                throw answers.withValue { $0.removeFirst() }
            }
            $0.holdFavorites(favorites)
        }

        await store.send(.onAppear) {
            $0.phase = .loading
        }
        await store.receive(\.itemsResponse.failure) {
            $0.listingFailure = .serverProblem(statusCode: 500)
        }
        await store.receive(\.offlineListingResolved) {
            $0.phase = .failed(serverError.userMessage)
        }
        favorites.open()
        await store.receive(\.favoritesResponse) {
            $0.hasLoadedFavorites = true
        }
        await store.send(.refreshButtonTapped) {
            $0.phase = .loading
            $0.listingFailure = nil
        }
        await store.receive(\.itemsResponse.failure) {
            $0.phase = .failed(refused.userMessage)
        }
        await store.receive(\.favoritesResponse)
    }
}
