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
struct FavoritesFeatureTests {
    private let serverURL = URL(fileURLWithPath: "/")

    private func makeFavorite(id: String = "1", path: String = "Documents", label: String? = nil, position: Int = 0) -> Favorite {
        Favorite(id: id, path: path, label: label, icon: "folder", color: nil, position: position, createdAt: MockDate.date, updatedAt: MockDate.date)
    }

    // MARK: Happy path

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
            $0.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos/Vacation", title: "My Trip"))
        }
    }

    @Test
    func rowTappedWithNoCustomLabelFallsBackToTheLastPathComponent() async {
        let favorite = makeFavorite(path: "Photos/Vacation", label: nil)
        let store = TestStore(initialState: FavoritesFeature.State(serverURL: serverURL)) {
            FavoritesFeature()
        }

        await store.send(.rowTapped(favorite)) {
            $0.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos/Vacation", title: "Vacation"))
        }
    }

    @Test
    func offlineFallsBackToTheSavedCopyUnderTheBanner() async throws {
        let fav = makeFavorite(id: "1", path: "Docs")
        let cache = try JSONCacheStore.seeded([fav], forKey: ListCache.key("favorites", serverURL: serverURL), fetchedAt: MockDate.date)
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
        try cache.write(key: ListCache.key("favorites", serverURL: serverURL), data: JSONEncoder().encode([fav]))

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
        offline.setPinnedRoots([OfflinePinnedRoot(path: "Docs", isDirectory: true)])
        let root = makeFavorite(id: "A", path: "Docs", position: 0)
        let subfolder = makeFavorite(id: "B", path: "Docs/Reports", position: 1)
        let unrelated = makeFavorite(id: "C", path: "Photos", position: 2)

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
        let fav = makeFavorite(id: "9", path: "Photos")
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
        let cached = try #require(cache.read(key: ListCache.key("favorites", serverURL: serverURL)))
        let decoded = try JSONDecoder().decode([Favorite].self, from: cached.data)
        #expect(decoded.map(\.id) == ["9"])
    }

    @Test
    func rapidRemoveDoubleTapFiresASingleRequest() async {
        let favorite = makeFavorite(id: "1", path: "Documents")
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [favorite]
        let gate = AsyncGate()
        let completions = LockIsolated(0)

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient.removeFavorite = { _, _ in
                try await gate.wait()
                completions.withValue { $0 += 1 }
            }
        }

        // The second tap cancels the first request, so only one reaches the end of the gate.
        await store.send(.removeTapped(favorite))
        await store.send(.removeTapped(favorite))
        gate.open()
        await store.receive(\.removeResponse) { $0.favorites = [] }

        #expect(completions.value == 1)
    }

    @Test
    func openFolderDelegateFromAPushedScreenPushesAnotherLevel() async {
        let subfolder = FileItem(name: "2020", path: "Photos", dateModified: MockDate.date, size: 0, kind: "directory")
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos", title: "Photos"))

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        await store.send(.path(.element(id: 0, action: .delegate(.openFolder(subfolder))))) {
            $0.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos/2020", title: "2020"))
        }
    }

    @Test
    func openPathDelegateFromAPushedScreenForwardsToNavigateToDirectory() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos", title: "Photos"))

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        // An empty path, because a pushed screen's stack id comes from a generator that a `receive`
        // assertion cannot rewind. What the stack holds after a jump to a real path is covered by
        // navigateToDirectoryReplacesThePathStackWithASingleLevel.
        await store.send(.path(.element(id: 0, action: .delegate(.openPath(path: "", title: "Home")))))
        await store.receive(\.navigateToDirectory) { $0.path = StackState() }
    }

    @Test
    func favoritesChangedFromAPushedScreenBubblesUpAsADelegate() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos", title: "Photos"))

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        await store.send(.path(.element(id: 0, action: .delegate(.favoritesChanged))))
        await store.receive(.delegate(.favoritesChanged))
    }

    @Test
    func openDownloadsTappedFromAPushedScreenBubblesUpAsADelegate() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos", title: "Photos"))

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        await store.send(.path(.element(id: 0, action: .delegate(.openDownloadsTapped))))
        await store.receive(.delegate(.openDownloadsTapped))
    }

    @Test
    func goToSharedTabFromAPushedScreenBubblesUpAsADelegate() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos", title: "Photos"))

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        await store.send(.path(.element(id: 0, action: .delegate(.goToSharedTab))))
        await store.receive(.delegate(.goToSharedTab))
    }

    @Test
    func navigateToDirectoryReplacesThePathStackWithASingleLevel() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Old", title: "Old"))

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        await store.send(.navigateToDirectory(path: "Music", title: "Music")) {
            $0.path = StackState([BrowseFeature.State(serverURL: serverURL, directoryPath: "Music", title: "Music")])
        }
    }

    @Test
    func navigateToDirectoryWithAnEmptyPathJustClearsTheStack() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Old", title: "Old"))

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        await store.send(.navigateToDirectory(path: "", title: "Home")) {
            $0.path = StackState()
        }
    }

    @Test
    func syncPathStackRefreshesEveryPushedSubfolder() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos", title: "Photos"))
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos/2020", title: "2020"))
        let pathIDs = state.path.ids
        let refreshed = FileItem(name: "New.txt", path: "", dateModified: MockDate.date, size: 0, kind: "txt")
        let access = FileAccess(canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true)
        let firstGate = AsyncGate()
        let secondGate = AsyncGate()
        let browsed = LockIsolated<[String]>([])

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, path in
                browsed.withValue { $0.append(path) }
                try await (path == "Photos" ? firstGate : secondGate).wait()
                return BrowseResult(items: [refreshed], access: access, path: path)
            }
            $0.filesClient.favorites = { _ in throw FilesClientError.offline }
        }

        await store.send(.syncPathStack)
        await store.receive(\.path[id: pathIDs[0]].refreshButtonTapped) {
            $0.path[id: pathIDs[0]]?.phase = .loading
        }
        await store.receive(\.path[id: pathIDs[1]].refreshButtonTapped) {
            $0.path[id: pathIDs[1]]?.phase = .loading
        }
        // Each screen's answer is released in turn so its follow up actions arrive in a fixed order.
        for (index, gate) in [firstGate, secondGate].enumerated() {
            gate.open()
            await store.receive(\.path[id: pathIDs[index]].itemsResponse.success) {
                $0.path[id: pathIDs[index]]?.phase = .loaded
                $0.path[id: pathIDs[index]]?.items = [refreshed]
                $0.path[id: pathIDs[index]]?.access = access
            }
            await store.receive(\.path[id: pathIDs[index]].offlineAvailabilityComputed)
        }
        await store.finish()

        #expect(Set(browsed.value) == ["Photos", "Photos/2020"])
    }

    @Test
    func syncPathStackWithNoPushedScreensDoesNothing() async {
        let store = TestStore(initialState: FavoritesFeature.State(serverURL: serverURL)) {
            FavoritesFeature()
        }

        await store.send(.syncPathStack)
    }

    @Test
    func searchQueryChangedFiltersDisplayedFavorites() async {
        let vacation = makeFavorite(id: "1", path: "Photos/Vacation")
        let work = makeFavorite(id: "2", path: "Documents/Work")
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [vacation, work]

        let clock = TestClock()
        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.filesClient.search = { _, _, _, _ in [] }
        }

        // The name filter over the favorite folders still applies (a query also kicks off the
        // recursive file search fan out, exercised in its own test).
        await store.send(.searchQueryChanged("vaca")) {
            $0.searchQuery = "vaca"
            $0.searchPhase = .loading
        }
        #expect(store.state.displayedFavorites == [vacation])

        await clock.advance(by: .seconds(1))
        await store.receive(\.fileSearchResponse.success) {
            $0.fileSearchResults = []
            $0.searchPhase = .loaded
        }
    }

    @Test
    func loadOrdersFavoritesByPositionRegardlessOfResponseOrder() async {
        let first = makeFavorite(id: "1", path: "Alpha", position: 0)
        let second = makeFavorite(id: "2", path: "Beta", position: 1)
        let store = TestStore(initialState: FavoritesFeature.State(serverURL: serverURL)) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient.favorites = { _ in [second, first] }
        }

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.favoritesResponse.success) {
            $0.phase = .loaded
            $0.favorites = [first, second]
        }
        await store.receive(\.offlineAvailabilityComputed)

        #expect(store.state.displayedFavorites == [first, second])
    }

    @Test
    func movingAFavoriteReordersOptimisticallyAndPatchesTheFullOrder() async {
        let a = makeFavorite(id: "a", path: "A", position: 0)
        let b = makeFavorite(id: "b", path: "B", position: 1)
        let c = makeFavorite(id: "c", path: "C", position: 2)
        let reordered = [
            makeFavorite(id: "c", path: "C", position: 0),
            makeFavorite(id: "a", path: "A", position: 1),
            makeFavorite(id: "b", path: "B", position: 2),
        ]
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [a, b, c]

        let recorded = LockIsolated<[String]?>(nil)
        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient.reorderFavorites = { _, ids in
                recorded.setValue(ids)
                return reordered
            }
        }

        // Move C to the front.
        await store.send(.favoritesMoved(IndexSet(integer: 2), 0)) { $0.favorites = [c, a, b] }
        await store.receive(\.reorderResponse.success) { $0.favorites = IdentifiedArray(uniqueElements: reordered) }
        await store.receive(.delegate(.favoritesChanged))

        #expect(recorded.value == ["c", "a", "b"])
    }

    @Test
    func aFailedReorderShowsAToastAndRefetchesTheAuthoritativeOrder() async {
        let a = makeFavorite(id: "a", path: "A", position: 0)
        let b = makeFavorite(id: "b", path: "B", position: 1)
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [a, b]

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient.reorderFavorites = { _, _ in throw FilesClientError.network("offline") }
            $0.filesClient.favorites = { _ in [a, b] }
        }

        await store.send(.favoritesMoved(IndexSet(integer: 1), 0)) { $0.favorites = [b, a] }
        await store.receive(\.reorderResponse.failure) {
            $0.actionErrorMessage = L10n.Favorites.reorderFailed
            $0.phase = .loading
        }
        await store.receive(\.favoritesResponse.success) {
            $0.phase = .loaded
            $0.favorites = [a, b]
        }
        await store.receive(\.offlineAvailabilityComputed)
    }

    @Test
    func reorderIsIgnoredWhileSearching() async {
        let a = makeFavorite(id: "a", path: "A", position: 0)
        let b = makeFavorite(id: "b", path: "B", position: 1)
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [a, b]
        state.searchQuery = "a"

        let store = TestStore(initialState: state) { FavoritesFeature() }

        await store.send(.favoritesMoved(IndexSet(integer: 1), 0))
    }

    @Test
    func editTappedPresentsTheSheetAndAnUpdateSwapsTheRow() async {
        let favorite = makeFavorite(id: "f1", path: "Documents", label: "Docs")
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [favorite]

        let store = TestStore(initialState: state) { FavoritesFeature() }

        await store.send(.editTapped(favorite)) {
            $0.editSheet = FavoriteEditFeature.State(serverURL: serverURL, favorite: favorite)
        }

        let updated = Favorite(
            id: "f1", path: "Documents", label: "Projects", icon: "solid:BriefcaseIcon", color: "#009cff",
            position: 0, createdAt: favorite.createdAt, updatedAt: MockDate.date
        )
        await store.send(.editSheet(.presented(.delegate(.updated(updated))))) {
            $0.favorites[id: "f1"] = updated
            $0.editSheet = nil
        }
        await store.receive(.delegate(.favoritesChanged))
    }

    @Test
    func selectModeTogglesAndClearsSelection() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.selectedFavoriteIDs = ["1"]

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        await store.send(.selectModeToggled) {
            $0.isSelecting = true
            $0.selectedFavoriteIDs = []
        }
    }

    @Test
    func itemSelectionToggledAddsThenRemovesTheSameID() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.isSelecting = true

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        await store.send(.itemSelectionToggled("1")) {
            $0.selectedFavoriteIDs = ["1"]
        }
        await store.send(.itemSelectionToggled("1")) {
            $0.selectedFavoriteIDs = []
        }
    }

    @Test
    func selectAllAndDeselectAllTapped() async {
        let a = makeFavorite(id: "1", path: "A")
        let b = makeFavorite(id: "2", path: "B")
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [a, b]
        state.isSelecting = true

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        await store.send(.selectAllTapped) {
            $0.selectedFavoriteIDs = ["1", "2"]
        }
        await store.send(.deselectAllTapped) {
            $0.selectedFavoriteIDs = []
        }
    }

    @Test
    func removeTappedRemovesASingleFavoriteOnSuccess() async {
        let favorite = makeFavorite(path: "Photos")
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [favorite]

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient.removeFavorite = { _, _ in }
        }

        await store.send(.removeTapped(favorite))
        await store.receive(\.removeResponse) {
            $0.favorites = []
        }
    }

    @Test
    func bulkRemoveConfirmedRemovesEverySelectedFavorite() async {
        let a = makeFavorite(id: "1", path: "A")
        let b = makeFavorite(id: "2", path: "B")
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [a, b]
        state.isSelecting = true
        state.selectedFavoriteIDs = ["1", "2"]

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient.removeFavorite = { _, _ in }
        }

        await store.send(.bulkRemoveTapped) {
            $0.bulkRemoveConfirmationIsPresented = true
        }
        await store.send(.bulkRemoveConfirmed) {
            $0.bulkRemoveConfirmationIsPresented = false
        }
        await store.receive(\.bulkRemoveResponse) {
            $0.favorites = []
            $0.isSelecting = false
            $0.selectedFavoriteIDs = []
        }
    }

    @Test
    func bulkRemoveTappedWithNoSelectionDoesNothing() async {
        let store = TestStore(initialState: FavoritesFeature.State(serverURL: serverURL)) {
            FavoritesFeature()
        }

        await store.send(.bulkRemoveTapped)
    }

    // MARK: Error path

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

    // MARK: Edge cases

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

    // MARK: Recursive file search across favorites

    @Test
    func rootSearchFansOutAcrossEveryFavoriteAndMergesResults() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [makeFavorite(id: "1", path: "Bills"), makeFavorite(id: "2", path: "Photos")]

        let billsHit = SearchResultItem(name: "internet.pdf", path: "Bills", kind: "file")
        let photosHit = SearchResultItem(name: "photos-internet.png", path: "Photos", kind: "file")
        let clock = TestClock()
        let searchedPaths = LockIsolated<Set<String>>([])

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.filesClient.search = { _, path, _, _ in
                searchedPaths.withValue { $0.insert(path) }
                switch path {
                case "Bills": return [billsHit]
                case "Photos": return [photosHit]
                default: return []
                }
            }
        }

        await store.send(.searchQueryChanged("internet")) {
            $0.searchQuery = "internet"
            $0.searchPhase = .loading
        }
        await clock.advance(by: .seconds(1))
        // Both hits merged into the results, alphabetically.
        await store.receive(\.fileSearchResponse.success) {
            $0.fileSearchResults = [billsHit, photosHit]
            $0.searchPhase = .loaded
        }

        // One backend search per favorite.
        #expect(searchedPaths.value == ["Bills", "Photos"])
    }

    @Test
    func clearingTheQueryCancelsTheSearchAndClearsResults() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [makeFavorite(id: "1", path: "Bills")]
        state.searchQuery = "internet"
        state.fileSearchResults = [SearchResultItem(name: "internet.pdf", path: "Bills", kind: "file")]
        state.searchPhase = .loaded
        let clock = TestClock()

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.filesClient.search = { _, _, _, _ in [] }
        }

        await store.send(.searchQueryChanged("")) {
            $0.searchQuery = ""
            $0.fileSearchResults = nil
            $0.searchPhase = .idle
        }
        await clock.advance(by: .seconds(1))
        await store.finish()
    }

    @Test
    func enclosingFolderFromAFavoritesOwnFolderReturnsToTheListAndForwardReopensIt() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        let folder = BrowseFeature.State(serverURL: serverURL, directoryPath: "Docs/Work", title: "Work")
        state.path.append(folder)
        let store = TestStore(initialState: state) { FavoritesFeature() }

        await store.send(.goToEnclosingFolder) {
            $0.path.removeLast()
            $0.forwardStack = [folder]
        }
        await store.send(.goForward) {
            $0.forwardStack = []
            $0.path.append(folder)
        }
    }
}
