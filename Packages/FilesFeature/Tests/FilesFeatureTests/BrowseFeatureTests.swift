import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Testing

@testable import FilesFeature

@MainActor
@Suite
struct BrowseFeatureTests {
    @Test
    func onAppearLoadsRootItems() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "Docs", path: "", dateModified: Date(), size: 0, kind: "directory")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in
                BrowseResult(
                    items: [item],
                    access: FileAccess(canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true),
                    path: ""
                )
            }
            $0.filesClient.favorites = { _ in [] }
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }
        await store.receive(\.itemsResponse.success) {
            $0.isLoading = false
            $0.items = [item]
            $0.access = FileAccess(canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true)
        }
        await store.receive(\.favoritesResponse)
    }

    @Test
    func onAppearSurfacesABrowseFailureAsAReadableErrorMessage() async {
        let serverURL = URL(string: "https://example.com")!

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in throw FilesClientError.sessionExpired }
            $0.filesClient.favorites = { _ in [] }
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }
        await store.receive(\.itemsResponse.failure) {
            $0.isLoading = false
            $0.errorMessage = FilesClientError.sessionExpired.userMessage
        }
        await store.receive(\.favoritesResponse)
    }

    @Test
    func onAppearIsANoOpWhenItemsAreAlreadyLoaded() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "Docs", path: "", dateModified: Date(), size: 0, kind: "directory")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.items = [item]

        let store = TestStore(initialState: state) {
            BrowseFeature()
        }

        // No `filesClient` dependency overridden: a network call here would crash with
        // "Unimplemented", proving the guard in `.onAppear` really does skip re-fetching.
        await store.send(.onAppear)
    }

    @Test
    func onAppearIsANoOpWhenAnErrorIsAlreadyShowing() async {
        let serverURL = URL(string: "https://example.com")!
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.errorMessage = "Something went wrong."

        let store = TestStore(initialState: state) {
            BrowseFeature()
        }

        // Same guard, different branch: an existing error also blocks a redundant fetch
        // until the user explicitly pulls to refresh.
        await store.send(.onAppear)
    }

    @Test
    func onAppearIsANoOpWhileAlreadyLoading() async {
        let serverURL = URL(string: "https://example.com")!
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.isLoading = true

        let store = TestStore(initialState: state) {
            BrowseFeature()
        }

        await store.send(.onAppear)
    }

    @Test
    func refreshButtonTappedReloadsEvenWhenItemsAreAlreadyLoaded() async {
        let serverURL = URL(string: "https://example.com")!
        let existing = FileItem(name: "Old", path: "", dateModified: Date(), size: 0, kind: "directory")
        let refreshed = FileItem(name: "New", path: "", dateModified: Date(), size: 0, kind: "directory")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.items = [existing]

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in
                BrowseResult(items: [refreshed], access: FileAccess(canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true), path: "")
            }
            $0.filesClient.favorites = { _ in [] }
        }

        await store.send(.refreshButtonTapped) {
            $0.isLoading = true
        }
        await store.receive(\.itemsResponse.success) {
            $0.isLoading = false
            $0.items = [refreshed]
            $0.access = FileAccess(canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true)
        }
        await store.receive(\.favoritesResponse)
    }

    @Test
    func rowTappedOnDirectoryEmitsOpenFolderDelegate() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "Docs", path: "", dateModified: Date(), size: 0, kind: "directory")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        }

        await store.send(.rowTapped(item))
        await store.receive(.delegate(.openFolder(item)))
    }

    @Test
    func rowTappedOnAFileEmitsNoDelegate() async {
        let serverURL = URL(string: "https://example.com")!
        let file = FileItem(name: "notes.txt", path: "", dateModified: Date(), size: 10, kind: "txt")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        }

        // A file row's tap is a no-op at the reducer level: the app has no file viewer yet,
        // so this only guards against ever emitting `.openFolder` for a non-directory.
        await store.send(.rowTapped(file))
    }

    @Test
    func searchResultTappedOnADirectoryEmitsOpenPathDelegate() async {
        let serverURL = URL(string: "https://example.com")!
        let result = SearchResultItem(name: "Docs", path: "Photos", kind: "dir")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        }

        await store.send(.searchResultTapped(result))
        await store.receive(.delegate(.openPath(path: "Photos/Docs", title: "Docs")))
    }

    @Test
    func searchResultTappedOnAFileEmitsNoDelegate() async {
        let serverURL = URL(string: "https://example.com")!
        let result = SearchResultItem(name: "notes.txt", path: "", kind: "txt")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        }

        await store.send(.searchResultTapped(result))
    }

    @Test
    func favoritesResponseCollectsFavoritePaths() async {
        let serverURL = URL(string: "https://example.com")!
        let favorite = Favorite(
            id: "1", path: "Documents", label: nil, icon: "folder", color: nil,
            position: 0, createdAt: Date(), updatedAt: Date()
        )

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        }

        await store.send(.favoritesResponse([favorite])) {
            $0.favoritePaths = ["Documents"]
        }
    }

    @Test
    func favoritesResponseWithNoFavoritesClearsFavoritePaths() async {
        let serverURL = URL(string: "https://example.com")!
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.favoritePaths = ["Documents"]

        let store = TestStore(initialState: state) {
            BrowseFeature()
        }

        await store.send(.favoritesResponse([])) {
            $0.favoritePaths = []
        }
    }

    @Test
    func sortOptionChangedUpdatesState() async {
        let serverURL = URL(string: "https://example.com")!

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        }

        await store.send(.sortOptionChanged(.dateModified)) {
            $0.sortOption = .dateModified
        }
    }

    @Test
    func sortDirectionChangedUpdatesState() async {
        let serverURL = URL(string: "https://example.com")!

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        }

        await store.send(.sortDirectionChanged(.descending)) {
            $0.sortDirection = .descending
        }
    }

    @Test
    func breadcrumbTappedEmitsOpenPathDelegateWithTheTappedSegment() async {
        let serverURL = URL(string: "https://example.com")!

        let store = TestStore(
            initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos/Documents", title: "Documents")
        ) {
            BrowseFeature()
        }

        await store.send(.breadcrumbTapped(path: "Photos", title: "Photos"))
        await store.receive(.delegate(.openPath(path: "Photos", title: "Photos")))
    }

    @Test
    func breadcrumbTappedOnHomeEmitsOpenPathDelegateWithAnEmptyPath() async {
        let serverURL = URL(string: "https://example.com")!

        let store = TestStore(
            initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos", title: "Photos")
        ) {
            BrowseFeature()
        }

        await store.send(.breadcrumbTapped(path: "", title: "Home"))
        await store.receive(.delegate(.openPath(path: "", title: "Home")))
    }

    // MARK: - Search: "This Folder" scope (client-side fuzzy match, no network)

    @Test
    func searchInThisFolderReturnsFuzzyMatchesFromAlreadyLoadedItems() async {
        let serverURL = URL(string: "https://example.com")!
        let match = FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 0, kind: "jpg")
        let nonMatch = FileItem(name: "notes.txt", path: "", dateModified: Date(), size: 0, kind: "txt")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.items = [match, nonMatch]
        let clock = TestClock()

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.continuousClock = clock
        }

        await store.send(.searchQueryChanged("vac")) {
            $0.searchQuery = "vac"
        }
        await clock.advance(by: .milliseconds(50))
        await store.receive(\.searchResultsResponse.success) {
            $0.searchResults = [SearchResultItem(name: "vacation.jpg", path: "", kind: "jpg")]
        }
    }

    @Test
    func clearingTheSearchQueryCancelsAnInFlightSearchAndClearsResults() async {
        let serverURL = URL(string: "https://example.com")!
        let match = FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 0, kind: "jpg")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.items = [match]
        let clock = TestClock()

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.continuousClock = clock
        }

        await store.send(.searchQueryChanged("vac")) {
            $0.searchQuery = "vac"
        }
        // Backspacing to empty before the settle delay elapses must cancel that effect
        // outright, not just ignore its eventual result.
        await store.send(.searchQueryChanged("")) {
            $0.searchQuery = ""
        }
        await clock.advance(by: .seconds(1))
        await store.finish()
    }

    @Test
    func rapidRetypingOnlyDeliversResultsForTheLatestQuery() async {
        // Regression: `.cancellable(id: CancelID.search, cancelInFlight: true)` must cancel
        // the previous keystroke's settle-delay effect, or a fast backspace/retype could
        // flash a stale intermediate result set.
        let serverURL = URL(string: "https://example.com")!
        let match = FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 0, kind: "jpg")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.items = [match]
        let clock = TestClock()

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.continuousClock = clock
        }

        await store.send(.searchQueryChanged("v")) {
            $0.searchQuery = "v"
        }
        await store.send(.searchQueryChanged("va")) {
            $0.searchQuery = "va"
        }
        await clock.advance(by: .milliseconds(50))
        await store.receive(\.searchResultsResponse.success) {
            $0.searchResults = [SearchResultItem(name: "vacation.jpg", path: "", kind: "jpg")]
        }
    }

    // MARK: - Search: "Everywhere" scope (network search, debounced)

    @Test
    func searchEverywhereHitsTheNetworkAfterTheDebounceAndSurfacesResults() async {
        let serverURL = URL(string: "https://example.com")!
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.searchScope = .everywhere
        let result = SearchResultItem(name: "vacation.jpg", path: "Photos", kind: "jpg")
        let clock = TestClock()

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.filesClient.search = { _, _, _, _ in [result] }
        }

        await store.send(.searchQueryChanged("vac")) {
            $0.searchQuery = "vac"
            $0.isSearchingEverywhere = true
        }
        await clock.advance(by: .milliseconds(150))
        await store.receive(\.searchResultsResponse.success) {
            $0.isSearchingEverywhere = false
            $0.searchResults = [result]
        }
    }

    @Test
    func searchEverywhereSurfacesANetworkFailureAsEmptyResultsRatherThanCrashing() async {
        let serverURL = URL(string: "https://example.com")!
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.searchScope = .everywhere
        let clock = TestClock()

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.filesClient.search = { _, _, _, _ in throw FilesClientError.rateLimited }
        }

        await store.send(.searchQueryChanged("vac")) {
            $0.searchQuery = "vac"
            $0.isSearchingEverywhere = true
        }
        await clock.advance(by: .milliseconds(150))
        await store.receive(\.searchResultsResponse.failure) {
            $0.isSearchingEverywhere = false
            $0.searchResults = []
        }
    }

    @Test
    func changingScopeToEverywhereWithAnExistingQueryTriggersANetworkSearch() async {
        let serverURL = URL(string: "https://example.com")!
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.searchQuery = "vac"
        let result = SearchResultItem(name: "vacation.jpg", path: "Photos", kind: "jpg")
        let clock = TestClock()

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.filesClient.search = { _, _, _, _ in [result] }
        }

        await store.send(.searchScopeChanged(.everywhere)) {
            $0.searchScope = .everywhere
            $0.isSearchingEverywhere = true
        }
        await clock.advance(by: .milliseconds(150))
        await store.receive(\.searchResultsResponse.success) {
            $0.isSearchingEverywhere = false
            $0.searchResults = [result]
        }
    }

    // MARK: - Edge cases

    @Test
    func onAppearWithAnEmptyFolderLoadsSuccessfullyWithNoItems() async {
        let serverURL = URL(string: "https://example.com")!
        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in
                BrowseResult(
                    items: [],
                    access: FileAccess(canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true),
                    path: ""
                )
            }
            $0.filesClient.favorites = { _ in [] }
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }
        await store.receive(\.itemsResponse.success) {
            $0.isLoading = false
            $0.items = []
            $0.access = FileAccess(canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true)
        }
        await store.receive(\.favoritesResponse)
    }

    @Test
    func breadcrumbTappedOnADeeplyNestedPathEmitsTheFullPath() async {
        let serverURL = URL(string: "https://example.com")!
        let deepPath = "A/B/C/D/E/F/G"

        let store = TestStore(
            initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: deepPath, title: "G")
        ) {
            BrowseFeature()
        }

        await store.send(.breadcrumbTapped(path: deepPath, title: "G"))
        await store.receive(.delegate(.openPath(path: deepPath, title: "G")))
    }

    @Test
    func rowTappedOnAFolderWithSpecialCharactersInItsNameStillEmitsOpenFolder() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "日本語 & #tag", path: "", dateModified: Date(), size: 0, kind: "directory")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        }

        await store.send(.rowTapped(item))
        await store.receive(.delegate(.openFolder(item)))
    }

    @Test
    func searchResultTappedOnADirectoryAtTheRootBuildsThePathFromAnEmptyParent() async {
        let serverURL = URL(string: "https://example.com")!
        let result = SearchResultItem(name: "Docs", path: "", kind: "dir")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        }

        await store.send(.searchResultTapped(result))
        await store.receive(.delegate(.openPath(path: "Docs", title: "Docs")))
    }
}

