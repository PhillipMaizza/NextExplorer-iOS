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
    func rowTappedOnAKnownBinaryFormatDoesNothing() async {
        let serverURL = URL(string: "https://example.com")!
        let file = FileItem(name: "installer.exe", path: "", dateModified: Date(), size: 10, kind: "exe")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        }

        // No `previewFile`/`fetchTextContent` override: a call to either would crash with
        // "Unimplemented," proving nothing is fetched for a format there's nothing to show.
        await store.send(.rowTapped(file))
    }

    @Test
    func rowTappedOnAnUnplayableStreamableContainerDoesNothing() async {
        let serverURL = URL(string: "https://example.com")!
        // `.webm` is `isStreamableMedia` (a video kind) but not `isNativelyPlayable`
        // (AVFoundation can't decode VP8/VP9) — regression test for a bug where `rowTapped`
        // guarded on `isPreviewable || isBrowsableArchive` instead of
        // `!isUnsupportedForPreview`, letting this slip through to `StreamingPreviewView`
        // with a URL it can't actually play.
        let file = FileItem(name: "clip.webm", path: "", dateModified: Date(), size: 10, kind: "webm")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        }

        await store.send(.rowTapped(file))
    }

    @Test
    func rowTappedOnANonBrowsableArchiveDoesNothing() async {
        let serverURL = URL(string: "https://example.com")!
        // `.zip`/`.rar` are `isBrowsableArchive` (see the dedicated test for those) — this
        // covers an archive kind neither `ZIPFoundation` nor `Unrar.swift` can list.
        let file = FileItem(name: "bundle.7z", path: "", dateModified: Date(), size: 10, kind: "7z")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        }

        await store.send(.rowTapped(file))
    }

    @Test
    func rowTappedOnATextFileFetchesItsContentAndEmitsNoDelegate() async {
        let serverURL = URL(string: "https://example.com")!
        let file = FileItem(name: "notes.txt", path: "", dateModified: Date(), size: 10, kind: "txt")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.fetchTextContent = { _, _ in "hello world" }
        }

        // Never emits `.openFolder` for a non-directory; sets `previewItem` immediately so
        // the viewer presents right away, and fetches text (not streamed, not downloaded via
        // `previewFile` — `.txt` isn't `isStreamableMedia` or `isPreviewableViaDownload`) in
        // the background.
        await store.send(.rowTapped(file)) {
            $0.previewItem = file
            $0.isLoadingTextContent = true
        }
        await store.receive(\.textContentResponse.success) {
            $0.isLoadingTextContent = false
            $0.textContent = "hello world"
        }
    }

    @Test
    func rowTappedOnAStreamableMediaFileSetsPreviewItemWithoutDownloading() async {
        let serverURL = URL(string: "https://example.com")!
        let video = FileItem(name: "clip.mp4", path: "", dateModified: Date(), size: 0, kind: "mp4")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        }

        // No `filesClient.previewFile` override: a call here would crash with
        // "Unimplemented," proving streamable media never downloads.
        await store.send(.rowTapped(video)) {
            $0.previewItem = video
        }
    }

    @Test
    func rowTappedOnABrowsableArchiveSetsPreviewItemWithoutDownloading() async {
        let serverURL = URL(string: "https://example.com")!
        let archive = FileItem(name: "bundle.zip", path: "", dateModified: Date(), size: 0, kind: "zip")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        }

        // No `filesClient.downloadRawFile`/`previewFile` override: a call here would crash
        // with "Unimplemented" — `ArchiveBrowserView` downloads and parses the archive itself.
        await store.send(.rowTapped(archive)) {
            $0.previewItem = archive
        }
    }

    @Test
    func rowTappedOnAnSVGDownloadsItForPreviewUnlikeOtherImages() async {
        let serverURL = URL(string: "https://example.com")!
        let file = FileItem(name: "logo.svg", path: "", dateModified: Date(), size: 0, kind: "svg")
        let fileURL = URL(fileURLWithPath: "/tmp/logo.svg")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.previewFile = { _, _ in fileURL }
        }

        // Unlike raster images (which set `previewItem` and load themselves in the gallery,
        // no reducer-driven fetch), SVGs go through the same download+QuickLook path as PDFs
        // — `UIImage`/`AsyncImage` can't rasterize them.
        await store.send(.rowTapped(file)) {
            $0.previewItem = file
            $0.isLoadingPreview = true
        }
        await store.receive(\.previewFileResponse.success) {
            $0.isLoadingPreview = false
            $0.previewFileURL = fileURL
        }
    }

    @Test
    func rowTappedOnATextFileFailingToFetchSurfacesAReadableErrorMessage() async {
        let serverURL = URL(string: "https://example.com")!
        let file = FileItem(name: "notes.txt", path: "", dateModified: Date(), size: 10, kind: "txt")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.fetchTextContent = { _, _ in throw FilesClientError.server(statusCode: 500) }
        }

        await store.send(.rowTapped(file)) {
            $0.previewItem = file
            $0.isLoadingTextContent = true
        }
        await store.receive(\.textContentResponse.failure) {
            $0.isLoadingTextContent = false
            $0.textEditorErrorMessage = FilesClientError.server(statusCode: 500).userMessage
        }
    }

    @Test
    func rowTappedOnAPDFDownloadsItForPreviewAndEmitsNoDelegate() async {
        let serverURL = URL(string: "https://example.com")!
        let file = FileItem(name: "report.pdf", path: "", dateModified: Date(), size: 10, kind: "pdf")
        let fileURL = URL(fileURLWithPath: "/tmp/report.pdf")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.previewFile = { _, _ in fileURL }
        }

        // PDFs are `isPreviewableViaDownload` (QuickLook), not text and not streamable.
        await store.send(.rowTapped(file)) {
            $0.previewItem = file
            $0.isLoadingPreview = true
        }
        await store.receive(\.previewFileResponse.success) {
            $0.isLoadingPreview = false
            $0.previewFileURL = fileURL
        }
    }

    @Test
    func rowTappedOnAWordDocumentDownloadsViaTheUnrestrictedDownloadEndpoint() async {
        let serverURL = URL(string: "https://example.com")!
        let file = FileItem(name: "report.docx", path: "", dateModified: Date(), size: 10, kind: "docx")
        let fileURL = URL(fileURLWithPath: "/tmp/report.docx")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.downloadRawFile = { _, _ in fileURL }
        }

        // No `filesClient.previewFile` override: a call here would crash with "Unimplemented"
        // — `.docx` isn't in `PREVIEWABLE_EXTENSIONS`, so it must go through
        // `downloadRawFile` (`POST /api/files/download`), not `GET /api/preview`.
        await store.send(.rowTapped(file)) {
            $0.previewItem = file
            $0.isLoadingPreview = true
        }
        await store.receive(\.previewFileResponse.success) {
            $0.isLoadingPreview = false
            $0.previewFileURL = fileURL
        }
    }

    @Test
    func textSaveTappedSavesContentAndUpdatesState() async {
        let serverURL = URL(string: "https://example.com")!
        let file = FileItem(name: "notes.txt", path: "", dateModified: Date(), size: 10, kind: "txt")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.previewItem = file
        state.textContent = "hello"

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.saveTextContent = { _, _, _ in }
        }

        await store.send(.textSaveTapped("hello world")) {
            $0.isSavingTextContent = true
        }
        await store.receive(\.textSaveResponse.success) {
            $0.isSavingTextContent = false
            $0.textContent = "hello world"
        }
    }

    @Test
    func textSaveTappedFailureSurfacesAReadableErrorMessage() async {
        let serverURL = URL(string: "https://example.com")!
        let file = FileItem(name: "notes.txt", path: "", dateModified: Date(), size: 10, kind: "txt")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.previewItem = file
        state.textContent = "hello"

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.saveTextContent = { _, _, _ in throw FilesClientError.server(statusCode: 500) }
        }

        await store.send(.textSaveTapped("hello world")) {
            $0.isSavingTextContent = true
        }
        await store.receive(\.textSaveResponse.failure) {
            $0.isSavingTextContent = false
            $0.textEditorErrorMessage = FilesClientError.server(statusCode: 500).userMessage
        }
    }

    @Test
    func textSaveTappedWithNoPreviewItemDoesNothing() async {
        let serverURL = URL(string: "https://example.com")!
        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        }

        await store.send(.textSaveTapped("orphaned content"))
    }

    @Test
    func previewDismissedClearsAllPreviewState() async {
        let serverURL = URL(string: "https://example.com")!
        let file = FileItem(name: "notes.txt", path: "", dateModified: Date(), size: 10, kind: "txt")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.previewItem = file
        state.previewFileURL = URL(fileURLWithPath: "/tmp/notes.txt")
        state.previewErrorMessage = "some error"
        state.isLoadingPreview = true

        let store = TestStore(initialState: state) {
            BrowseFeature()
        }

        await store.send(.previewDismissed) {
            $0.previewItem = nil
            $0.previewFileURL = nil
            $0.isLoadingPreview = false
            $0.previewErrorMessage = nil
        }
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

    // MARK: File actions — context menu routing

    @Test
    func renameTappedSetsTheRenameSheetItem() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 0, kind: "jpg")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        }

        await store.send(.renameTapped(item)) {
            $0.renameSheetItem = item
        }
    }

    @Test
    func deleteTappedSetsTheDeleteConfirmationItem() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 0, kind: "jpg")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        }

        await store.send(.deleteTapped(item)) {
            $0.deleteConfirmationItem = item
        }
    }

    // MARK: File actions — favorite toggle

    @Test
    func favoriteToggleOnAFileIsANoOpBecauseOnlyFoldersCanBeFavorited() async {
        // The real server 400s (`favoritesService.validatePath`) on anything that isn't a
        // directory — this mirrors that restriction client-side rather than round-tripping
        // to discover it.
        let serverURL = URL(string: "https://example.com")!
        let file = FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 0, kind: "jpg")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        }

        await store.send(.favoriteToggleButtonTapped(file))
    }

    @Test
    func favoriteToggleAddsAFavoriteWhenNotAlreadyFavorited() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "Vacation", path: "", dateModified: Date(), size: 0, kind: "directory")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.addFavorite = { _, path in
                Favorite(id: "1", path: path, label: nil, icon: "star", color: nil, position: 0, createdAt: Date(), updatedAt: Date())
            }
        }

        await store.send(.favoriteToggleButtonTapped(item))
        await store.receive(\.favoriteToggleResponse.success) {
            $0.favoritePaths = ["Vacation"]
        }
        await store.receive(.delegate(.favoritesChanged))
    }

    @Test
    func favoriteToggleRemovesAnExistingFavorite() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "Vacation", path: "", dateModified: Date(), size: 0, kind: "directory")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.favoritePaths = ["Vacation"]

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.removeFavorite = { _, _ in }
        }

        await store.send(.favoriteToggleButtonTapped(item))
        await store.receive(\.favoriteToggleResponse.success) {
            $0.favoritePaths = []
        }
        await store.receive(.delegate(.favoritesChanged))
    }

    @Test
    func favoriteToggleFailureSurfacesAReadableErrorMessage() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "Vacation", path: "", dateModified: Date(), size: 0, kind: "directory")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.addFavorite = { _, _ in throw FilesClientError.server(statusCode: 500) }
        }

        await store.send(.favoriteToggleButtonTapped(item))
        await store.receive(\.favoriteToggleResponse.failure) {
            $0.fileActionErrorMessage = FilesClientError.server(statusCode: 500).userMessage
        }
    }

    // MARK: File actions — rename

    @Test
    func renameCancelledClearsTheRenameSheetItem() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 0, kind: "jpg")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.renameSheetItem = item

        let store = TestStore(initialState: state) {
            BrowseFeature()
        }

        await store.send(.renameCancelled) {
            $0.renameSheetItem = nil
        }
    }

    @Test
    func renameConfirmedWithAnEmptyNameClearsTheSheetWithoutCallingTheServer() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 0, kind: "jpg")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.renameSheetItem = item

        let store = TestStore(initialState: state) {
            BrowseFeature()
        }

        await store.send(.renameConfirmed("   ")) {
            $0.renameSheetItem = nil
        }
    }

    @Test
    func renameConfirmedWithTheUnchangedNameClearsTheSheetWithoutCallingTheServer() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 0, kind: "jpg")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.renameSheetItem = item

        let store = TestStore(initialState: state) {
            BrowseFeature()
        }

        await store.send(.renameConfirmed("vacation.jpg")) {
            $0.renameSheetItem = nil
        }
    }

    @Test
    func renameConfirmedReplacesTheRenamedItemInPlace() async {
        let serverURL = URL(string: "https://example.com")!
        let original = FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 0, kind: "jpg")
        let renamed = FileItem(name: "beach.jpg", path: "", dateModified: Date(), size: 0, kind: "jpg")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.items = [original]
        state.renameSheetItem = original

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.renameItem = { _, _, _ in renamed }
        }

        await store.send(.renameConfirmed("beach.jpg")) {
            $0.isPerformingFileAction = true
        }
        await store.receive(\.renameResponse.success) {
            $0.isPerformingFileAction = false
            $0.renameSheetItem = nil
            $0.items = [renamed]
        }
    }

    @Test
    func renameConfirmedFailureSurfacesAReadableErrorMessageAndLeavesTheItemUnchanged() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 0, kind: "jpg")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.items = [item]
        state.renameSheetItem = item

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.renameItem = { _, _, _ in throw FilesClientError.server(statusCode: 409) }
        }

        await store.send(.renameConfirmed("taken.jpg")) {
            $0.isPerformingFileAction = true
        }
        await store.receive(\.renameResponse.failure) {
            $0.isPerformingFileAction = false
            $0.fileActionErrorMessage = FilesClientError.server(statusCode: 409).userMessage
        }
    }

    // MARK: File actions — delete

    @Test
    func deleteCancelledClearsTheDeleteConfirmationItem() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 0, kind: "jpg")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.deleteConfirmationItem = item

        let store = TestStore(initialState: state) {
            BrowseFeature()
        }

        await store.send(.deleteCancelled) {
            $0.deleteConfirmationItem = nil
        }
    }

    @Test
    func deleteConfirmedRemovesTheItemAndItsFavoriteOnSuccess() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 0, kind: "jpg")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.items = [item]
        state.favoritePaths = [item.id]
        state.deleteConfirmationItem = item

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.deleteItems = { _, _ in }
        }

        await store.send(.deleteConfirmed) {
            $0.deleteConfirmationItem = nil
            $0.isPerformingFileAction = true
        }
        await store.receive(\.deleteResponse.success) {
            $0.isPerformingFileAction = false
            $0.items = []
            $0.favoritePaths = []
        }
        await store.receive(.delegate(.favoritesChanged))
    }

    @Test
    func deleteConfirmedOfANonFavoritedItemDoesNotSignalTheFavoritesTabToRefresh() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 0, kind: "jpg")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.items = [item]
        state.deleteConfirmationItem = item

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.deleteItems = { _, _ in }
        }

        await store.send(.deleteConfirmed) {
            $0.deleteConfirmationItem = nil
            $0.isPerformingFileAction = true
        }
        await store.receive(\.deleteResponse.success) {
            $0.isPerformingFileAction = false
            $0.items = []
        }
    }

    @Test
    func deleteConfirmedFailureSurfacesAReadableErrorMessageAndKeepsTheItem() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "readonly.txt", path: "", dateModified: Date(), size: 0, kind: "txt")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.items = [item]
        state.deleteConfirmationItem = item

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.deleteItems = { _, _ in throw FilesClientError.server(statusCode: 403) }
        }

        await store.send(.deleteConfirmed) {
            $0.deleteConfirmationItem = nil
            $0.isPerformingFileAction = true
        }
        await store.receive(\.deleteResponse.failure) {
            $0.isPerformingFileAction = false
            $0.fileActionErrorMessage = FilesClientError.server(statusCode: 403).userMessage
        }
    }

    // MARK: File actions — extract/compress

    @Test
    func extractZipTappedAddsTheExtractedFolderOnSuccess() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "bundle.zip", path: "", dateModified: Date(), size: 0, kind: "zip")
        let extracted = FileItem(name: "bundle", path: "", dateModified: Date(), size: 0, kind: "directory")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.items = [item]

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.extractZip = { _, _ in extracted }
        }

        await store.send(.extractZipTapped(item)) {
            $0.isPerformingFileAction = true
            $0.fileActionProgressMessage = "Extracting…"
        }
        await store.receive(\.extractZipResponse.success) {
            $0.isPerformingFileAction = false
            $0.fileActionProgressMessage = nil
            $0.items = [item, extracted]
        }
    }

    @Test
    func extractZipTappedFailureSurfacesAReadableErrorMessage() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "bundle.zip", path: "", dateModified: Date(), size: 0, kind: "zip")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.extractZip = { _, _ in throw FilesClientError.server(statusCode: 415) }
        }

        await store.send(.extractZipTapped(item)) {
            $0.isPerformingFileAction = true
            $0.fileActionProgressMessage = "Extracting…"
        }
        await store.receive(\.extractZipResponse.failure) {
            $0.isPerformingFileAction = false
            $0.fileActionProgressMessage = nil
            $0.fileActionErrorMessage = FilesClientError.server(statusCode: 415).userMessage
        }
    }

    @Test
    func compressTappedAddsTheNewArchiveOnSuccess() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "Documents", path: "", dateModified: Date(), size: 0, kind: "directory")
        let compressed = FileItem(name: "Documents.zip", path: "", dateModified: Date(), size: 0, kind: "zip")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.items = [item]

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.compressItem = { _, _ in compressed }
        }

        await store.send(.compressTapped(item)) {
            $0.isPerformingFileAction = true
            $0.fileActionProgressMessage = "Compressing…"
        }
        await store.receive(\.compressResponse.success) {
            $0.isPerformingFileAction = false
            $0.fileActionProgressMessage = nil
            $0.items = [item, compressed]
        }
    }

    @Test
    func compressTappedFailureSurfacesAReadableErrorMessage() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "Documents", path: "", dateModified: Date(), size: 0, kind: "directory")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.compressItem = { _, _ in throw FilesClientError.server(statusCode: 403) }
        }

        await store.send(.compressTapped(item)) {
            $0.isPerformingFileAction = true
            $0.fileActionProgressMessage = "Compressing…"
        }
        await store.receive(\.compressResponse.failure) {
            $0.isPerformingFileAction = false
            $0.fileActionProgressMessage = nil
            $0.fileActionErrorMessage = FilesClientError.server(statusCode: 403).userMessage
        }
    }

    // MARK: File actions — get info

    @Test
    func infoTappedFetchesMetadataAndShowsIt() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "Photos", path: "", dateModified: Date(), size: 0, kind: "directory")
        let metadata = FileMetadata(
            path: "Photos",
            name: "Photos",
            kind: "directory",
            size: 4_096,
            dateModified: Date(timeIntervalSince1970: 1_800_000_000),
            dateCreated: Date(timeIntervalSince1970: 1_700_000_000),
            directory: FileMetadata.DirectorySummary(totalSize: 1_024, fileCount: 3, dirCount: 1, truncated: false)
        )

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.fetchMetadata = { _, _ in metadata }
        }

        await store.send(.infoTapped(item)) {
            $0.infoItem = item
            $0.isLoadingInfoMetadata = true
        }
        await store.receive(\.infoMetadataResponse.success) {
            $0.isLoadingInfoMetadata = false
            $0.infoMetadata = metadata
        }
    }

    @Test
    func infoTappedFailureSurfacesAReadableErrorMessage() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "notes.txt", path: "", dateModified: Date(), size: 0, kind: "txt")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.fetchMetadata = { _, _ in throw FilesClientError.server(statusCode: 403) }
        }

        await store.send(.infoTapped(item)) {
            $0.infoItem = item
            $0.isLoadingInfoMetadata = true
        }
        await store.receive(\.infoMetadataResponse.failure) {
            $0.isLoadingInfoMetadata = false
            $0.infoErrorMessage = FilesClientError.server(statusCode: 403).userMessage
        }
    }

    @Test
    func infoTappedOnADifferentItemWhileOneIsAlreadyShowingReplacesIt() async {
        let serverURL = URL(string: "https://example.com")!
        let first = FileItem(name: "Photos", path: "", dateModified: Date(), size: 0, kind: "directory")
        let second = FileItem(name: "Documents", path: "", dateModified: Date(), size: 0, kind: "directory")
        let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)
        let secondMetadata = FileMetadata(path: "Documents", name: "Documents", kind: "directory", size: 0, dateModified: fixedDate, dateCreated: fixedDate)
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.infoItem = first
        state.infoMetadata = FileMetadata(path: "Photos", name: "Photos", kind: "directory", size: 0, dateModified: fixedDate, dateCreated: fixedDate)
        state.infoErrorMessage = "stale error"

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.fetchMetadata = { _, _ in secondMetadata }
        }

        await store.send(.infoTapped(second)) {
            $0.infoItem = second
            $0.infoMetadata = nil
            $0.infoErrorMessage = nil
            $0.isLoadingInfoMetadata = true
        }
        await store.receive(\.infoMetadataResponse.success) {
            $0.isLoadingInfoMetadata = false
            $0.infoMetadata = secondMetadata
        }
    }

    @Test
    func infoDismissedClearsAllInfoState() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "Photos", path: "", dateModified: Date(), size: 0, kind: "directory")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.infoItem = item
        state.infoMetadata = FileMetadata(path: "Photos", name: "Photos", kind: "directory", size: 0, dateModified: Date(), dateCreated: Date())
        state.infoErrorMessage = "some error"
        state.isLoadingInfoMetadata = true

        let store = TestStore(initialState: state) {
            BrowseFeature()
        }

        await store.send(.infoDismissed) {
            $0.infoItem = nil
            $0.infoMetadata = nil
            $0.infoErrorMessage = nil
            $0.isLoadingInfoMetadata = false
        }
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
    func kindSortAscendingOrdersAlphabeticallyByExtensionWithinEachGroup() {
        let jpg = FileItem(name: "photo.jpg", path: "", dateModified: Date(), size: 0, kind: "jpg")
        let txt = FileItem(name: "notes.txt", path: "", dateModified: Date(), size: 0, kind: "txt")
        var state = makeState(showHiddenFiles: true, sortOption: .kind, sortDirection: .ascending)
        state.items = [txt, jpg]

        #expect(state.displayedItems.map(\.name) == ["photo.jpg", "notes.txt"])
    }

    @Test
    func kindSortDescendingOrdersReverseAlphabeticallyByExtensionWithinEachGroup() {
        let jpg = FileItem(name: "photo.jpg", path: "", dateModified: Date(), size: 0, kind: "jpg")
        let txt = FileItem(name: "notes.txt", path: "", dateModified: Date(), size: 0, kind: "txt")
        var state = makeState(showHiddenFiles: true, sortOption: .kind, sortDirection: .descending)
        state.items = [jpg, txt]

        #expect(state.displayedItems.map(\.name) == ["notes.txt", "photo.jpg"])
    }

    @Test
    func equalKindsDoNotCrashOrReorderUnpredictablyWhenDescending() {
        let first = FileItem(name: "a.txt", path: "", dateModified: Date(), size: 0, kind: "txt")
        let second = FileItem(name: "b.txt", path: "", dateModified: Date(), size: 0, kind: "txt")
        var state = makeState(showHiddenFiles: true, sortOption: .kind, sortDirection: .descending)
        state.items = [first, second]

        #expect(Set(state.displayedItems.map(\.name)) == ["a.txt", "b.txt"])
        #expect(state.displayedItems.count == 2)
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
