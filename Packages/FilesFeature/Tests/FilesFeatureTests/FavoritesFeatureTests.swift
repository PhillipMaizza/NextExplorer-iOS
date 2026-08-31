import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Localization
import Testing

@testable import FilesFeature

@MainActor
@Suite
struct FavoritesFeatureTests {
    private let serverURL = URL(string: "https://example.com")!

    private func makeFavorite(id: String = "1", path: String = "Documents", label: String? = nil, position: Int = 0) -> Favorite {
        Favorite(id: id, path: path, label: label, icon: "folder", color: nil, position: position, createdAt: Date(), updatedAt: Date())
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
    }

    @Test
    func rowTappedPushesTheFavoritedFolderOntoTheOwnPathStackWithoutLeavingTheTab() async {
        let favorite = makeFavorite(path: "Photos/Vacation", label: "My Trip")
        let store = TestStore(initialState: FavoritesFeature.State(serverURL: serverURL)) {
            FavoritesFeature()
        }

        await store.send(.rowTapped(favorite)) {
            $0.path.append(BrowseFeature.State(serverURL: self.serverURL, directoryPath: "Photos/Vacation", title: "My Trip"))
        }
    }

    @Test
    func rowTappedWithNoCustomLabelFallsBackToTheLastPathComponent() async {
        let favorite = makeFavorite(path: "Photos/Vacation", label: nil)
        let store = TestStore(initialState: FavoritesFeature.State(serverURL: serverURL)) {
            FavoritesFeature()
        }

        await store.send(.rowTapped(favorite)) {
            $0.path.append(BrowseFeature.State(serverURL: self.serverURL, directoryPath: "Photos/Vacation", title: "Vacation"))
        }
    }

    @Test
    func openFolderDelegateFromAPushedScreenPushesAnotherLevel() async {
        let subfolder = FileItem(name: "2020", path: "Photos", dateModified: Date(), size: 0, kind: "directory")
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos", title: "Photos"))

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        await store.send(.path(.element(id: 0, action: .delegate(.openFolder(subfolder))))) {
            $0.path.append(BrowseFeature.State(serverURL: self.serverURL, directoryPath: "Photos/2020", title: "2020"))
        }
    }

    @Test
    func openPathDelegateFromAPushedScreenForwardsToNavigateToDirectory() async {
        // Exhaustivity off: the freshly-pushed `BrowseFeature.State` gets a `StackElementID`
        // that isn't reproducible from inside a `receive`-triggered assertion closure (`send`
        // gets special generator snapshotting from TCA, `receive` doesn't) — asserting the
        // resulting path's content is what actually matters here.
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos", title: "Photos"))

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }
        store.exhaustivity = .off

        await store.send(.path(.element(id: 0, action: .delegate(.openPath(path: "Music", title: "Music")))))
        await store.receive(\.navigateToDirectory)

        #expect(store.state.path.map(\.directoryPath) == ["Music"])
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
            $0.path = StackState([BrowseFeature.State(serverURL: self.serverURL, directoryPath: "Music", title: "Music")])
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
        let refreshed = FileItem(name: "New", path: "", dateModified: Date(), size: 0, kind: "directory")

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in
                BrowseResult(items: [refreshed], access: FileAccess(canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true), path: "")
            }
            $0.filesClient.favorites = { _ in [] }
        }
        store.exhaustivity = .off

        await store.send(.syncPathStack)
        await store.receive(\.path[id: pathIDs[0]].refreshButtonTapped) {
            $0.path[id: pathIDs[0]]?.phase = .loading
        }
        await store.receive(\.path[id: pathIDs[1]].refreshButtonTapped) {
            $0.path[id: pathIDs[1]]?.phase = .loading
        }
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

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        await store.send(.searchQueryChanged("vaca")) {
            $0.searchQuery = "vaca"
        }

        #expect(store.state.displayedFavorites == [vacation])
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
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.displayedFavorites == [first, second])
    }

    @Test
    func movingAFavoriteReordersOptimisticallyAndPatchesTheFullOrder() async {
        let a = makeFavorite(id: "a", path: "A", position: 0)
        let b = makeFavorite(id: "b", path: "B", position: 1)
        let c = makeFavorite(id: "c", path: "C", position: 2)
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [a, b, c]

        let recorded = LockIsolated<[String]?>(nil)
        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient.reorderFavorites = { _, ids in
                recorded.setValue(ids)
                return ids.enumerated().map { index, id in
                    Favorite(id: id, path: id, label: nil, icon: "folder", color: nil, position: index, createdAt: Date(), updatedAt: Date())
                }
            }
        }
        store.exhaustivity = .off

        // Move C to the front.
        await store.send(.favoritesMoved(IndexSet(integer: 2), 0))
        #expect(store.state.favorites.map(\.id) == ["c", "a", "b"])

        await store.skipReceivedActions()
        #expect(recorded.value == ["c", "a", "b"])
        #expect(store.state.favorites.map(\.id) == ["c", "a", "b"])
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
        store.exhaustivity = .off

        await store.send(.favoritesMoved(IndexSet(integer: 1), 0))
        await store.skipReceivedActions()

        #expect(store.state.actionErrorMessage == L10n.Favorites.reorderFailed)
        #expect(store.state.favorites.map(\.id) == ["a", "b"])
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
            $0.editSheet = FavoriteEditFeature.State(serverURL: self.serverURL, favorite: favorite)
        }

        let updated = Favorite(
            id: "f1", path: "Documents", label: "Projects", icon: "solid:BriefcaseIcon", color: "#009cff",
            position: 0, createdAt: favorite.createdAt, updatedAt: Date()
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

    @Test
    func bulkRemoveCancelledHidesTheConfirmationAlert() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.bulkRemoveConfirmationIsPresented = true

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        await store.send(.bulkRemoveCancelled) {
            $0.bulkRemoveConfirmationIsPresented = false
        }
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
        // "Unimplemented", proving the guard skips a redundant fetch.
        await store.send(.onAppear)
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

        // A `.failed` phase is retryable — coming back to the tab kicks a fresh load.
        await store.send(.onAppear) {
            $0.phase = .loading
        }
        await store.receive(\.favoritesResponse.success) {
            $0.phase = .loaded
            $0.favorites = [favorite]
        }
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