// MARK: - `BrowseFeature.State` display logic

/// These test the pure `displayedItems`/`displayedSearchResults` computed properties directly
/// against hand-built state, rather than through the reducer: sorting/filtering is derived
/// state, not something any action produces, so there's no meaningful action to send.
@MainActor
@Suite
struct BrowseFeatureDisplayedItemsTests {
    private let serverURL = URL(string: "https://example.com")!

    private func makeState(
        showHiddenFiles: Bool,
        sortOption: BrowseFeature.SortOption = .name,
        sortDirection: BrowseFeature.SortDirection = .ascending
    ) -> BrowseFeature.State {
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        // `.inMemory` shared state is a process-wide registry keyed by string, so every test
        // that touches it resets to a known value first rather than assuming a clean default.
        state.$preferences.withLock { $0 = UserPreferences(showHiddenFiles: showHiddenFiles, showThumbnails: true) }
        state.sortOption = sortOption
        state.sortDirection = sortDirection
        return state
    }

    @Test
    func foldersAlwaysSortBeforeFilesRegardlessOfSortOption() {
        let file = FileItem(name: "aaa.txt", path: "", dateModified: Date(), size: 0, kind: "txt")
        let folder = FileItem(name: "zzz", path: "", dateModified: Date(), size: 0, kind: "directory")
        var state = makeState(showHiddenFiles: true)
        state.items = [file, folder]

        #expect(state.displayedItems.map(\.name) == ["zzz", "aaa.txt"])
    }

