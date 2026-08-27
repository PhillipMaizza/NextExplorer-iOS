import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Testing

@testable import FilesFeature

@MainActor
@Suite
struct FavoritesFeatureTests {
    private let serverURL = URL(string: "https://example.com")!

    private func makeFavorite(id: String = "1", path: String = "Documents", label: String? = nil) -> Favorite {
        Favorite(id: id, path: path, label: label, icon: "folder", color: nil, position: 0, createdAt: Date(), updatedAt: Date())
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
            $0.isLoading = true
        }
        await store.receive(\.favoritesResponse.success) {
            $0.isLoading = false
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
            $0.isLoading = true
        }
        await store.receive(\.favoritesResponse.success) {
            $0.isLoading = false
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
            $0.path[id: pathIDs[0]]?.isLoading = true
        }
        await store.receive(\.path[id: pathIDs[1]].refreshButtonTapped) {
            $0.path[id: pathIDs[1]]?.isLoading = true
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
    func sortOptionAndDirectionChangeTheDisplayedOrder() async {
        let alpha = makeFavorite(id: "1", path: "Alpha")
        let beta = makeFavorite(id: "2", path: "Beta")
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [beta, alpha]

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        #expect(store.state.displayedFavorites == [alpha, beta])

        await store.send(.sortDirectionChanged(.descending)) {
            $0.sortDirection = .descending
        }
        #expect(store.state.displayedFavorites == [beta, alpha])
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
            $0.isLoading = true
        }
        await store.receive(\.favoritesResponse.failure) {
            $0.isLoading = false
            $0.errorMessage = FilesClientError.sessionExpired.userMessage
        }
    }

    @Test
    func refreshAfterAFailureClearsThePreviousErrorMessage() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.errorMessage = "Couldn't reach the server."
        let favorite = makeFavorite()

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient.favorites = { _ in [favorite] }
        }

        await store.send(.refreshButtonTapped) {
            $0.isLoading = true
            $0.errorMessage = nil
        }
        await store.receive(\.favoritesResponse.success) {
            $0.isLoading = false
            $0.favorites = [favorite]
        }
    }

    // MARK: Edge cases

    @Test
    func onAppearIsANoOpWhenFavoritesAreAlreadyLoaded() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [makeFavorite()]

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        // No `filesClient` dependency overridden: a network call here would crash with
        // "Unimplemented", proving the guard skips a redundant fetch.
        await store.send(.onAppear)
    }

    @Test
    func onAppearIsANoOpWhenAnErrorIsAlreadyShowing() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.errorMessage = "Something went wrong."

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        await store.send(.onAppear)
    }

    @Test
    func onAppearIsANoOpWhileAlreadyLoading() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.isLoading = true

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
        }
    }
}
