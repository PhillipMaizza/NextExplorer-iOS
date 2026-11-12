import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FolderPickerFeature
import Foundation
import Localization
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct DestinationPickerFeatureTests {
    private let serverURL = URL(string: TestHost.exampleURLString)!

    private nonisolated func folder(_ name: String, path: String = "") -> FileItem {
        FileItem(name: name, path: path, dateModified: MockDate.date, size: 0, kind: FileItem.directoryKind)
    }

    private nonisolated func file(_ name: String, path: String = "") -> FileItem {
        FileItem(name: name, path: path, dateModified: MockDate.date, size: 0, kind: TestKind.text)
    }

    private nonisolated func access() -> FileAccess {
        FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: false, canDownload: true)
    }

    private func finishLoad(_ state: inout DestinationPickerFeature.State, folders: [FileItem]) {
        state.phase = .loaded
        state.currentAccess = access()
        state.folders = IdentifiedArray(uniqueElements: folders)
    }

    @Test
    func onAppearLoadsFoldersOnlyDroppingFiles() async {
        let store = TestStore(
            initialState: DestinationPickerFeature.State(serverURL: serverURL, items: [file(TestFile.aText, path: TestFolder.inbox)])
        ) {
            DestinationPickerFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in
                BrowseResult(items: [folder(TestFolder.documents), file("readme.txt")], access: access(), path: "")
            }
        }

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.foldersResponse.success) { finishLoad(&$0, folders: [folder(TestFolder.documents)]) }
    }

    @Test
    func uploadModeConfirmStaysDisabledUntilTheFolderReportsUploadAccess() {
        let atRoot = DestinationPickerFeature.State(serverURL: serverURL, uploadStartingAt: "")
        #expect(atRoot.purpose == .upload)
        #expect(atRoot.canConfirm == false)

        var inFolder = DestinationPickerFeature.State(serverURL: serverURL, uploadStartingAt: TestFolder.documents)
        #expect(inFolder.directoryPath == TestFolder.documents)
        #expect(inFolder.canConfirm == false) // access not loaded yet

        inFolder.currentAccess = FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: false, canDownload: true)
        #expect(inFolder.canConfirm == true)

        inFolder.currentAccess = FileAccess(canRead: true, canWrite: true, canUpload: false, canDelete: true, canShare: false, canDownload: true)
        #expect(inFolder.canConfirm == false)
    }

    @Test
    func uploadModeConfirmEmitsTheChosenDestination() async {
        var state = DestinationPickerFeature.State(serverURL: serverURL, uploadStartingAt: TestFolder.documents)
        state.directoryPath = Constants.documentsReports
        state.currentAccess = FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: false, canDownload: true)

        let store = TestStore(initialState: state) { DestinationPickerFeature() }

        await store.send(.confirmTapped)
        await store.receive(.delegate(.confirmed(destination: Constants.documentsReports)))
    }

    @Test
    func folderTappedDrillsIntoTheChild() async {
        let store = TestStore(
            initialState: DestinationPickerFeature.State(serverURL: serverURL, items: [file(TestFile.aText, path: TestFolder.inbox)])
        ) {
            DestinationPickerFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, path in
                BrowseResult(
                    items: path == TestFolder.documents ? [folder(Constants.workFolder, path: TestFolder.documents)] : [folder(TestFolder.documents)],
                    access: access(), path: path
                )
            }
        }

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.foldersResponse.success) { finishLoad(&$0, folders: [folder(TestFolder.documents)]) }
        await store.send(.folderTapped(folder(TestFolder.documents))) {
            $0.directoryPath = TestFolder.documents
            $0.navigationHistory = [TestFolder.inbox]
            $0.phase = .loading
            $0.currentAccess = nil
        }
        await store.receive(\.foldersResponse.success) {
            finishLoad(&$0, folders: [folder(Constants.workFolder, path: TestFolder.documents)])
        }
    }

    @Test
    func drillingInTurnsCloseIntoBackAndBackStepsUpOneLevel() async {
        let store = TestStore(
            initialState: DestinationPickerFeature.State(serverURL: serverURL, uploadStartingAt: "")
        ) {
            DestinationPickerFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, path in
                BrowseResult(items: [folder(Constants.childFolder, path: path)], access: access(), path: path)
            }
        }

        #expect(store.state.canNavigateBack == false)

        await store.send(.folderTapped(folder(TestFolder.documents))) {
            $0.directoryPath = TestFolder.documents
            $0.navigationHistory = [""]
            $0.phase = .loading
            $0.currentAccess = nil
        }
        await store.receive(\.foldersResponse.success) { finishLoad(&$0, folders: [folder(Constants.childFolder, path: TestFolder.documents)]) }
        #expect(store.state.canNavigateBack == true)

        await store.send(.folderTapped(folder("Reports", path: TestFolder.documents))) {
            $0.directoryPath = Constants.documentsReports
            $0.navigationHistory = ["", TestFolder.documents]
            $0.phase = .loading
            $0.currentAccess = nil
        }
        await store.receive(\.foldersResponse.success) { finishLoad(&$0, folders: [folder(Constants.childFolder, path: Constants.documentsReports)]) }

        await store.send(.backTapped) {
            $0.directoryPath = TestFolder.documents
            $0.navigationHistory = [""]
            $0.phase = .loading
            $0.currentAccess = nil
        }
        await store.receive(\.foldersResponse.success) { finishLoad(&$0, folders: [folder(Constants.childFolder, path: TestFolder.documents)]) }

        await store.send(.backTapped) {
            $0.directoryPath = ""
            $0.navigationHistory = []
            $0.phase = .loading
            $0.currentAccess = nil
        }
        await store.receive(\.foldersResponse.success) { finishLoad(&$0, folders: [folder(Constants.childFolder, path: "")]) }
        #expect(store.state.canNavigateBack == false)
    }

    @Test
    func breadcrumbJumpTrimsTheBackTrailToThatFolder() async {
        var state = DestinationPickerFeature.State(serverURL: serverURL, uploadStartingAt: "")
        state.directoryPath = "A/B/C"
        state.navigationHistory = ["", "A", "A/B"]

        let store = TestStore(initialState: state) {
            DestinationPickerFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in BrowseResult(items: [], access: access(), path: "") }
        }

        await store.send(.breadcrumbTapped(path: "A")) {
            $0.directoryPath = "A"
            $0.navigationHistory = [""]
            $0.phase = .loading
            $0.currentAccess = nil
        }
        await store.receive(\.foldersResponse.success) { finishLoad(&$0, folders: []) }
    }

    @Test
    func breadcrumbTappedJumpsStraightToThatPath() async {
        var state = DestinationPickerFeature.State(serverURL: serverURL, items: [file(TestFile.aText, path: TestFolder.inbox)])
        state.directoryPath = TestPath.documentsWork

        let store = TestStore(initialState: state) {
            DestinationPickerFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in BrowseResult(items: [], access: access(), path: "") }
        }

        await store.send(.breadcrumbTapped(path: TestFolder.documents)) {
            $0.directoryPath = TestFolder.documents
            $0.phase = .loading
            $0.currentAccess = nil
        }
        await store.receive(\.foldersResponse.success) { finishLoad(&$0, folders: []) }
    }

    @Test
    func loadFailureSurfacesAReadableErrorAndRetryReloads() async {
        let store = TestStore(
            initialState: DestinationPickerFeature.State(serverURL: serverURL, items: [file(TestFile.aText, path: TestFolder.inbox)])
        ) {
            DestinationPickerFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in throw FilesClientError.server(statusCode: 500) }
        }

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.foldersResponse.failure) {
            $0.phase = .failed(L10n.Browse.destinationPickerLoadFailed)
        }
        await store.send(.retryTapped) { $0.phase = .loading }
        await store.receive(\.foldersResponse.failure) {
            $0.phase = .failed(L10n.Browse.destinationPickerLoadFailed)
        }
    }

    @Test
    func confirmTappedEmitsTheChosenDestination() async {
        var state = DestinationPickerFeature.State(serverURL: serverURL, items: [file(TestFile.aText, path: TestFolder.inbox)])
        state.directoryPath = TestFolder.documents

        let store = TestStore(initialState: state) { DestinationPickerFeature() }

        await store.send(.confirmTapped)
        await store.receive(.delegate(.confirmed(destination: TestFolder.documents)))
    }

    @Test
    func confirmIsBlockedIntoTheItemsOwnParentAndIntoItself() {
        var parent = DestinationPickerFeature.State(serverURL: serverURL, items: [file(TestFile.aText, path: TestFolder.inbox)])
        parent.directoryPath = TestFolder.inbox
        #expect(parent.canConfirm == false)

        var intoItself = DestinationPickerFeature.State(serverURL: serverURL, items: [folder(TestFolder.photos, path: TestFolder.media)])
        intoItself.directoryPath = TestPath.mediaPhotos2024
        #expect(intoItself.canConfirm == false)

        var ok = DestinationPickerFeature.State(serverURL: serverURL, items: [file(TestFile.aText, path: TestFolder.inbox)])
        ok.directoryPath = TestFolder.documents
        #expect(ok.canConfirm == true)
    }

    @Test
    func rootIsNeverAValidDestination() {
        let state = DestinationPickerFeature.State(serverURL: serverURL, items: [file(TestFile.aText, path: "")])
        #expect(state.directoryPath == "")
        #expect(state.canConfirm == false)
    }

    @Test
    func opensInTheFolderTheItemsAlreadyLiveIn() {
        let state = DestinationPickerFeature.State(
            serverURL: serverURL, items: [file(TestFile.aText, path: Constants.documentsReports)]
        )
        #expect(state.directoryPath == Constants.documentsReports)
        // Confirming right here would be a no-op move into the item's own parent.
        #expect(state.canConfirm == false)
    }

    @Test
    func searchRunsRecursivelyScopedToCurrentFolderAndClearsOnDrillDown() async {
        let clock = TestClock()
        let searchScope = LockIsolated<String?>(nil)
        let store = TestStore(
            initialState: DestinationPickerFeature.State(serverURL: serverURL, items: [file(TestFile.aText, path: TestFolder.media)])
        ) {
            DestinationPickerFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.filesClient.browse = { _, _ in
                BrowseResult(items: [folder(TestFolder.photos, path: TestFolder.media)], access: access(), path: TestFolder.media)
            }
            $0.filesClient.search = { _, path, _, _ in
                searchScope.setValue(path)
                return [
                    SearchResultItem(name: Constants.summerFolder, path: TestPath.mediaPhotos2024, kind: "dir"),
                    SearchResultItem(name: TestFile.notes, path: TestPath.mediaPhotos, kind: TestKind.text),
                ]
            }
        }

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.foldersResponse.success) { finishLoad(&$0, folders: [folder(TestFolder.photos, path: TestFolder.media)]) }

        await store.send(.searchQueryChanged("sum")) {
            $0.searchQuery = "sum"
            $0.isSearching = true
        }
        await clock.advance(by: FilesClient.searchDebounce)
        await store.receive(\.searchResultsResponse.success) {
            $0.isSearching = false
            $0.searchResults = [SearchResultItem(name: Constants.summerFolder, path: TestPath.mediaPhotos2024, kind: "dir")]
        }
        #expect(searchScope.value == TestFolder.media)

        await store.send(.searchResultTapped(SearchResultItem(name: Constants.summerFolder, path: TestPath.mediaPhotos2024, kind: "dir"))) {
            $0.directoryPath = "Media/Photos/2024/Summer"
            $0.searchQuery = ""
            $0.searchResults = nil
            $0.navigationHistory = [TestFolder.media]
            $0.phase = .loading
            $0.currentAccess = nil
        }
        await store.receive(\.foldersResponse.success) { finishLoad(&$0, folders: [folder(TestFolder.photos, path: TestFolder.media)]) }
    }

    /// A picker in `Media` whose search records each term it was asked and answers `Summer`.
    private func searchingStore(clock: TestClock<Duration>, queries: LockIsolated<[String]>) -> TestStoreOf<DestinationPickerFeature> {
        TestStore(
            initialState: DestinationPickerFeature.State(serverURL: serverURL, items: [file(TestFile.aText, path: TestFolder.media)])
        ) {
            DestinationPickerFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.filesClient.search = { _, _, query, _ in
                queries.withValue { $0.append(query) }
                return [SearchResultItem(name: Constants.summerFolder, path: TestFolder.media, kind: "dir")]
            }
        }
    }

    @Test("Typing waits 350 ms before searching folders, and not a moment less")
    func searchWaitsOutTheDebounceExactly() async {
        let clock = TestClock()
        let queries = LockIsolated<[String]>([])
        let store = searchingStore(clock: clock, queries: queries)

        await store.send(.searchQueryChanged(Constants.searchTerm)) {
            $0.searchQuery = Constants.searchTerm
            $0.isSearching = true
        }
        await clock.advance(by: TestSearchTiming.justBeforeDebounce)
        #expect(queries.value.isEmpty)

        await clock.advance(by: TestSearchTiming.lastMoment)
        await store.receive(\.searchResultsResponse.success) {
            $0.isSearching = false
            $0.searchResults = [SearchResultItem(name: Constants.summerFolder, path: TestFolder.media, kind: "dir")]
        }
        #expect(queries.value == [Constants.searchTerm])
    }

    @Test("A typed space leaves the server's term unchanged, so the pending search keeps its wait")
    func aTypedSpaceKeepsThePendingSearch() async {
        let clock = TestClock()
        let queries = LockIsolated<[String]>([])
        let store = searchingStore(clock: clock, queries: queries)

        await store.send(.searchQueryChanged(Constants.searchTerm)) {
            $0.searchQuery = Constants.searchTerm
            $0.isSearching = true
        }
        await clock.advance(by: TestSearchTiming.partOfDebounce)
        await store.send(.searchQueryChanged(Constants.searchTermWithSpace)) {
            $0.searchQuery = Constants.searchTermWithSpace
        }
        await clock.advance(by: TestSearchTiming.restOfDebounce)
        await store.receive(\.searchResultsResponse.success) {
            $0.isSearching = false
            $0.searchResults = [SearchResultItem(name: Constants.summerFolder, path: TestFolder.media, kind: "dir")]
        }
        #expect(queries.value == [Constants.searchTerm])
    }
}

private enum Constants {
    static let searchTerm = "sum"
    static let searchTermWithSpace = "sum "
    static let summerFolder = "Summer"
    static let workFolder = "Work"
    static let childFolder = "Child"
    static let documentsReports = "Documents/Reports"
}