    @Test
    func foldersAlwaysSortBeforeFilesEvenWhenDescending() {
        let file = FileItem(name: "aaa.txt", path: "", dateModified: Date(), size: 0, kind: "txt")
        let folder = FileItem(name: "zzz", path: "", dateModified: Date(), size: 0, kind: "directory")
        var state = makeState(showHiddenFiles: true, sortDirection: .descending)
        state.items = [file, folder]

        #expect(state.displayedItems.map(\.name) == ["zzz", "aaa.txt"])
    }

    @Test
    func nameSortAscendingOrdersAtoZWithinEachGroup() {
        let fileB = FileItem(name: "b.txt", path: "", dateModified: Date(), size: 0, kind: "txt")
        let fileA = FileItem(name: "a.txt", path: "", dateModified: Date(), size: 0, kind: "txt")
        var state = makeState(showHiddenFiles: true, sortOption: .name, sortDirection: .ascending)
        state.items = [fileB, fileA]

        #expect(state.displayedItems.map(\.name) == ["a.txt", "b.txt"])
    }

    @Test
    func nameSortDescendingOrdersZtoAWithinEachGroup() {
        let fileB = FileItem(name: "b.txt", path: "", dateModified: Date(), size: 0, kind: "txt")
        let fileA = FileItem(name: "a.txt", path: "", dateModified: Date(), size: 0, kind: "txt")
        var state = makeState(showHiddenFiles: true, sortOption: .name, sortDirection: .descending)
        state.items = [fileA, fileB]

        #expect(state.displayedItems.map(\.name) == ["b.txt", "a.txt"])
    }

