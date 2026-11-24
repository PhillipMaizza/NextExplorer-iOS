import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FolderPickerFeature
import Foundation
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct DestinationPickerSelectedFolderTests: DestinationPickerTestHelpers {
    private var documents: FileItem {
        folder(TestFolder.documents)
    }

    private var notes: FileItem {
        file(TestFile.notes)
    }

    private var inboxResult: SearchResultItem {
        SearchResultItem(name: TestFolder.inbox, path: TestFolder.documents, kind: SearchResultItem.directoryKind)
    }

    private func loadedState(items: [FileItem], isCopy: Bool = false) -> DestinationPickerFeature.State {
        var state = DestinationPickerFeature.State(serverURL: serverURL, items: items, isCopy: isCopy)
        finishLoad(&state, folders: [documents, notes])
        return state
    }

    @Test("A selected folder is where Move Here moves to")
    func aSelectedFolderIsTheMoveDestination() async {
        let store = TestStore(initialState: loadedState(items: [file(TestFile.aText, path: TestFolder.inbox)])) {
            DestinationPickerFeature()
        }

        await store.send(.rowSelected(documents.id)) {
            $0.selectedFolderPath = documents.id
        }
        await store.send(.confirmTapped)
        await store.receive(.delegate(.confirmed(destination: documents.id)))
    }

    @Test("A selected search result folder is where Copy Here copies to")
    func aSelectedSearchResultIsTheCopyDestination() async {
        var state = loadedState(items: [file(TestFile.aText, path: TestFolder.inbox)], isCopy: true)
        state.searchResults = [inboxResult]
        let store = TestStore(initialState: state) { DestinationPickerFeature() }

        await store.send(.rowSelected(inboxResult.id)) {
            $0.selectedFolderPath = inboxResult.id
        }
        await store.send(.confirmTapped)
        await store.receive(.delegate(.confirmed(destination: inboxResult.id)))
    }

    @Test("A file or an item being moved is never the destination")
    func aFileOrAMovedFolderIsNoDestination() async {
        let store = TestStore(initialState: loadedState(items: [documents])) { DestinationPickerFeature() }

        await store.send(.rowSelected(notes.id))
        #expect(store.state.transferDestination == "")
        await store.send(.rowSelected(documents.id)) {
            $0.selectedFolderPath = documents.id
        }
        #expect(!store.state.canConfirm)
    }

    @Test("Typing a new search drops the selection")
    func typingASearchDropsTheSelection() async {
        var state = loadedState(items: [file(TestFile.aText, path: TestFolder.inbox)])
        state.selectedFolderPath = documents.id
        let store = TestStore(initialState: state) { DestinationPickerFeature() }

        await store.send(.searchQueryChanged(shortSearchTerm)) {
            $0.searchQuery = shortSearchTerm
            $0.selectedFolderPath = nil
        }
    }

    @Test("Opening another folder drops the selection")
    func openingAFolderDropsTheSelection() async {
        var state = loadedState(items: [file(TestFile.aText, path: TestFolder.inbox)])
        state.selectedFolderPath = documents.id
        let store = TestStore(initialState: state) { DestinationPickerFeature() } withDependencies: {
            $0.filesClient.browse = { _, path in BrowseResult(items: [], access: access(), path: path) }
        }

        await store.send(.folderTapped(documents)) {
            $0.directoryPath = documents.id
            $0.navigationHistory = [TestFolder.inbox]
            $0.selectedFolderPath = nil
            $0.phase = .loading
            $0.currentAccess = nil
        }
        await store.receive(\.foldersResponse.success) { finishLoad(&$0, folders: []) }
    }
}
