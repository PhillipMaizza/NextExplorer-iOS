import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// The saved copy of a listing: painted before the fetch, kept when the server is unreachable, and
/// warmed ahead of time for the folders around the one on screen.
@Suite(.isolatedDependencies)
@MainActor
struct BrowseOfflineCacheTests {
    private let access = BrowseTestSupport.readOnlyAccess
    private let fetchedAt = MockDate.date.addingTimeInterval(1_000)
    private let cachedItem = BrowseFixtures.file("Saved.txt", in: TestPath.docsLowercase, size: 1)

    private func docsStore(
        state: BrowseFeature.State = BrowseFixtures.state(TestPath.docsLowercase, title: TestFolder.docs),
        configure: (inout DependencyValues) -> Void
    ) -> TestStoreOf<BrowseFeature> {
        BrowseFixtures.store(state) { configure(&$0) }
    }

    private func cachedListing(_ items: [FileItem]) -> CachedDirectory {
        CachedDirectory(path: TestPath.docsLowercase, items: items, access: access, fetchedAt: fetchedAt)
    }

    @Test("Offline with a saved copy paints it first, then keeps it under the saved copy banner")
    func offlineBrowseFailureFallsBackToTheCachedListing() async {
        let browse = AsyncGate()
        let favorites = AsyncGate()
        let cached = cachedListing([cachedItem])
        let store = docsStore {
            $0.serveEmptyFolders()
            $0.filesClient.browse = { _, _ in
                try await browse.wait()
                throw FilesClientError.offline
            }
            $0.holdFavorites(favorites)
            $0.directoryCacheStore.read = { _, _ in cached }
        }

        await store.send(.onAppear) {
            $0.phase = .loading
        }
        await store.receive(\.cachedListingPainted) {
            $0.items = [cachedItem]
            $0.access = access
            $0.isShowingCachePaint = true
        }
        browse.open()
        await store.receive(\.itemsResponse.failure)
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

    @Test("Offline, a pinned folder lists from the copy kept with its files when the cache has nothing")
    func offlineBrowseFallsBackToTheListingKeptWithThePinnedFolder() async {
        let browse = AsyncGate()
        let favorites = AsyncGate()
        let offline = OfflineFileStore.inMemory()
        offline.saveListing(cachedListing([cachedItem]))
        let store = docsStore {
            $0.serveEmptyFolders()
            $0.filesClient.browse = { _, _ in
                try await browse.wait()
                throw FilesClientError.offline
            }
            $0.holdFavorites(favorites)
            $0.directoryCacheStore.read = { _, _ in nil }
            $0.offlineFileStore = offline
        }

        await store.send(.onAppear) {
            $0.phase = .loading
        }
        await store.receive(\.cachedListingPainted) {
            $0.items = [cachedItem]
            $0.access = access
            $0.isShowingCachePaint = true
        }
        browse.open()
        await store.receive(\.itemsResponse.failure)
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

    @Test("Offline with nothing saved shows the offline message")
    func offlineBrowseFailureWithNoCacheShowsTheErrorMessage() async {
        let favorites = AsyncGate()
        let store = docsStore {
            $0.serveEmptyFolders()
            $0.filesClient.browse = { _, _ in throw FilesClientError.offline }
            $0.holdFavorites(favorites)
            $0.directoryCacheStore.read = { _, _ in nil }
        }

        await store.send(.onAppear) {
            $0.phase = .loading
        }
        await store.receive(\.itemsResponse.failure)
        await store.receive(\.offlineListingResolved) {
            $0.phase = .failed(FilesClientError.offline.userMessage)
        }
        favorites.open()
        await store.receive(\.favoritesResponse) {
            $0.hasLoadedFavorites = true
        }
    }

    @Test("A saved copy shows at once without the offline banner, and fresh data replaces it")
    func cacheFirstPaintShowsSavedItemsWithoutTheOfflineBannerThenFreshDataReplacesThem() async {
        let fresh = BrowseFixtures.file("New.txt", in: TestPath.docsLowercase, size: 2)
        let browse = AsyncGate()
        let favorites = AsyncGate()
        let cached = cachedListing([BrowseFixtures.file("Old.txt", in: TestPath.docsLowercase, size: 1)])
        let store = docsStore {
            $0.serveEmptyFolders()
            $0.filesClient.browse = { _, path in
                try await browse.wait()
                return BrowseResult(items: [fresh], access: BrowseTestSupport.readOnlyAccess, path: path)
            }
            $0.holdFavorites(favorites)
            $0.directoryCacheStore.read = { _, _ in cached }
        }

        await store.send(.onAppear) {
            $0.phase = .loading
        }
        await store.receive(\.cachedListingPainted) {
            $0.items = [BrowseFixtures.file("Old.txt", in: TestPath.docsLowercase, size: 1)]
            $0.access = access
            $0.isShowingCachePaint = true
        }
        browse.open()
        await store.receive(\.itemsResponse.success) {
            $0.phase = .loaded
            $0.items = [fresh]
            $0.isShowingCachePaint = false
        }
        await store.receive(\.offlineAvailabilityComputed)
        favorites.open()
        await store.receive(\.favoritesResponse) {
            $0.hasLoadedFavorites = true
        }
    }

    @Test("A successful browse warms the immediate subfolders only, not files")
    func aSuccessfulBrowsePrefetchesImmediateSubfoldersOnly() async {
        let folder = BrowseFixtures.folder(TestFolder.photos, in: TestPath.docsLowercase)
        let file = BrowseFixtures.file(TestFile.aText, in: TestPath.docsLowercase, size: 1)
        let favorites = AsyncGate()
        let prefetched = LockIsolated<[String]>([])
        let store = docsStore {
            $0.serveEmptyFolders()
            $0.serveListing([folder, file])
            $0.holdFavorites(favorites)
            $0.filesClient.prefetchDirectory = { _, path in prefetched.withValue { $0.append(path) } }
            $0.directoryCacheStore.lastWrittenAt = { _, _ in nil }
        }

        await store.send(.onAppear) {
            $0.phase = .loading
        }
        await store.receive(\.itemsResponse.success) {
            $0.phase = .loaded
            $0.items = [folder, file]
            $0.access = access
        }
        await store.receive(\.offlineAvailabilityComputed)
        favorites.open()
        await store.receive(\.favoritesResponse) {
            $0.hasLoadedFavorites = true
        }
        await store.finish()
        #expect(prefetched.value == ["docs/Photos"])
    }

    @Test("Offline while items are on screen replaces them with the saved copy read in an effect")
    func anOfflineFailureReadsTheSavedListingInAnEffectAndThenShowsIt() async {
        let live = BrowseFixtures.file("Live.txt", in: TestPath.docsLowercase, size: 1)
        let cached = cachedListing([cachedItem])
        let store = docsStore(state: BrowseFixtures.loadedState(TestPath.docsLowercase, items: [live])) {
            $0.directoryCacheStore.read = { _, _ in cached }
        }

        await store.send(.itemsResponse(.failure(.offline)))
        await store.receive(\.offlineListingResolved) {
            $0.items = [cachedItem]
            $0.access = access
            $0.dataSource = .cached(fetchedAt: fetchedAt)
        }
        await store.receive(\.offlineAvailabilityComputed)
    }

    @Test("A saved copy that arrives after the live listing is dropped")
    func aPaintThatArrivesAfterTheLiveListingIsDropped() async {
        let live = BrowseFixtures.file("Live.txt", in: TestPath.docsLowercase, size: 1)
        let store = docsStore(state: BrowseFixtures.loadedState(TestPath.docsLowercase, items: [live])) { _ in }

        await store.send(.cachedListingPainted(cachedListing([cachedItem])))
    }

    @Test(
        "A server error after the saved copy was painted shows the error, not the stale list",
        arguments: [404, 403, 500]
    )
    func aServerErrorAfterTheCachePaintShowsTheErrorNotTheStaleList(statusCode: Int) async {
        let error = FilesClientError.server(statusCode: statusCode)
        let browse = AsyncGate()
        let cached = cachedListing([cachedItem])
        let store = docsStore {
            $0.serveEmptyFolders()
            $0.filesClient.browse = { _, _ in
                try await browse.wait()
                throw error
            }
            $0.directoryCacheStore.read = { _, _ in cached }
        }

        await store.send(.onAppear) {
            $0.phase = .loading
        }
        await store.receive(\.cachedListingPainted) {
            $0.items = [cachedItem]
            $0.access = access
            $0.isShowingCachePaint = true
        }
        browse.open()
        await store.receive(\.itemsResponse.failure) {
            $0.items = []
            $0.access = nil
            $0.phase = .failed(error.userMessage)
            $0.isShowingCachePaint = false
        }
        await store.receive(\.favoritesResponse) {
            $0.hasLoadedFavorites = true
        }
    }

    @Test("A server error on a refresh of the offline saved copy shows the error, not the stale list")
    func aServerErrorOnARefreshOfAnOfflineSavedCopyShowsTheErrorNotTheStaleList() async {
        let error = FilesClientError.server(statusCode: 404)
        var state = BrowseFixtures.loadedState(TestPath.docsLowercase, items: [cachedItem], access: access)
        state.dataSource = .cached(fetchedAt: fetchedAt)
        let store = docsStore(state: state) {
            $0.serveEmptyFolders()
            $0.filesClient.browse = { _, _ in throw error }
        }

        await store.send(.refreshButtonTapped) {
            $0.phase = .loading
        }
        await store.receive(\.itemsResponse.failure) {
            $0.items = []
            $0.access = nil
            $0.phase = .failed(error.userMessage)
            $0.dataSource = .live
        }
        await store.receive(\.favoritesResponse) {
            $0.hasLoadedFavorites = true
        }
    }
}