    @Test
    func sizeSortAscendingOrdersSmallestFirstWithinEachGroup() {
        let small = FileItem(name: "small.txt", path: "", dateModified: Date(), size: 10, kind: "txt")
        let large = FileItem(name: "large.txt", path: "", dateModified: Date(), size: 1_000, kind: "txt")
        var state = makeState(showHiddenFiles: true, sortOption: .size, sortDirection: .ascending)
        state.items = [large, small]

        #expect(state.displayedItems.map(\.name) == ["small.txt", "large.txt"])
    }

    @Test
    func sizeSortDescendingOrdersLargestFirstWithinEachGroup() {
        let small = FileItem(name: "small.txt", path: "", dateModified: Date(), size: 10, kind: "txt")
        let large = FileItem(name: "large.txt", path: "", dateModified: Date(), size: 1_000, kind: "txt")
        var state = makeState(showHiddenFiles: true, sortOption: .size, sortDirection: .descending)
        state.items = [small, large]

        #expect(state.displayedItems.map(\.name) == ["large.txt", "small.txt"])
    }

    @Test
    func dateModifiedSortAscendingOrdersOldestFirstWithinEachGroup() {
        let older = FileItem(name: "older.txt", path: "", dateModified: Date(timeIntervalSince1970: 0), size: 0, kind: "txt")
        let newer = FileItem(name: "newer.txt", path: "", dateModified: Date(timeIntervalSince1970: 1_000), size: 0, kind: "txt")
        var state = makeState(showHiddenFiles: true, sortOption: .dateModified, sortDirection: .ascending)
        state.items = [newer, older]

        #expect(state.displayedItems.map(\.name) == ["older.txt", "newer.txt"])
    }

