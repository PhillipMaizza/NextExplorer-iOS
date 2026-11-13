import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct FavoritesLoadingTests: FavoritesTestSupport {
    @Test
    func onAppearLoadsFavorites() async {
        let favorite = makeFavorite()
        let store = TestStore(initialState: FavoritesFeature.State(serverURL: serverURL)) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient.favorites = { _ in [favorite] }
        }

        await store.send(.onAppear) {
            $0.phase = .loading
        }
        await store.receive(\.favoritesResponse.success) {
            $0.phase = .loaded
            $0.favorites = [favorite]
        }
        await store.receive(\.offlineAvailabilityComputed)
    }

    @Test
    func refreshButtonTappedReloadsEvenWhenFavoritesAreAlreadyLoaded() async {
        let existing = makeFavorite(id: "1", path: "Old")
        let refreshed = makeFavorite(id: "2", path: "New")
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [existing]

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient.favorites = { _ in [refreshed] }
        }

        await store.send(.refreshButtonTapped) {
            $0.phase = .loading
        }
        await store.receive(\.favoritesResponse.success) {
            $0.phase = .loaded
            $0.favorites = [refreshed]
        }
        await store.receive(\.offlineAvailabilityComputed)
    }

    @Test
    func rowTappedPushesTheFavoritedFolderOntoTheOwnPathStackWithoutLeavingTheTab() async {
        let favorite = makeFavorite(path: "Photos/Vacation", label: "My Trip")
        let store = TestStore(initialState: FavoritesFeature.State(serverURL: serverURL)) {
            FavoritesFeature()
        }

        await store.send(.rowTapped(favorite)) {
            $0.path.append(BrowseFeature.State(
                serverURL: serverURL,
                directoryPath: "Photos/Vacation",
                title: "My Trip"
            ))
        }
    }

    @Test
    func rowTappedWithNoCustomLabelFallsBackToTheLastPathComponent() async {
        let favorite = makeFavorite(path: "Photos/Vacation", label: nil)
        let store = TestStore(initialState: FavoritesFeature.State(serverURL: serverURL)) {
            FavoritesFeature()
        }

        await store.send(.rowTapped(favorite)) {
            $0.path.append(BrowseFeature.State(
                serverURL: serverURL,
                directoryPath: "Photos/Vacation",
                title: "Vacation"
            ))
        }
    }

    @Test
    func offlineFallsBackToTheSavedCopyUnderTheBanner() async throws {
        let fav = makeFavorite(id: "1", path: TestFolder.docs)
        let cache = try JSONCacheStore.seeded(
            [fav],
            forKey: ListCache.key(Constants.favorites, serverURL: serverURL),
            fetchedAt: MockDate.date
        )
        let gate = AsyncGate()

        let store = TestStore(initialState: FavoritesFeature.State(serverURL: serverURL)) {
            FavoritesFeature()
        } withDependencies: {
            $0.jsonCacheStore = cache
            $0.filesClient.favorites = { _ in
                try await gate.wait()
                throw FilesClientError.offline
            }
        }

        // The state already holds the saved copy, painted when it was built inside the dependency context.
        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.offlineAvailabilityComputed)
        gate.open()
        await store.receive(\.favoritesResponse.failure)
        await store.receive(\.offlineFavoritesResolved) {
            $0.phase = .loaded
            $0.dataSource = .cached(fetchedAt: MockDate.date)
        }
        await store.receive(\.offlineAvailabilityComputed)
    }

    @Test
    func offlineWithNoSavedCopyShowsTheErrorInstead() async {
        let store = TestStore(initialState: FavoritesFeature.State(serverURL: serverURL)) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient.favorites = { _ in throw FilesClientError.offline }
        }

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.favoritesResponse.failure)
        await store.receive(\.offlineFavoritesResolved) {
            $0.phase = .failed(FilesClientError.offline.userMessage)
        }
    }

    @Test
    func stateInitPaintsTheSavedCopySoTheFirstFrameIsNotBlank() throws {
        let cache = JSONCacheStore.inMemory()
        let fav = makeFavorite(id: "7", path: "Downloads")
        try cache.write(
            key: ListCache.key(Constants.favorites, serverURL: serverURL),
            data: JSONEncoder().encode([fav])
        )

        // Constructed inside the dependency context the way the app builds the tab at mount: the
        // saved copy is painted synchronously, before any `onAppear`, so an unreachable server
        // can't leave the tab blank while its fetch times out. `phase` stays `.idle` so the tab
        // still refetches.
        let state = withDependencies {
            $0.jsonCacheStore = cache
        } operation: {
            FavoritesFeature.State(serverURL: serverURL)
        }

        #expect(state.favorites.map(\.id) == ["7"])
        #expect(state.phase == .idle)
        #expect(state.dataSource == .live)
    }

    @Test
    func offlineAvailabilityFlagsPinnedRootsAndTheirSubfolders() async {
        let offline = OfflineFileStore.inMemory()
        offline.setPinnedRoots([OfflinePinnedRoot(path: TestFolder.docs, isDirectory: true)])
        let root = makeFavorite(id: "A", path: TestFolder.docs, position: 0)
        let subfolder = makeFavorite(id: "B", path: "Docs/Reports", position: 1)
        let unrelated = makeFavorite(id: "C", path: TestFolder.photos, position: 2)

        let store = TestStore(initialState: FavoritesFeature.State(serverURL: serverURL)) {
            FavoritesFeature()
        } withDependencies: {
            $0.offlineFileStore = offline
            $0.filesClient.favorites = { _ in [root, subfolder, unrelated] }
        }

        await store.send(.refreshButtonTapped) { $0.phase = .loading }
        await store.receive(\.favoritesResponse.success) {
            $0.phase = .loaded
            $0.favorites = [root, subfolder, unrelated]
        }
        // The pinned root and the favorite that sits under it are both flagged; the unrelated one
        // is not.
        await store.receive(\.offlineAvailabilityComputed) { $0.offlineFavoriteIDs = ["A", "B"] }
    }

    @Test
    func aSuccessfulLoadWritesTheSavedCopyAndMarksLive() async throws {
        let cache = JSONCacheStore.inMemory()
        let fav = makeFavorite(id: "9", path: TestFolder.photos)
        let store = TestStore(initialState: FavoritesFeature.State(serverURL: serverURL)) {
            FavoritesFeature()
        } withDependencies: {
            $0.jsonCacheStore = cache
            $0.filesClient.favorites = { _ in [fav] }
        }

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.favoritesResponse.success) {
            $0.phase = .loaded
            $0.favorites = [fav]
        }
        await store.receive(\.offlineAvailabilityComputed)

        #expect(store.state.dataSource == .live)
        let cached = try #require(cache.read(key: ListCache.key(Constants.favorites, serverURL: serverURL)))
        let decoded = try JSONDecoder().decode([Favorite].self, from: cached.data)
        #expect(decoded.map(\.id) == ["9"])
    }

    @Test
    func onAppearSurfacesAFavoritesFailureAsAReadableErrorMessage() async {
        let store = TestStore(initialState: FavoritesFeature.State(serverURL: serverURL)) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient.favorites = { _ in throw FilesClientError.sessionExpired }
        }

        await store.send(.onAppear) {
            $0.phase = .loading
        }
        await store.receive(\.favoritesResponse.failure) {
            $0.phase = .failed(FilesClientError.sessionExpired.userMessage)
        }
    }

    @Test
    func refreshAfterAFailureClearsThePreviousErrorMessage() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.phase = .failed("Couldn't reach the server.")
        let favorite = makeFavorite()

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient.favorites = { _ in [favorite] }
        }

        await store.send(.refreshButtonTapped) {
            $0.phase = .loading
        }
        await store.receive(\.favoritesResponse.success) {
            $0.phase = .loaded
            $0.favorites = [favorite]
        }
        await store.receive(\.offlineAvailabilityComputed)
    }

    @Test
    func onAppearIsANoOpWhenFavoritesAreAlreadyLoaded() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [makeFavorite()]
        state.phase = .loaded

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        // No `filesClient` dependency overridden: a network call here would crash with
        // "Unimplemented", proving the guard skips a redundant fetch. `onAppear` still refreshes
        // the offline badges (a disk read, no network), so that one effect is expected.
        await store.send(.onAppear)
        await store.receive(\.offlineAvailabilityComputed)
    }

    @Test
    func onAppearRetriesAfterAFailedLoad() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.phase = .failed("Something went wrong.")
        let favorite = makeFavorite()

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient.favorites = { _ in [favorite] }
        }

        // A `.failed` phase is retryable: coming back to the tab kicks a fresh load.
        await store.send(.onAppear) {
            $0.phase = .loading
        }
        await store.receive(\.favoritesResponse.success) {
            $0.phase = .loaded
            $0.favorites = [favorite]
        }
        await store.receive(\.offlineAvailabilityComputed)
    }

    @Test
    func onAppearIsANoOpWhileAlreadyLoading() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.phase = .loading

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        await store.send(.onAppear)
    }

    @Test
    func favoritesResponseWithAnEmptyListClearsExistingFavorites() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [makeFavorite()]

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        await store.send(.favoritesResponse(.success([]))) {
            $0.favorites = []
            $0.phase = .loaded
        }
    }
}

private enum Constants {
    static let favorites = "favorites"
}
