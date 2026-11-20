import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FolderPickerFeature
import Foundation
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct DestinationPickerReplaceTests: DestinationPickerTestHelpers {
    private func source() -> FileItem {
        file(TestFile.aText, path: TestFolder.inbox)
    }

    private func loadedState() -> DestinationPickerFeature.State {
        var state = DestinationPickerFeature.State(serverURL: serverURL, replacing: source())
        finishLoad(&state, folders: [folder(TestFolder.documents), file(TestFile.bText, path: TestFolder.inbox)])
        return state
    }

    @Test
    func itStartsInTheSourceFilesFolderWithTheFileAsTheOnlyItem() {
        let state = DestinationPickerFeature.State(serverURL: serverURL, replacing: source())
        #expect(state.purpose == .replaceFile)
        #expect(state.directoryPath == TestFolder.inbox)
        #expect(state.items == [source()])
    }

    @Test
    func theListingKeepsFilesFoldersFirstAndLeavesOutTheSourceFile() async {
        let store = TestStore(initialState: DestinationPickerFeature.State(serverURL: serverURL, replacing: source())) {
            DestinationPickerFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, path in
                BrowseResult(
                    items: [
                        file(TestFile.bText, path: path),
                        file(TestFile.aText, path: path),
                        folder(TestFolder.documents, path: path),
                    ],
                    access: access(),
                    path: path
                )
            }
            $0.filesClient.recentDestinations = { _ in [] }
        }

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.foldersResponse.success) {
            finishLoad(&$0, folders: [
                folder(TestFolder.documents, path: TestFolder.inbox),
                file(TestFile.bText, path: TestFolder.inbox),
            ])
        }
        await store.receive(\.recentsResponse)
    }

    @Test
    func pickingAFileEnablesConfirmAndAFolderRowDoesNot() async {
        let picked = file(TestFile.bText, path: TestFolder.inbox)
        let store = TestStore(initialState: loadedState()) { DestinationPickerFeature() }
        #expect(!store.state.canConfirm)

        await store.send(.rowSelected(picked.id)) { $0.selectedFilePath = picked.id }
        #expect(store.state.canConfirm)

        await store.send(.rowSelected(folder(TestFolder.documents).id)) { $0.selectedFilePath = nil }
        #expect(!store.state.canConfirm)
    }

    @Test
    func confirmNeedsWriteAccessToTheFolder() {
        var state = loadedState()
        state.selectedFilePath = file(TestFile.bText, path: TestFolder.inbox).id
        state.currentAccess = FileAccess(
            canRead: true,
            canWrite: false,
            canUpload: false,
            canDelete: false,
            canShare: false,
            canDownload: true
        )
        #expect(!state.canConfirm)
    }

    @Test
    func confirmHandsBackThePickedFilesPath() async {
        let picked = file(TestFile.bText, path: TestFolder.inbox)
        var state = loadedState()
        state.selectedFilePath = picked.id
        let store = TestStore(initialState: state) { DestinationPickerFeature() }

        await store.send(.confirmTapped)
        await store.receive(.delegate(.confirmed(destination: picked.id)))
    }

    @Test
    func openingAFolderClearsThePickedFile() async {
        var state = loadedState()
        state.selectedFilePath = file(TestFile.bText, path: TestFolder.inbox).id
        let store = TestStore(initialState: state) { DestinationPickerFeature() } withDependencies: {
            $0.filesClient.browse = { _, path in BrowseResult(items: [], access: access(), path: path) }
        }

        await store.send(.folderTapped(folder(TestFolder.documents))) {
            $0.directoryPath = TestFolder.documents
            $0.navigationHistory = [TestFolder.inbox]
            $0.selectedFilePath = nil
            $0.phase = .loading
            $0.currentAccess = nil
        }
        await store.receive(\.foldersResponse.success) { finishLoad(&$0, folders: []) }
    }

    @Test
    func rowSelectionDoesNothingOutsideTheFileChooser() async {
        var state = DestinationPickerFeature.State(serverURL: serverURL, items: [source()])
        finishLoad(&state, folders: [folder(TestFolder.documents)])
        let store = TestStore(initialState: state) { DestinationPickerFeature() }

        await store.send(.rowSelected(TestFolder.documents))
        #expect(store.state.selectedFilePath == nil)
    }

    @Test
    func confirmWithNoPickedFileSendsNothing() async {
        let store = TestStore(initialState: loadedState()) { DestinationPickerFeature() }

        await store.send(.confirmTapped)
    }

    @Test
    func searchOffersFilesButNotTheSourceFileWhenReplacing() async {
        var state = loadedState()
        state.searchQuery = "note"
        state.searchPhase = .loading
        let store = TestStore(initialState: state) { DestinationPickerFeature() }
        let hit = SearchResultItem(name: TestFile.bText, path: TestFolder.documents, kind: TestKind.text)
        let sourceHit = SearchResultItem(name: TestFile.aText, path: TestFolder.inbox, kind: TestKind.text)

        await store.send(.searchResultsResponse(.success([hit, sourceHit]))) {
            $0.searchPhase = .loaded
            $0.searchResults = [hit]
        }
    }

    @Test
    func tappingAFileResultOpensItsFolderAndPicksIt() async {
        let picked = file(TestFile.bText, path: TestFolder.documents)
        var state = loadedState()
        state.searchQuery = "note"
        state.searchResults = [SearchResultItem(name: TestFile.bText, path: TestFolder.documents, kind: TestKind.text)]
        let store = TestStore(initialState: state) { DestinationPickerFeature() } withDependencies: {
            $0.filesClient.browse = { _, path in BrowseResult(items: [picked], access: access(), path: path) }
        }
        let hit = SearchResultItem(name: TestFile.bText, path: TestFolder.documents, kind: TestKind.text)

        await store.send(.searchResultTapped(hit)) {
            $0.directoryPath = TestFolder.documents
            $0.navigationHistory = [TestFolder.inbox]
            $0.searchQuery = ""
            $0.searchResults = []
            $0.pendingFileSelection = picked.id
            $0.phase = .loading
            $0.currentAccess = nil
            $0.selectedFilePath = nil
        }
        await store.receive(\.foldersResponse.success) {
            finishLoad(&$0, folders: [picked])
            $0.selectedFilePath = picked.id
            $0.pendingFileSelection = nil
        }
    }
}