    @Test
    func dateModifiedSortDescendingOrdersMostRecentFirstWithinEachGroup() {
        let older = FileItem(name: "older.txt", path: "", dateModified: Date(timeIntervalSince1970: 0), size: 0, kind: "txt")
        let newer = FileItem(name: "newer.txt", path: "", dateModified: Date(timeIntervalSince1970: 1_000), size: 0, kind: "txt")
        var state = makeState(showHiddenFiles: true, sortOption: .dateModified, sortDirection: .descending)
        state.items = [older, newer]

        #expect(state.displayedItems.map(\.name) == ["newer.txt", "older.txt"])
    }

    @Test
    func equalSizesDoNotCrashOrReorderUnpredictablyWhenDescending() {
        // Regression: negating a `<` comparator to build `>` breaks `sorted`'s strict-weak-
        // ordering requirement exactly when two elements compare equal. This only asserts the
        // membership is preserved (no crash, no duplication/loss), not a specific tie order.
        let first = FileItem(name: "a.txt", path: "", dateModified: Date(), size: 100, kind: "txt")
        let second = FileItem(name: "b.txt", path: "", dateModified: Date(), size: 100, kind: "txt")
        var state = makeState(showHiddenFiles: true, sortOption: .size, sortDirection: .descending)
        state.items = [first, second]

        #expect(Set(state.displayedItems.map(\.name)) == ["a.txt", "b.txt"])
        #expect(state.displayedItems.count == 2)
    }

    @Test
    func hiddenFilesAreDroppedWhenThePreferenceIsOff() {
        let visible = FileItem(name: "visible.txt", path: "", dateModified: Date(), size: 0, kind: "txt")
        let hidden = FileItem(name: ".hidden", path: "", dateModified: Date(), size: 0, kind: "txt")
        var state = makeState(showHiddenFiles: false)
        state.items = [visible, hidden]

        #expect(state.displayedItems.map(\.name) == ["visible.txt"])
    }

    @Test
    func hiddenFilesAreKeptWhenThePreferenceIsOn() {
        let visible = FileItem(name: "visible.txt", path: "", dateModified: Date(), size: 0, kind: "txt")
        let hidden = FileItem(name: ".hidden", path: "", dateModified: Date(), size: 0, kind: "txt")
        var state = makeState(showHiddenFiles: true)
        state.items = [visible, hidden]

        #expect(Set(state.displayedItems.map(\.name)) == ["visible.txt", ".hidden"])
    }

    @Test
    func displayedItemsIsEmptyWhenThereAreNoItems() {
        let state = makeState(showHiddenFiles: true)
        #expect(state.displayedItems.isEmpty)
    }

    @Test
    func displayedSearchResultsIsNilWhenNoSearchHasRun() {
        let state = makeState(showHiddenFiles: true)
        #expect(state.displayedSearchResults == nil)
    }

    @Test
    func displayedSearchResultsDropsHiddenEntriesWhenThePreferenceIsOff() {
        let visible = SearchResultItem(name: "visible.txt", path: "", kind: "txt")
        let hidden = SearchResultItem(name: ".hidden", path: "", kind: "txt")
        var state = makeState(showHiddenFiles: false)
        state.searchResults = [visible, hidden]

        #expect(state.displayedSearchResults?.map(\.name) == ["visible.txt"])
    }

    @Test
    func displayedSearchResultsKeepsHiddenEntriesWhenThePreferenceIsOn() {
        let visible = SearchResultItem(name: "visible.txt", path: "", kind: "txt")
        let hidden = SearchResultItem(name: ".hidden", path: "", kind: "txt")
        var state = makeState(showHiddenFiles: true)
        state.searchResults = [visible, hidden]

        #expect(Set(state.displayedSearchResults?.map(\.name) ?? []) == ["visible.txt", ".hidden"])
    }

    @Test
    func displayedSearchResultsIsEmptyWhenSearchReturnedNoMatches() {
        var state = makeState(showHiddenFiles: true)
        state.searchResults = []

        #expect(state.displayedSearchResults?.isEmpty == true)
    }
}
