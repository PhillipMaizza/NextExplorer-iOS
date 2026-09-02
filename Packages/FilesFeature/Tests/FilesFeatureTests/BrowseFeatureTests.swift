import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Localization
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
            $0.phase = .loading
        }
        await store.receive(\.itemsResponse.success) {
            $0.phase = .loaded
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
            $0.phase = .loading
        }
        await store.receive(\.itemsResponse.failure) {
            $0.phase = .failed(FilesClientError.sessionExpired.userMessage)
        }
        await store.receive(\.favoritesResponse)
    }

    @Test
    func onAppearIsANoOpWhenItemsAreAlreadyLoaded() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "Docs", path: "", dateModified: Date(), size: 0, kind: "directory")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.items = [item]
        state.phase = .loaded

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
        state.phase = .failed("Something went wrong.")

        let store = TestStore(initialState: state) {
            BrowseFeature()
        }

        // Same guard, different branch: a completed load (here, one that errored) blocks a
        // redundant fetch until the user explicitly pulls to refresh.
        await store.send(.onAppear)
    }

    @Test
    func onAppearIsANoOpWhileAlreadyLoading() async {
        let serverURL = URL(string: "https://example.com")!
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.phase = .loading

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
            $0.phase = .loading
        }
        await store.receive(\.itemsResponse.success) {
            $0.phase = .loaded
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
    func rowTappedOnAKnownBinaryFormatPresentsTheUnsupportedPreviewAndFetchesNothing() async {
        let serverURL = URL(string: "https://example.com")!
        let file = FileItem(name: "installer.exe", path: "", dateModified: Date(), size: 10, kind: "exe")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        }

        // No `previewFile`/`fetchTextContent` override: a call to either would crash with
        // "Unimplemented," proving nothing is fetched for a format there's nothing to show.
        await store.send(.rowTapped(file)) { $0.previewItem = file }
    }

    @Test
    func rowTappedOnAnUnplayableStreamableContainerPresentsTheUnsupportedPreview() async {
        let serverURL = URL(string: "https://example.com")!
        // `.webm` is `isStreamableMedia` (a video kind) but not `isNativelyPlayable`
        // (AVFoundation can't decode VP8/VP9) — regression test for a bug where `rowTapped`
        // guarded on `isPreviewable || isBrowsableArchive` instead of
        // `!isUnsupportedForPreview`, letting this slip through to `StreamingPreviewView`
        // with a URL it can't actually play. It now lands on `UnsupportedFilePreviewView`.
        let file = FileItem(name: "clip.webm", path: "", dateModified: Date(), size: 10, kind: "webm")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        }

        await store.send(.rowTapped(file)) { $0.previewItem = file }
    }

    @Test
    func rowTappedOnANonBrowsableArchivePresentsTheUnsupportedPreview() async {
        let serverURL = URL(string: "https://example.com")!
        // `.zip`/`.rar` are `isBrowsableArchive` (see the dedicated test for those) — this
        // covers an archive kind neither `ZIPFoundation` nor `Unrar.swift` can list.
        let file = FileItem(name: "bundle.7z", path: "", dateModified: Date(), size: 10, kind: "7z")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        }

        await store.send(.rowTapped(file)) { $0.previewItem = file }
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
    func rowTappedOnAGoogleDriveStubOpensItsLinkInsteadOfPreviewing() async {
        let serverURL = URL(string: "https://example.com")!
        let stub = FileItem(name: "Budget.gsheet", path: "", dateModified: Date(), size: 120, kind: "gsheet")
        let opened = LockIsolated<URL?>(nil)

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.fetchTextContent = { _, _ in
                #"{"url": "https://docs.google.com/spreadsheets/d/ABC/edit"}"#
            }
            $0.openURL = .init { url in opened.setValue(url); return true }
        }

        await store.send(.rowTapped(stub))
        await store.receive(\.googleDocsPointerResponse)

        #expect(store.state.previewItem == nil)
        #expect(opened.value?.absoluteString == "https://docs.google.com/spreadsheets/d/ABC/edit")
    }

    @Test
    func rowTappedOnAnUnreadableGoogleDriveStubFallsBackToTheTextViewer() async {
        let serverURL = URL(string: "https://example.com")!
        let stub = FileItem(name: "broken.gdoc", path: "", dateModified: Date(), size: 5, kind: "gdoc")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.fetchTextContent = { _, _ in "not json" }
            $0.openURL = .init { _ in true }
        }
        store.exhaustivity = .off

        await store.send(.rowTapped(stub))
        await store.receive(\.googleDocsPointerResponse) {
            $0.previewItem = stub
            $0.isLoadingTextContent = true
        }
        await store.receive(\.textContentResponse.success)
    }

    @Test
    func openInBrowserHandsTheRawFileURLToSafari() async {
        let serverURL = URL(string: "https://example.com")!
        let page = FileItem(name: "index.html", path: "site", dateModified: Date(), size: 40, kind: "html")
        let opened = LockIsolated<URL?>(nil)

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "site", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.openURL = .init { url in opened.setValue(url); return true }
        }

        await store.send(.openInBrowserTapped(page))
        #expect(opened.value == URL(string: "https://example.com/api/raw?path=site/index.html"))
        #expect(store.state.previewItem == nil)
    }

    @Test
    func openInBrowserIsIgnoredForNonHTMLFiles() async {
        let serverURL = URL(string: "https://example.com")!
        let file = FileItem(name: "notes.txt", path: "", dateModified: Date(), size: 4, kind: "txt")
        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        }

        await store.send(.openInBrowserTapped(file))
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
    func favoritesResponseCollectsFavoritePaths() async {
        let serverURL = URL(string: "https://example.com")!
        let favorite = Favorite(
            id: "1", path: "Documents", label: nil, icon: "folder", color: nil,
            position: 0, createdAt: Date(), updatedAt: Date()
        )

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.prefetchDirectory = { _, _ in }
        }
        store.exhaustivity = .off

        await store.send(.favoritesResponse([favorite])) {
            $0.favoritePaths = ["Documents"]
        }
        await store.finish()
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
            $0.fileActionErrorMessage = "Couldn't search. Check your connection and try again."
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
            $0.phase = .loading
        }
        await store.receive(\.itemsResponse.success) {
            $0.phase = .loaded
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
    func deleteTappedSetsTheDeleteConfirmationItemAndChecksShareImpact() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 0, kind: "jpg")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.deleteImpact = { _, items in
                #expect(items.map(\.name) == ["vacation.jpg"])
                return DeleteImpact(shareCount: 2)
            }
        }

        await store.send(.deleteTapped(item)) {
            $0.deleteConfirmationItem = item
            $0.deleteImpactCheck = .checking
        }
        await store.receive(\.deleteImpactResponse.success) {
            $0.deleteImpactCheck = .loaded(DeleteImpact(shareCount: 2))
        }
    }

    @Test
    func deleteTappedTreatsAFailedShareImpactCheckAsUnavailable() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 0, kind: "jpg")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.deleteImpact = { _, _ in throw FilesClientError.network("offline") }
        }

        await store.send(.deleteTapped(item)) {
            $0.deleteConfirmationItem = item
            $0.deleteImpactCheck = .checking
        }
        await store.receive(\.deleteImpactResponse.failure) {
            $0.deleteImpactCheck = .unavailable
        }
    }

    @Test
    func bulkDeleteTappedChecksShareImpactForEverySelectedItem() async {
        let serverURL = URL(string: "https://example.com")!
        let one = FileItem(name: "a.txt", path: "", dateModified: Date(), size: 0, kind: "txt")
        let two = FileItem(name: "b.txt", path: "", dateModified: Date(), size: 0, kind: "txt")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.items = [one, two]
        state.selectedItemIDs = [one.id, two.id]

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.deleteImpact = { _, items in
                #expect(Set(items.map(\.name)) == ["a.txt", "b.txt"])
                return DeleteImpact(shareCount: 3)
            }
        }

        await store.send(.bulkDeleteTapped) {
            $0.bulkDeleteConfirmationIsPresented = true
            $0.deleteImpactCheck = .checking
        }
        await store.receive(\.deleteImpactResponse.success) {
            $0.deleteImpactCheck = .loaded(DeleteImpact(shareCount: 3))
        }
    }

    // MARK: File actions — favorite toggle

    @Test
    func anInPlaceMutationWritesTheCorrectedListingThroughToTheCache() async {
        let serverURL = URL(string: "https://example.com")!
        let cache = DirectoryCacheStore.inMemory()
        let existing = FileItem(name: "Old", path: "Docs", dateModified: Date(), size: 0, kind: "txt")
        let newFolder = FileItem(name: "Reports", path: "Docs", dateModified: Date(), size: 0, kind: "directory")

        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "Docs", title: "Docs")
        state.access = FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true)
        state.items = [existing]

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.directoryCacheStore = cache
            $0.date = .constant(Date(timeIntervalSince1970: 1_000))
        }
        store.exhaustivity = .off

        // A create edits this folder in place; the on-disk cache must now hold the new listing
        // so an offline revisit shows the folder, not the pre-create state.
        await store.send(.newFolderResponse(.success(newFolder)))

        let cached = cache.read(serverURL: serverURL, path: "Docs")
        #expect(cached?.items.contains(where: { $0.id == newFolder.id }) == true)
        #expect(cached?.etag == nil, "etag must be nil so the next online browse revalidates cleanly")
    }

    @Test
    func rapidFavoriteDoubleTapFiresASingleRequest() async {
        let serverURL = URL(string: "https://example.com")!
        let dir = FileItem(name: "Vacation", path: "", dateModified: Date(), size: 0, kind: "directory")
        let clock = TestClock()
        let completions = LockIsolated(0)

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.addFavorite = { _, path in
                try await clock.sleep(for: .seconds(1))
                completions.withValue { $0 += 1 }
                return Favorite(id: "1", path: path, label: nil, icon: "star", color: nil, position: 0, createdAt: Date(), updatedAt: Date())
            }
        }
        store.exhaustivity = .off

        // Two taps on the same star before the first resolves: the second supersedes the first.
        await store.send(.favoriteToggleButtonTapped(dir))
        await store.send(.favoriteToggleButtonTapped(dir))
        await clock.advance(by: .seconds(2))
        await store.receive(\.favoriteToggleResponse.success)

        #expect(completions.value == 1)
    }

    @Test
    func bulkDownloadWhileOneIsAlreadyInFlightIsIgnored() async {
        let serverURL = URL(string: "https://example.com")!
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.isBulkActionInFlight = true

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.downloadRawFile = { _, _ in
                Issue.record("a second bulk download must not start while one is in flight")
                return URL(fileURLWithPath: "/tmp/x")
            }
        }

        // No state change, no effect: the re-entry guard swallows it.
        await store.send(.bulkDownloadTapped(.documents, removeArchiveAfterDownload: false))
    }

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

    @Test
    func searchResultTappedOnAFileOpensThePreviewViaRowTapped() async {
        let serverURL = URL(string: "https://example.com")!
        let store = TestStore(
            initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        ) {
            BrowseFeature()
        }
        // `searchResultTapped` stamps `Date()` into the synthesized `FileItem`, so match on
        // the fields it actually derives rather than the whole value.
        store.exhaustivity = .off

        await store.send(.searchResultTapped(SearchResultItem(name: "clip.mp4", path: "Media", kind: "file")))
        await store.receive(\.rowTapped)
        #expect(store.state.previewItem?.name == "clip.mp4")
        #expect(store.state.previewItem?.path == "Media")
        #expect(store.state.previewItem?.kind == "mp4")
    }

    // MARK: File actions — new folder

    @Test
    func newFolderTappedOpensTheSheetAndCancelledClosesIt() async {
        let serverURL = URL(string: "https://example.com")!
        let store = TestStore(
            initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "Docs", title: "Docs")
        ) {
            BrowseFeature()
        }

        await store.send(.newFolderTapped) {
            $0.isNewFolderSheetPresented = true
        }
        await store.send(.newFolderCancelled) {
            $0.isNewFolderSheetPresented = false
        }
    }

    @Test
    func newFolderConfirmedWithABlankNameClosesTheSheetWithoutCallingTheServer() async {
        let serverURL = URL(string: "https://example.com")!
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "Docs", title: "Docs")
        state.isNewFolderSheetPresented = true

        let store = TestStore(initialState: state) {
            BrowseFeature()
        }

        await store.send(.newFolderConfirmed("   ")) {
            $0.isNewFolderSheetPresented = false
        }
    }

    @Test
    func newFolderConfirmedAppendsTheCreatedFolderOnSuccess() async {
        let serverURL = URL(string: "https://example.com")!
        let existing = FileItem(name: "old.txt", path: "Docs", dateModified: Date(), size: 0, kind: "txt")
        let created = FileItem(name: "Reports", path: "Docs", dateModified: Date(), size: 0, kind: "directory")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "Docs", title: "Docs")
        state.items = [existing]
        state.isNewFolderSheetPresented = true

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.createFolder = { _, _, _ in created }
        }

        await store.send(.newFolderConfirmed("Reports")) {
            $0.isPerformingFileAction = true
        }
        await store.receive(\.newFolderResponse.success) {
            $0.isPerformingFileAction = false
            $0.isNewFolderSheetPresented = false
            $0.items = [existing, created]
        }
    }

    @Test
    func newFolderConfirmedFailureSurfacesAReadableErrorMessage() async {
        let serverURL = URL(string: "https://example.com")!
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "Docs", title: "Docs")
        state.isNewFolderSheetPresented = true

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.createFolder = { _, _, _ in throw FilesClientError.server(statusCode: 403) }
        }

        await store.send(.newFolderConfirmed("Reports")) {
            $0.isPerformingFileAction = true
        }
        await store.receive(\.newFolderResponse.failure) {
            $0.isPerformingFileAction = false
            // The sheet stays open so the user can correct the name and retry.
            $0.fileActionErrorMessage = FilesClientError.server(statusCode: 403).userMessage
        }
    }

    // MARK: File actions — delete

    @Test
    func deleteCancelledClearsTheDeleteConfirmationItemAndShareImpactCheck() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 0, kind: "jpg")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.deleteConfirmationItem = item
        state.deleteImpactCheck = .loaded(DeleteImpact(shareCount: 1))

        let store = TestStore(initialState: state) {
            BrowseFeature()
        }

        await store.send(.deleteCancelled) {
            $0.deleteConfirmationItem = nil
            $0.deleteImpactCheck = .idle
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
    func deleteConfirmedFromPreviewDismissesTheCoverThenDeletesAfterASettle() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 0, kind: "jpg")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.items = [item]
        state.previewItem = item
        state.deleteConfirmationItem = item

        let clock = TestClock()
        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.filesClient.deleteItems = { _, _ in }
        }

        await store.send(.deleteConfirmedFromPreview) {
            $0.deleteConfirmationItem = nil
            $0.isPerformingFileAction = true
        }
        // Cover closes right away; the request waits for the settle so the row animates out
        // on the list, not mid transition.
        await store.receive(.previewDismissed) {
            $0.previewItem = nil
        }
        await clock.advance(by: .milliseconds(350))
        await store.receive(\.deleteResponse.success) {
            $0.isPerformingFileAction = false
            $0.items = []
        }
    }

    @Test
    func renameConfirmedWhilePreviewingRepointsTheCoverAtTheRenamedItemWithoutDismissing() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 0, kind: "jpg")
        let renamed = FileItem(name: "beach.jpg", path: "", dateModified: Date(), size: 0, kind: "jpg")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.items = [item]
        state.previewItem = item
        state.renameSheetItem = item

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
            $0.previewItem = renamed
        }
    }

    @Test
    func openDownloadsFromPreviewDismissesTheCoverThenSwitchesTabsAfterASettle() async {
        let serverURL = URL(string: "https://example.com")!
        let file = FileItem(name: "archive.bin", path: "", dateModified: Date(), size: 0, kind: "bin")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.previewItem = file

        let clock = TestClock()
        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.continuousClock = clock
        }

        await store.send(.openDownloadsFromPreview)
        await store.receive(.previewDismissed) {
            $0.previewItem = nil
        }
        await clock.advance(by: .milliseconds(350))
        await store.receive(.delegate(.openDownloadsTapped))
    }

    @Test
    func goToSharedTabFromPreviewDismissesTheCoverThenSwitchesTabsAfterASettle() async {
        let serverURL = URL(string: "https://example.com")!
        let file = FileItem(name: "photo.jpg", path: "", dateModified: Date(), size: 0, kind: "jpg")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.previewItem = file

        let clock = TestClock()
        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.continuousClock = clock
        }

        await store.send(.goToSharedTabFromPreview)
        await store.receive(.previewDismissed) {
            $0.previewItem = nil
        }
        await clock.advance(by: .milliseconds(350))
        await store.receive(.delegate(.goToSharedTab))
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

    // MARK: File actions — download

    @Test
    func downloadTappedOnAFileDownloadsAndSavesItSuccessfully() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "report.pdf", path: "", dateModified: Date(), size: 0, kind: "pdf")
        let cachedURL = URL(fileURLWithPath: "/tmp/cached/report.pdf")
        let savedURL = URL(fileURLWithPath: "/tmp/Documents/Downloads/report.pdf")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.downloadRawFile = { _, _ in cachedURL }
            $0.localDownloadStore.save = { _, _, _ in savedURL }
        }

        await store.send(.downloadTapped(item, .documents, removeArchiveAfterDownload: false)) {
            $0.isPerformingFileAction = true
            $0.fileActionProgressMessage = "Downloading…"
        }
        await store.receive(\.downloadResponse.success) {
            $0.isPerformingFileAction = false
            $0.fileActionProgressMessage = nil
            $0.downloadSuccessMessage = "Saved to Documents"
        }
    }

    @Test
    func downloadTappedOnAFileFailureSurfacesAReadableErrorMessage() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "report.pdf", path: "", dateModified: Date(), size: 0, kind: "pdf")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.downloadRawFile = { _, _ in throw FilesClientError.server(statusCode: 403) }
        }

        await store.send(.downloadTapped(item, .documents, removeArchiveAfterDownload: false)) {
            $0.isPerformingFileAction = true
            $0.fileActionProgressMessage = "Downloading…"
        }
        await store.receive(\.downloadResponse.failure) {
            $0.isPerformingFileAction = false
            $0.fileActionProgressMessage = nil
            $0.fileActionErrorMessage = FilesClientError.server(statusCode: 403).userMessage
        }
    }

    @Test
    func downloadTappedOnAFolderCompressesThenDownloadsBeforeSaving() async {
        // Folders have no dedicated zip-download endpoint — this exercises the full
        // compress → download → save chain, and that the progress message switches from
        // "Compressing…" to "Downloading…" partway through.
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "Documents", path: "", dateModified: Date(), size: 0, kind: "directory")
        let compressed = FileItem(name: "Documents.zip", path: "", dateModified: Date(), size: 0, kind: "zip")
        let cachedURL = URL(fileURLWithPath: "/tmp/cached/Documents.zip")
        let savedURL = URL(fileURLWithPath: "/tmp/Caches/Downloads/Documents.zip")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.compressItem = { _, _ in compressed }
            $0.filesClient.downloadRawFile = { _, _ in cachedURL }
            $0.localDownloadStore.save = { _, _, _ in savedURL }
        }

        await store.send(.downloadTapped(item, .cache, removeArchiveAfterDownload: false)) {
            $0.isPerformingFileAction = true
            $0.fileActionProgressMessage = "Compressing…"
        }
        await store.receive(\.downloadProgressUpdated) {
            $0.fileActionProgressMessage = "Downloading…"
        }
        await store.receive(\.downloadResponse.success) {
            $0.isPerformingFileAction = false
            $0.fileActionProgressMessage = nil
            $0.downloadSuccessMessage = "Saved to Cache"
        }
    }

    @Test
    func downloadTappedOnAFolderWithRemoveArchiveEnabledDeletesTheCompressedArchiveOnceSaved() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "Documents", path: "", dateModified: Date(), size: 0, kind: "directory")
        let compressed = FileItem(name: "Documents.zip", path: "", dateModified: Date(), size: 0, kind: "zip")
        let deletedItems = LockIsolated<[FileItem]>([])

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.compressItem = { _, _ in compressed }
            $0.filesClient.downloadRawFile = { _, _ in URL(fileURLWithPath: "/tmp/cached/Documents.zip") }
            $0.localDownloadStore.save = { _, _, _ in URL(fileURLWithPath: "/tmp/Caches/Downloads/Documents.zip") }
            $0.filesClient.deleteItems = { _, items in deletedItems.withValue { $0 = items } }
        }
        store.exhaustivity = .off

        await store.send(.downloadTapped(item, .cache, removeArchiveAfterDownload: true))
        await store.receive(\.downloadResponse.success)

        #expect(deletedItems.value == [compressed])
    }

    @Test
    func downloadTappedOnAFolderWithRemoveArchiveEnabledStillSucceedsWhenDeletingTheArchiveFails() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "Documents", path: "", dateModified: Date(), size: 0, kind: "directory")
        let compressed = FileItem(name: "Documents.zip", path: "", dateModified: Date(), size: 0, kind: "zip")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.compressItem = { _, _ in compressed }
            $0.filesClient.downloadRawFile = { _, _ in URL(fileURLWithPath: "/tmp/cached/Documents.zip") }
            $0.localDownloadStore.save = { _, _, _ in URL(fileURLWithPath: "/tmp/Caches/Downloads/Documents.zip") }
            $0.filesClient.deleteItems = { _, _ in throw FilesClientError.server(statusCode: 500) }
        }
        store.exhaustivity = .off

        await store.send(.downloadTapped(item, .cache, removeArchiveAfterDownload: true))
        await store.receive(\.downloadResponse.success) {
            $0.downloadSuccessMessage = "Saved to Cache"
        }
    }

    @Test
    func downloadTappedOnAFileWithRemoveArchiveEnabledNeverCallsDelete() async {
        // No `deleteItems` override: a call here would crash with "Unimplemented," proving
        // the cleanup only ever applies to a folder's own compressed archive.
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "report.pdf", path: "", dateModified: Date(), size: 0, kind: "pdf")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.downloadRawFile = { _, _ in URL(fileURLWithPath: "/tmp/cached/report.pdf") }
            $0.localDownloadStore.save = { _, _, _ in URL(fileURLWithPath: "/tmp/Documents/Downloads/report.pdf") }
        }
        store.exhaustivity = .off

        await store.send(.downloadTapped(item, .documents, removeArchiveAfterDownload: true))
        await store.receive(\.downloadResponse.success)
    }

    @Test
    func downloadTappedOnAFolderFailureWhenCompressFails() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "Documents", path: "", dateModified: Date(), size: 0, kind: "directory")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            // No `downloadRawFile`/`localDownloadStore` override: a call to either here would
            // crash with "Unimplemented," proving the chain stops right after compress fails.
            $0.filesClient.compressItem = { _, _ in throw FilesClientError.server(statusCode: 507) }
        }

        await store.send(.downloadTapped(item, .documents, removeArchiveAfterDownload: false)) {
            $0.isPerformingFileAction = true
            $0.fileActionProgressMessage = "Compressing…"
        }
        await store.receive(\.downloadResponse.failure) {
            $0.isPerformingFileAction = false
            $0.fileActionProgressMessage = nil
            $0.fileActionErrorMessage = FilesClientError.server(statusCode: 507).userMessage
        }
    }

    @Test
    func downloadTappedFailureWhenSavingLocallyFailsAfterANetworkSucceeds() async {
        // Edge case: the network half of the chain succeeds, but the local copy step (disk
        // full, permissions, ...) fails — the error should still surface as a readable
        // message via the same `FilesClientError.network` fallback every other action uses
        // for a non-`FilesClientError` throw.
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "report.pdf", path: "", dateModified: Date(), size: 0, kind: "pdf")
        let cachedURL = URL(fileURLWithPath: "/tmp/cached/report.pdf")
        struct DiskFullError: Error {}

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.downloadRawFile = { _, _ in cachedURL }
            $0.localDownloadStore.save = { _, _, _ in throw DiskFullError() }
        }

        await store.send(.downloadTapped(item, .documents, removeArchiveAfterDownload: false)) {
            $0.isPerformingFileAction = true
            $0.fileActionProgressMessage = "Downloading…"
        }
        await store.receive(\.downloadResponse.failure) {
            $0.isPerformingFileAction = false
            $0.fileActionProgressMessage = nil
            $0.fileActionErrorMessage = FilesClientError.network(String(describing: DiskFullError())).userMessage
        }
    }

    // MARK: Selection + bulk toolbar

    @Test
    func selectModeToggledEntersSelectMode() async {
        let store = TestStore(initialState: BrowseFeature.State(serverURL: URL(string: "https://example.com")!, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        }

        await store.send(.selectModeToggled) {
            $0.isSelecting = true
        }
    }

    @Test
    func selectModeToggledExitingClearsAnyExistingSelection() async {
        var state = BrowseFeature.State(serverURL: URL(string: "https://example.com")!, directoryPath: "", title: "Browse")
        state.isSelecting = true
        state.selectedItemIDs = ["a", "b"]

        let store = TestStore(initialState: state) {
            BrowseFeature()
        }

        await store.send(.selectModeToggled) {
            $0.isSelecting = false
            $0.selectedItemIDs = []
        }
    }

    @Test
    func itemSelectionToggledAddsThenRemovesTheSameID() async {
        var state = BrowseFeature.State(serverURL: URL(string: "https://example.com")!, directoryPath: "", title: "Browse")
        state.isSelecting = true

        let store = TestStore(initialState: state) {
            BrowseFeature()
        }

        await store.send(.itemSelectionToggled("a")) {
            $0.selectedItemIDs = ["a"]
        }
        await store.send(.itemSelectionToggled("a")) {
            $0.selectedItemIDs = []
        }
    }

    @Test
    func selectAllTappedSelectsEveryDisplayedItem() async {
        let itemA = FileItem(name: "A", path: "", dateModified: Date(), size: 0, kind: "directory")
        let itemB = FileItem(name: "B", path: "", dateModified: Date(), size: 0, kind: "txt")
        var state = BrowseFeature.State(serverURL: URL(string: "https://example.com")!, directoryPath: "", title: "Browse")
        state.items = [itemA, itemB]
        state.isSelecting = true

        let store = TestStore(initialState: state) {
            BrowseFeature()
        }

        await store.send(.selectAllTapped) {
            $0.selectedItemIDs = [itemA.id, itemB.id]
        }
        await store.send(.deselectAllTapped) {
            $0.selectedItemIDs = []
        }
    }

    @Test
    func bulkDeleteTappedWithAnEmptySelectionDoesNotShowTheConfirmation() async {
        var state = BrowseFeature.State(serverURL: URL(string: "https://example.com")!, directoryPath: "", title: "Browse")
        state.isSelecting = true

        let store = TestStore(initialState: state) {
            BrowseFeature()
        }

        await store.send(.bulkDeleteTapped)
    }

    @Test
    func bulkDeleteConfirmedDeletesEverySelectedItemInOneCall() async {
        let itemA = FileItem(name: "A", path: "", dateModified: Date(), size: 0, kind: "directory")
        let itemB = FileItem(name: "B", path: "", dateModified: Date(), size: 0, kind: "txt")
        var state = BrowseFeature.State(serverURL: URL(string: "https://example.com")!, directoryPath: "", title: "Browse")
        state.items = [itemA, itemB]
        state.isSelecting = true
        state.selectedItemIDs = [itemA.id, itemB.id]
        state.bulkDeleteConfirmationIsPresented = true
        state.favoritePaths = [itemA.id]

        let deletedItems = LockIsolated<[FileItem]>([])
        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.deleteItems = { _, items in deletedItems.setValue(items) }
        }

        await store.send(.bulkDeleteConfirmed) {
            $0.bulkDeleteConfirmationIsPresented = false
            $0.isBulkActionInFlight = true
        }
        await store.receive(\.bulkDeleteResponse.success) {
            $0.isBulkActionInFlight = false
            $0.items = []
            $0.favoritePaths = []
            $0.isSelecting = false
            $0.selectedItemIDs = []
        }
        await store.receive(.delegate(.favoritesChanged))

        #expect(Set(deletedItems.value.map(\.id)) == [itemA.id, itemB.id])
    }

    @Test
    func bulkDeleteConfirmedFailureSurfacesAReadableErrorMessage() async {
        let item = FileItem(name: "A", path: "", dateModified: Date(), size: 0, kind: "directory")
        var state = BrowseFeature.State(serverURL: URL(string: "https://example.com")!, directoryPath: "", title: "Browse")
        state.items = [item]
        state.isSelecting = true
        state.selectedItemIDs = [item.id]

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.deleteItems = { _, _ in throw FilesClientError.server(statusCode: 403) }
        }

        await store.send(.bulkDeleteConfirmed) {
            $0.bulkDeleteConfirmationIsPresented = false
            $0.isBulkActionInFlight = true
        }
        await store.receive(\.bulkDeleteResponse.failure) {
            $0.isBulkActionInFlight = false
            $0.fileActionErrorMessage = FilesClientError.server(statusCode: 403).userMessage
        }
    }

    @Test
    func bulkFavoriteTappedTogglesEachSelectedDirectory() async {
        let folder = FileItem(name: "Photos", path: "", dateModified: Date(), size: 0, kind: "directory")
        let alreadyFavorited = FileItem(name: "Documents", path: "", dateModified: Date(), size: 0, kind: "directory")
        let file = FileItem(name: "notes.txt", path: "", dateModified: Date(), size: 0, kind: "txt")
        var state = BrowseFeature.State(serverURL: URL(string: "https://example.com")!, directoryPath: "", title: "Browse")
        state.items = [folder, alreadyFavorited, file]
        state.favoritePaths = [alreadyFavorited.id]
        state.isSelecting = true
        state.selectedItemIDs = [folder.id, alreadyFavorited.id, file.id]

        let addedPaths = LockIsolated<[String]>([])
        let removedPaths = LockIsolated<[String]>([])
        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.addFavorite = { _, path in
                addedPaths.withValue { $0.append(path) }
                return Favorite(id: "1", path: path, label: nil, icon: "star", color: nil, position: 0, createdAt: Date(), updatedAt: Date())
            }
            $0.filesClient.removeFavorite = { _, path in
                removedPaths.withValue { $0.append(path) }
            }
        }

        await store.send(.bulkFavoriteTapped) {
            $0.isBulkActionInFlight = true
        }
        await store.receive(\.bulkFavoriteResponse) {
            $0.isBulkActionInFlight = false
            $0.favoritePaths = [folder.id]
            $0.isSelecting = false
            $0.selectedItemIDs = []
        }
        await store.receive(.delegate(.favoritesChanged))

        #expect(addedPaths.value == [folder.id])
        #expect(removedPaths.value == [alreadyFavorited.id])
    }

    @Test
    func bulkFavoriteTappedWithNoDirectoriesSelectedDoesNothing() async {
        let file = FileItem(name: "notes.txt", path: "", dateModified: Date(), size: 0, kind: "txt")
        var state = BrowseFeature.State(serverURL: URL(string: "https://example.com")!, directoryPath: "", title: "Browse")
        state.items = [file]
        state.isSelecting = true
        state.selectedItemIDs = [file.id]

        // No `addFavorite`/`removeFavorite` override: a call here would crash with
        // "Unimplemented," proving a selection with no directories never touches the network.
        let store = TestStore(initialState: state) {
            BrowseFeature()
        }

        await store.send(.bulkFavoriteTapped)
    }

    @Test
    func bulkDownloadTappedSavesEverySelectedItem() async {
        let file = FileItem(name: "report.pdf", path: "", dateModified: Date(), size: 0, kind: "pdf")
        let folder = FileItem(name: "Photos", path: "", dateModified: Date(), size: 0, kind: "directory")
        let compressedFolder = FileItem(name: "Photos.zip", path: "", dateModified: Date(), size: 0, kind: "zip")
        var state = BrowseFeature.State(serverURL: URL(string: "https://example.com")!, directoryPath: "", title: "Browse")
        state.items = [file, folder]
        state.isSelecting = true
        state.selectedItemIDs = [file.id, folder.id]

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.compressItem = { _, _ in compressedFolder }
            $0.filesClient.downloadRawFile = { _, item in URL(fileURLWithPath: "/tmp/cached/\(item.name)") }
            $0.localDownloadStore.save = { sourceURL, fileName, _ in URL(fileURLWithPath: "/tmp/Documents/Downloads/\(fileName)") }
        }
        store.exhaustivity = .off

        await store.send(.bulkDownloadTapped(.documents, removeArchiveAfterDownload: false)) {
            $0.isBulkActionInFlight = true
            $0.fileActionProgressMessage = "Downloading 1 of 2…"
        }
        await store.receive(\.bulkDownloadResponse) {
            $0.isBulkActionInFlight = false
            $0.fileActionProgressMessage = nil
            $0.isSelecting = false
            $0.selectedItemIDs = []
            $0.downloadSuccessMessage = "Saved 2 items to Documents"
        }
    }

    @Test
    func bulkDownloadTappedWithRemoveArchiveEnabledOnlyDeletesTheCompressedFolderArchives() async {
        let file = FileItem(name: "report.pdf", path: "", dateModified: Date(), size: 0, kind: "pdf")
        let folder = FileItem(name: "Photos", path: "", dateModified: Date(), size: 0, kind: "directory")
        let compressedFolder = FileItem(name: "Photos.zip", path: "", dateModified: Date(), size: 0, kind: "zip")
        var state = BrowseFeature.State(serverURL: URL(string: "https://example.com")!, directoryPath: "", title: "Browse")
        state.items = [file, folder]
        state.isSelecting = true
        state.selectedItemIDs = [file.id, folder.id]

        let deletedItems = LockIsolated<[FileItem]>([])
        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.compressItem = { _, _ in compressedFolder }
            $0.filesClient.downloadRawFile = { _, item in URL(fileURLWithPath: "/tmp/cached/\(item.name)") }
            $0.localDownloadStore.save = { _, fileName, _ in URL(fileURLWithPath: "/tmp/Documents/Downloads/\(fileName)") }
            $0.filesClient.deleteItems = { _, items in deletedItems.withValue { $0.append(contentsOf: items) } }
        }
        store.exhaustivity = .off

        await store.send(.bulkDownloadTapped(.documents, removeArchiveAfterDownload: true))
        await store.receive(\.bulkDownloadResponse)

        #expect(deletedItems.value == [compressedFolder])
    }

    @Test
    func bulkDownloadTappedReportsPartialSuccessWhenOneItemFails() async {
        let goodFile = FileItem(name: "report.pdf", path: "", dateModified: Date(), size: 0, kind: "pdf")
        let badFile = FileItem(name: "broken.pdf", path: "", dateModified: Date(), size: 0, kind: "pdf")
        var state = BrowseFeature.State(serverURL: URL(string: "https://example.com")!, directoryPath: "", title: "Browse")
        state.items = [goodFile, badFile]
        state.isSelecting = true
        state.selectedItemIDs = [goodFile.id, badFile.id]

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.downloadRawFile = { _, item in
                if item.id == badFile.id { throw FilesClientError.server(statusCode: 500) }
                return URL(fileURLWithPath: "/tmp/cached/\(item.name)")
            }
            $0.localDownloadStore.save = { sourceURL, fileName, _ in URL(fileURLWithPath: "/tmp/Documents/Downloads/\(fileName)") }
        }
        store.exhaustivity = .off

        await store.send(.bulkDownloadTapped(.documents, removeArchiveAfterDownload: false))
        await store.receive(\.bulkDownloadResponse) {
            $0.isBulkActionInFlight = false
            $0.fileActionProgressMessage = nil
            $0.isSelecting = false
            $0.selectedItemIDs = []
            $0.downloadSuccessMessage = "Saved 1 of 2 items to Documents"
        }
    }

    // MARK: File actions — get info

    @Test
    func infoTappedOnAFolderFetchesMetadataAndServerDiskUsage() async {
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
        let usage = StorageUsage(path: "Photos", size: 30, free: 70, total: 100)

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.fetchMetadata = { _, _ in metadata }
            $0.filesClient.fetchUsage = { _, path in
                #expect(path == "Photos")
                return usage
            }
        }
        store.exhaustivity = .off

        await store.send(.infoTapped(item)) {
            $0.infoItem = item
            $0.isLoadingInfoMetadata = true
        }
        await store.receive(\.infoMetadataResponse.success) {
            $0.isLoadingInfoMetadata = false
            $0.infoMetadata = metadata
        }
        await store.receive(\.infoUsageResponse.success) {
            $0.infoUsage = usage
        }
    }

    @Test
    func infoTappedOnAFileSkipsTheUsageFetch() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "notes.txt", path: "", dateModified: Date(), size: 12, kind: "txt")
        let metadata = FileMetadata(path: "notes.txt", name: "notes.txt", kind: "txt", size: 12, dateModified: Date(), dateCreated: Date())

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.fetchMetadata = { _, _ in metadata }
            $0.filesClient.fetchUsage = { _, _ in
                Issue.record("a file's Get Info should not fetch disk usage")
                return StorageUsage()
            }
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
    func anAllZeroUsageResponseIsDropped() async {
        let serverURL = URL(string: "https://example.com")!
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.infoUsage = StorageUsage(path: "x", size: 1, free: 1, total: 2)
        let store = TestStore(initialState: state) { BrowseFeature() }

        await store.send(.infoUsageResponse(.success(StorageUsage(path: "Photos", size: 0, free: 0, total: 0)))) {
            $0.infoUsage = nil
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
            $0.filesClient.fetchUsage = { _, _ in StorageUsage() }
        }
        store.exhaustivity = .off

        await store.send(.infoTapped(second)) {
            $0.infoItem = second
            $0.infoMetadata = nil
            $0.infoUsage = nil
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
        state.infoUsage = StorageUsage(path: "Photos", size: 1, free: 1, total: 2)
        state.infoErrorMessage = "some error"
        state.isLoadingInfoMetadata = true

        let store = TestStore(initialState: state) {
            BrowseFeature()
        }

        await store.send(.infoDismissed) {
            $0.infoItem = nil
            $0.infoMetadata = nil
            $0.infoUsage = nil
            $0.infoErrorMessage = nil
            $0.isLoadingInfoMetadata = false
        }
    }

    @Test
    func permissionsTappedPresentsTheSheetSeededFromTheItemAndDismissClearsIt() async {
        let serverURL = URL(string: "https://example.com")!
        let item = FileItem(name: "report.pdf", path: "Documents", dateModified: Date(), size: 10, kind: "pdf")
        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        }
        store.exhaustivity = .off

        await store.send(.permissionsTapped(item)) {
            $0.permissions = PermissionsFeature.State(serverURL: serverURL, item: item)
        }
        #expect(store.state.permissions?.item == item)

        await store.send(.permissions(.dismiss)) {
            $0.permissions = nil
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

// MARK: - Copy / Move / Paste

@MainActor
@Suite
struct BrowseFeatureTransferTests {
    private let serverURL = URL(string: "https://example.com")!

    private nonisolated func writableAccess() -> FileAccess {
        FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: false, canDownload: true)
    }

    private func makeState(directoryPath: String = "Documents", access: FileAccess? = nil) -> BrowseFeature.State {
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: directoryPath, title: "Docs")
        state.access = access ?? writableAccess()
        state.$clipboard.withLock { $0 = nil }
        return state
    }

    private nonisolated func item(_ name: String, path: String = "Inbox") -> FileItem {
        FileItem(name: name, path: path, dateModified: Date(timeIntervalSince1970: 1), size: 0, kind: "txt")
    }

    private nonisolated func result(destination: String, moved: Int, skipped: Int = 0) -> TransferResult {
        var entries: [TransferResult.Entry] = []
        for i in 0..<moved { entries.append(.init(from: "Inbox/f\(i)", to: "\(destination)/f\(i)")) }
        for i in 0..<skipped { entries.append(.init(from: "Inbox/s\(i)", to: "Inbox/s\(i)", skipped: true)) }
        return TransferResult(destination: destination, items: entries)
    }

    @Test
    func copyTappedStagesTheItemAndConfirmsWithAToast() async {
        let file = item("a.txt")
        let store = TestStore(initialState: makeState()) { BrowseFeature() }

        await store.send(.copyTapped(file)) {
            $0.$clipboard.withLock { $0 = FileClipboard(items: [file], operation: .copy) }
            $0.clipboardStagedMessage = L10n.Browse.clipboardCopiedOne("a.txt")
        }
    }

    @Test
    func moveTappedPresentsTheDestinationPicker() async {
        let file = item("a.txt")
        let store = TestStore(initialState: makeState()) { BrowseFeature() }

        await store.send(.moveTapped(file)) {
            $0.destinationPicker = DestinationPickerFeature.State(serverURL: self.serverURL, items: [file])
        }
    }

    private nonisolated func picked(_ name: String, id: UUID, size: Int64 = 10) -> PickedFile {
        PickedFile(id: id, fileURL: URL(fileURLWithPath: "/tmp/\(name)"), fileName: name, size: size)
    }

    @Test
    func beginningUploadOpensTheReviewSheetAndStartsStaging() async {
        let store = TestStore(initialState: makeState(directoryPath: "Documents")) {
            BrowseFeature()
        } withDependencies: {
            $0.uploadStaging = UploadStagingClient(
                stageDocuments: { _ in
                    AsyncStream<PickedFile> { continuation in
                        continuation.yield(self.picked("a.jpg", id: UUID(0)))
                        continuation.yield(self.picked("b.jpg", id: UUID(1)))
                        continuation.finish()
                    }
                },
                stagePhotos: { _ in AsyncStream<PickedFile> { $0.finish() } },
                stageCameraCapture: { _ in nil },
                discard: { _ in },
                sweepStale: {}
            )
        }
        store.exhaustivity = .off

        await store.send(.beginUpload(.documents([
            URL(fileURLWithPath: "/tmp/a.jpg"), URL(fileURLWithPath: "/tmp/b.jpg"),
        ])))
        #expect(store.state.uploadReview != nil)
        #expect(store.state.uploadReview?.destination == "Documents")

        await store.receive(\.uploadReview.presented.stage) {
            $0.uploadReview?.preparingCount = 2
        }
        await store.receive(\.uploadReview.presented.filePrepared)
        await store.receive(\.uploadReview.presented.filePrepared)
        await store.receive(\.uploadReview.presented.stagingBatchFinished)
        #expect(store.state.uploadReview?.totalCount == 2)
    }

    @Test
    func confirmingTheReviewSheetEnqueuesWithTheChosenDestination() async {
        var state = makeState(directoryPath: "Documents")
        let files = [picked("a.jpg", id: UUID(0)), picked("b.txt", id: UUID(1))]
        state.uploadReview = UploadReviewFeature.State(
            serverURL: serverURL, files: files, startingDestination: "Documents"
        )
        let store = TestStore(initialState: state) { BrowseFeature() }
        store.exhaustivity = .off

        await store.send(.uploadReview(.presented(.delegate(.confirmed(files: files, destination: "Documents/Trips"))))) {
            $0.uploadReview = nil
        }
        await store.receive(.delegate(.uploadRequested([
            PendingUpload(id: UUID(0), fileURL: URL(fileURLWithPath: "/tmp/a.jpg"), fileName: "a.jpg", destination: "Documents/Trips"),
            PendingUpload(id: UUID(1), fileURL: URL(fileURLWithPath: "/tmp/b.txt"), fileName: "b.txt", destination: "Documents/Trips"),
        ])))
    }

    @Test
    func cancellingTheUploadReviewSheetClosesIt() async {
        var state = makeState()
        state.uploadReview = UploadReviewFeature.State(
            serverURL: serverURL, startingDestination: "Documents", preparingCount: 1
        )
        let store = TestStore(initialState: state) { BrowseFeature() }
        store.exhaustivity = .off

        await store.send(.uploadReview(.presented(.delegate(.cancelled)))) {
            $0.uploadReview = nil
        }
    }

    @Test
    func bulkCopyStagesTheSelectionWithACountToastAndExitsSelectMode() async {
        let a = item("a.txt", path: "Documents")
        let b = item("b.txt", path: "Documents")
        var state = makeState()
        state.items = [a, b]
        state.isSelecting = true
        state.selectedItemIDs = [a.id, b.id]
        let store = TestStore(initialState: state) { BrowseFeature() }

        await store.send(.bulkCopyTapped) {
            $0.$clipboard.withLock { $0 = FileClipboard(items: [a, b], operation: .copy) }
            $0.clipboardStagedMessage = L10n.Browse.clipboardCopiedMany(2)
            $0.isSelecting = false
            $0.selectedItemIDs = []
        }
    }

    @Test
    func bulkMovePresentsThePickerWithTheSelectionAndExitsSelectMode() async {
        let a = item("a.txt", path: "Documents")
        let b = item("b.txt", path: "Documents")
        var state = makeState()
        state.items = [a, b]
        state.isSelecting = true
        state.selectedItemIDs = [a.id, b.id]
        let store = TestStore(initialState: state) { BrowseFeature() }

        await store.send(.bulkMoveTapped) {
            $0.destinationPicker = DestinationPickerFeature.State(serverURL: self.serverURL, items: [a, b])
            $0.isSelecting = false
            $0.selectedItemIDs = []
        }
    }

    @Test
    func destinationPickerConfirmRunsAMoveTransfer() async {
        let file = item("a.txt")
        var state = makeState()
        state.$clipboard.withLock { $0 = FileClipboard(items: [item("copied.txt")], operation: .copy) }
        state.destinationPicker = DestinationPickerFeature.State(serverURL: serverURL, items: [file])
        let captured = LockIsolated<(destination: String, operation: TransferOperation)?>(nil)

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.transferItems = { _, _, destination, operation in
                captured.setValue((destination, operation))
                return self.result(destination: destination, moved: 1)
            }
        }
        store.exhaustivity = .off

        await store.send(.destinationPicker(.presented(.delegate(.confirmed(destination: "Archive"))))) {
            $0.destinationPicker = nil
        }
        await store.receive(\.transferResponse.success)
        await store.receive(.delegate(.directoryContentsChanged))

        #expect(captured.value?.destination == "Archive")
        #expect(captured.value?.operation == .move)
        // The unrelated copy clipboard is untouched by a picker move.
        #expect(store.state.clipboard == FileClipboard(items: [item("copied.txt")], operation: .copy))
    }

    @Test
    func destinationPickerCancelDismissesWithoutTransferring() async {
        var state = makeState()
        state.destinationPicker = DestinationPickerFeature.State(serverURL: serverURL, items: [item("a.txt")])
        // No `transferItems` override: a call would crash with "Unimplemented".
        let store = TestStore(initialState: state) { BrowseFeature() }

        await store.send(.destinationPicker(.presented(.delegate(.cancelled)))) {
            $0.destinationPicker = nil
        }
    }

    @Test
    func clipboardClearedEmptiesTheClipboard() async {
        var state = makeState()
        state.$clipboard.withLock { $0 = FileClipboard(items: [item("a.txt")], operation: .copy) }
        let store = TestStore(initialState: state) { BrowseFeature() }

        await store.send(.clipboardCleared) {
            $0.$clipboard.withLock { $0 = nil }
        }
    }

    @Test
    func pasteCopiesIntoTheCurrentFolderAndClearsTheClipboardWhenKeepIsOff() async {
        let file = item("a.txt")
        var state = makeState(directoryPath: "Documents")
        state.$clipboard.withLock { $0 = FileClipboard(items: [file], operation: .copy) }
        let captured = LockIsolated<(items: [FileItem], destination: String, operation: TransferOperation)?>(nil)

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.transferItems = { _, items, destination, operation in
                captured.setValue((items, destination, operation))
                return self.result(destination: destination, moved: 1)
            }
        }

        await store.send(.pasteTapped(keepItemsAfterCopy: false)) {
            $0.isPerformingFileAction = true
            $0.fileActionProgressMessage = L10n.Browse.progressCopying
            $0.pendingTransferRetry = BrowseFeature.TransferRetry(
                items: [file], destination: "Documents", operation: .copy, clearClipboard: true, resolution: .keepBoth
            )
        }
        await store.receive(\.transferResponse.success) {
            $0.isPerformingFileAction = false
            $0.fileActionProgressMessage = nil
            $0.pendingTransferRetry = nil
            $0.$clipboard.withLock { $0 = nil }
            $0.transferSuccessMessage = L10n.Browse.transferCopied(1)
        }
        await store.receive(.delegate(.directoryContentsChanged))

        #expect(captured.value?.items == [file])
        #expect(captured.value?.destination == "Documents")
        #expect(captured.value?.operation == .copy)
    }

    @Test
    func pasteKeepsTheClipboardWhenKeepItemsAfterCopyIsOn() async {
        let file = item("a.txt")
        var state = makeState()
        state.$clipboard.withLock { $0 = FileClipboard(items: [file], operation: .copy) }

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.transferItems = { _, _, destination, _ in self.result(destination: destination, moved: 1) }
        }
        store.exhaustivity = .off

        await store.send(.pasteTapped(keepItemsAfterCopy: true))
        await store.receive(\.transferResponse.success) {
            $0.transferSuccessMessage = L10n.Browse.transferCopied(1)
        }
        #expect(store.state.clipboard == FileClipboard(items: [file], operation: .copy))
    }

    @Test
    func pasteFailureKeepsTheClipboardAndSurfacesAReadableError() async {
        let file = item("a.txt")
        var state = makeState()
        state.$clipboard.withLock { $0 = FileClipboard(items: [file], operation: .copy) }

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.transferItems = { _, _, _, _ in throw FilesClientError.serverMessage(statusCode: 500, message: "Nope.") }
        }
        store.exhaustivity = .off

        await store.send(.pasteTapped(keepItemsAfterCopy: false))
        await store.receive(\.transferResponse.failure) {
            $0.isPerformingFileAction = false
            $0.fileActionProgressMessage = nil
            $0.transferErrorMessage = "Nope."
        }
        #expect(store.state.clipboard == FileClipboard(items: [file], operation: .copy))
        #expect(store.state.pendingTransferRetry?.operation == .copy)
    }

    @Test
    func retryTransferReRunsTheFailedTransferAndClearsTheClipboardOnSuccess() async {
        let file = item("a.txt")
        var state = makeState()
        state.$clipboard.withLock { $0 = FileClipboard(items: [file], operation: .copy) }
        let attempts = LockIsolated(0)

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.transferItems = { _, _, destination, _ in
                attempts.withValue { $0 += 1 }
                if attempts.value == 1 { throw FilesClientError.serverMessage(statusCode: 500, message: "Nope.") }
                return self.result(destination: destination, moved: 1)
            }
        }
        store.exhaustivity = .off

        await store.send(.pasteTapped(keepItemsAfterCopy: false))
        await store.receive(\.transferResponse.failure) {
            $0.transferErrorMessage = "Nope."
        }
        await store.send(.retryTransferTapped)
        await store.receive(\.transferResponse.success) {
            $0.transferErrorMessage = nil
            $0.pendingTransferRetry = nil
        }
        #expect(attempts.value == 2)
        #expect(store.state.clipboard == nil)
    }

    @Test
    func pasteIsANoOpAtTheVolumeRoot() async {
        var state = makeState(directoryPath: "")
        state.$clipboard.withLock { $0 = FileClipboard(items: [item("a.txt")], operation: .copy) }
        // No `transferItems` override: a call would crash with "Unimplemented".
        let store = TestStore(initialState: state) { BrowseFeature() }

        await store.send(.pasteTapped(keepItemsAfterCopy: false))
    }

    @Test
    func pasteIsANoOpWhenTheFolderIsNotWritable() async {
        var state = makeState(access: FileAccess(canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true))
        state.$clipboard.withLock { $0 = FileClipboard(items: [item("a.txt")], operation: .copy) }
        let store = TestStore(initialState: state) { BrowseFeature() }

        await store.send(.pasteTapped(keepItemsAfterCopy: false))
    }

    @Test
    func pasteIsANoOpWhenCopyingAFolderIntoASubdirectoryOfItself() async {
        // Server fails this with EINVAL ("Cannot copy to a subdirectory of self"); the
        // reducer must not fire the doomed request.
        let folder = FileItem(name: "Photos", path: "Media", dateModified: Date(timeIntervalSince1970: 1), size: 0, kind: "directory")
        var state = makeState(directoryPath: "Media/Photos/2024")
        state.$clipboard.withLock { $0 = FileClipboard(items: [folder], operation: .copy) }
        // No `transferItems` override: a call would crash with "Unimplemented".
        let store = TestStore(initialState: state) { BrowseFeature() }

        await store.send(.pasteTapped(keepItemsAfterCopy: false))
    }

    @Test
    func pasteSuccessMessageReportsSkippedCopies() async {
        var state = makeState()
        state.$clipboard.withLock { $0 = FileClipboard(items: [item("a.txt")], operation: .copy) }

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.transferItems = { _, _, destination, _ in self.result(destination: destination, moved: 2, skipped: 1) }
        }
        store.exhaustivity = .off

        await store.send(.pasteTapped(keepItemsAfterCopy: false))
        await store.receive(\.transferResponse.success) {
            $0.transferSuccessMessage = L10n.Browse.transferCopiedWithSkipped(2, 1)
        }
    }

    @Test
    func moveViaPickerSuccessMessageReportsSkippedItems() async {
        var state = makeState()
        state.destinationPicker = DestinationPickerFeature.State(serverURL: serverURL, items: [item("a.txt")])

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.transferItems = { _, _, destination, _ in self.result(destination: destination, moved: 2, skipped: 1) }
        }
        store.exhaustivity = .off

        await store.send(.destinationPicker(.presented(.delegate(.confirmed(destination: "Archive")))))
        await store.receive(\.transferResponse.success) {
            $0.transferSuccessMessage = L10n.Browse.transferMovedWithSkipped(2, 1)
        }
    }

    // MARK: Name collisions

    @Test
    func pastePromptsWhenTheCurrentFolderAlreadyHasASameNamedItem() async {
        let incoming = item("a.txt", path: "Inbox")
        let existing = item("a.txt", path: "Documents")
        var state = makeState(directoryPath: "Documents")
        state.items = [existing]
        state.$clipboard.withLock { $0 = FileClipboard(items: [incoming], operation: .copy) }
        let store = TestStore(initialState: state) { BrowseFeature() }

        await store.send(.pasteTapped(keepItemsAfterCopy: false)) {
            $0.pendingTransferRetry = BrowseFeature.TransferRetry(
                items: [incoming], destination: "Documents", operation: .copy, clearClipboard: true
            )
            $0.transferConflict = BrowseFeature.TransferConflict(
                retry: BrowseFeature.TransferRetry(
                    items: [incoming], destination: "Documents", operation: .copy, clearClipboard: true
                ),
                collidingItems: [existing]
            )
        }
    }

    @Test
    func replaceDeletesTheClashingItemThenTransfers() async {
        let incoming = item("a.txt", path: "Inbox")
        let existing = item("a.txt", path: "Documents")
        var state = makeState(directoryPath: "Documents")
        state.items = [existing]
        state.$clipboard.withLock { $0 = FileClipboard(items: [incoming], operation: .copy) }
        let deleted = LockIsolated<[FileItem]?>(nil)

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.deleteItems = { _, items in deleted.setValue(items) }
            $0.filesClient.transferItems = { _, _, destination, _ in self.result(destination: destination, moved: 1) }
        }
        store.exhaustivity = .off

        await store.send(.pasteTapped(keepItemsAfterCopy: false))
        await store.send(.transferConflictResolved(.replace))
        await store.receive(\.transferResponse.success)

        #expect(deleted.value == [existing])
    }

    @Test
    func keepBothTransfersWithoutDeletingAnything() async {
        let incoming = item("a.txt", path: "Inbox")
        let existing = item("a.txt", path: "Documents")
        var state = makeState(directoryPath: "Documents")
        state.items = [existing]
        state.$clipboard.withLock { $0 = FileClipboard(items: [incoming], operation: .copy) }
        let deleteCalled = LockIsolated(false)

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.deleteItems = { _, _ in deleteCalled.setValue(true) }
            $0.filesClient.transferItems = { _, _, destination, _ in self.result(destination: destination, moved: 1) }
        }
        store.exhaustivity = .off

        await store.send(.pasteTapped(keepItemsAfterCopy: false))
        await store.send(.transferConflictResolved(.keepBoth))
        await store.receive(\.transferResponse.success)

        #expect(deleteCalled.value == false)
    }

    @Test
    func cancellingTheCollisionPromptKeepsTheClipboardAndTransfersNothing() async {
        let incoming = item("a.txt", path: "Inbox")
        let existing = item("a.txt", path: "Documents")
        var state = makeState(directoryPath: "Documents")
        state.items = [existing]
        state.$clipboard.withLock { $0 = FileClipboard(items: [incoming], operation: .copy) }
        // No transferItems override: a call would flag "Unimplemented".
        let store = TestStore(initialState: state) { BrowseFeature() }
        store.exhaustivity = .off

        await store.send(.pasteTapped(keepItemsAfterCopy: false))
        await store.send(.transferConflictResolved(nil)) {
            $0.transferConflict = nil
            $0.pendingTransferRetry = nil
        }

        #expect(store.state.clipboard == FileClipboard(items: [incoming], operation: .copy))
    }

    @Test
    func pastingAFileBackIntoItsOwnFolderIsNotTreatedAsACollision() async {
        let file = item("a.txt", path: "Documents")
        var state = makeState(directoryPath: "Documents")
        state.items = [file]
        state.$clipboard.withLock { $0 = FileClipboard(items: [file], operation: .copy) }

        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.transferItems = { _, _, destination, _ in self.result(destination: destination, moved: 1) }
        }
        store.exhaustivity = .off

        await store.send(.pasteTapped(keepItemsAfterCopy: true))
        await store.receive(\.transferResponse.success)

        #expect(store.state.transferConflict == nil)
    }

    // MARK: Offline directory cache

    private nonisolated static let offlineAccess = FileAccess(
        canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true
    )

    @Test
    func offlineBrowseFailureFallsBackToTheCachedListing() async {
        let serverURL = URL(string: "https://example.com")!
        let fetchedAt = Date(timeIntervalSince1970: 1_000)
        let cachedItem = FileItem(name: "Saved", path: "docs", dateModified: Date(timeIntervalSince1970: 0), size: 1, kind: "txt")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "docs", title: "Docs")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in throw FilesClientError.offline }
            $0.filesClient.favorites = { _ in [] }
            $0.directoryCacheStore.read = { _, _ in
                CachedDirectory(path: "docs", items: [cachedItem], access: Self.offlineAccess, fetchedAt: fetchedAt)
            }
        }

        await store.send(.onAppear) {
            $0.phase = .loading
            $0.items = [cachedItem]
            $0.access = Self.offlineAccess
        }
        await store.receive(\.itemsResponse.failure) {
            $0.phase = .loaded
            $0.dataSource = .cached(fetchedAt: fetchedAt)
        }
        await store.receive(\.favoritesResponse)

        #expect(store.state.phase.errorMessage == nil)
    }

    @Test
    func offlineBrowseFailureWithNoCacheShowsTheErrorMessage() async {
        let serverURL = URL(string: "https://example.com")!

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "docs", title: "Docs")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in throw FilesClientError.offline }
            $0.filesClient.favorites = { _ in [] }
            $0.directoryCacheStore.read = { _, _ in nil }
        }

        await store.send(.onAppear) {
            $0.phase = .loading
        }
        await store.receive(\.itemsResponse.failure) {
            $0.phase = .failed(FilesClientError.offline.userMessage)
        }
        await store.receive(\.favoritesResponse)
    }

    @Test
    func cacheFirstPaintShowsSavedItemsWithoutTheOfflineBannerThenFreshDataReplacesThem() async {
        let serverURL = URL(string: "https://example.com")!
        let fetchedAt = Date(timeIntervalSince1970: 1_000)
        let cachedItem = FileItem(name: "Old", path: "docs", dateModified: Date(timeIntervalSince1970: 0), size: 1, kind: "txt")
        let freshItem = FileItem(name: "New", path: "docs", dateModified: Date(timeIntervalSince1970: 0), size: 2, kind: "txt")

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "docs", title: "Docs")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in
                BrowseResult(items: [freshItem], access: Self.offlineAccess, path: "docs")
            }
            $0.filesClient.favorites = { _ in [] }
            $0.directoryCacheStore.read = { _, _ in
                CachedDirectory(path: "docs", items: [cachedItem], access: Self.offlineAccess, fetchedAt: fetchedAt)
            }
        }

        await store.send(.onAppear) {
            $0.phase = .loading
            $0.items = [cachedItem]
            $0.access = Self.offlineAccess
        }
        #expect(store.state.dataSource == .live)

        await store.receive(\.itemsResponse.success) {
            $0.phase = .loaded
            $0.items = [freshItem]
        }
        await store.receive(\.favoritesResponse)

        #expect(store.state.dataSource == .live)
    }

    @Test
    func aSuccessfulBrowsePrefetchesImmediateSubfoldersOnly() async {
        let serverURL = URL(string: "https://example.com")!
        let folder = FileItem(name: "Photos", path: "docs", dateModified: Date(timeIntervalSince1970: 0), size: 0, kind: "directory")
        let file = FileItem(name: "a.txt", path: "docs", dateModified: Date(timeIntervalSince1970: 0), size: 1, kind: "txt")
        let prefetched = LockIsolated<[String]>([])

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "docs", title: "Docs")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in BrowseResult(items: [folder, file], access: Self.offlineAccess, path: "docs") }
            $0.filesClient.favorites = { _ in [] }
            $0.filesClient.prefetchDirectory = { _, path in prefetched.withValue { $0.append(path) } }
            $0.directoryCacheStore.lastWrittenAt = { _, _ in nil }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.itemsResponse.success)
        await store.receive(\.favoritesResponse)
        await store.finish()

        #expect(prefetched.value == ["docs/Photos"])
    }

    @Test
    func favoritesResponsePrefetchesFavoritedFolders() async {
        let serverURL = URL(string: "https://example.com")!
        let prefetched = LockIsolated<[String]>([])
        let favorites = ["Work", "Trips"].enumerated().map { index, path in
            Favorite(id: "\(index)", path: path, label: nil, icon: "folder", color: nil, position: index, createdAt: Date(), updatedAt: Date())
        }

        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.prefetchDirectory = { _, path in prefetched.withValue { $0.append(path) } }
            $0.directoryCacheStore.lastWrittenAt = { _, _ in nil }
        }
        store.exhaustivity = .off

        await store.send(.favoritesResponse(favorites)) {
            $0.favoritePaths = ["Work", "Trips"]
        }
        await store.finish()

        #expect(Set(prefetched.value) == ["Work", "Trips"])
    }
}
