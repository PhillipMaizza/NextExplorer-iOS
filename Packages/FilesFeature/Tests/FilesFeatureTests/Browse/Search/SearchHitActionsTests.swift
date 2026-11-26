import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct SearchHitActionsTests {
    private enum Constants {
        static let renamedName = "summary.pdf"
        static let archiveName = "report.zip"
    }

    private let hit = SearchResultItem(
        name: TestFile.report,
        path: TestFolder.docs,
        kind: SearchResultItem.fileKind,
        isNameMatch: true
    )
    private let folderHit = SearchResultItem(
        name: TestFolder.photos,
        path: TestFolder.docs,
        kind: SearchResultItem.directoryKind,
        isNameMatch: true
    )

    private func searching() -> BrowseFeature.State {
        var state = BrowseFixtures.loadedState(TestFolder.documents)
        state.searchQuery = TestSearch.term
        state.searchResults = [hit, folderHit]
        state.searchAnsweredTerm = TestSearch.term
        state.searchPhase = .loaded
        return state
    }

    @Test("Deleting a hit takes it out of the results")
    func deletingAHitDropsIt() async {
        let store = BrowseFixtures.store(searching())

        await store.send(.deleteResponse(.success(BrowseFeature.DeleteResult(removedIDs: [hit.id])))) {
            $0.searchResults = [folderHit]
        }
    }

    @Test("Renaming a hit shows its new name in the results")
    func renamingAHitRenamesTheResult() async {
        let store = BrowseFixtures.store(searching())
        let renamed = BrowseFixtures.file(Constants.renamedName, in: TestFolder.docs)
        let renamedHit = SearchResultItem(
            name: Constants.renamedName,
            path: TestFolder.docs,
            kind: SearchResultItem.fileKind,
            isNameMatch: true
        )

        await store.send(.renameResponse(.success(.init(originalID: hit.id, renamed: renamed)))) {
            $0.searchResults = [renamedHit, folderHit]
            $0.$undoStack.withLock { $0.record(FileUndoEntry(.renamed(renamed, previousName: TestFile.report))) }
        }
    }

    @Test("Compressing a hit elsewhere adds no row here and searches again")
    func compressingAHitElsewhereSearchesAgain() async {
        let archive = BrowseFixtures.file(Constants.archiveName, in: TestFolder.docs)
        let hit = hit
        let store = BrowseFixtures.store(searching()) {
            $0.filesClient.search = { _, _, _, _ in [hit] }
        }

        await store.send(.compressResponse(.success(archive))) {
            $0.searchPhase = .loading
        }
        await store.receive(\.searchResultsResponse) {
            $0.searchPhase = .loaded
            $0.searchResults = [hit]
        }
    }

    @Test("A hit from another folder is not kept offline: that folder's download rights are unknown here")
    func aHitFromAnotherFolderIsNotKeptOffline() async {
        let store = BrowseFixtures.store(searching())

        await store.send(.offlineToggleTapped(hit.actionItem))
    }

    @Test("Open on a folder hit opens it the way the result does, ending the search")
    func openOnAHitOpensItLikeTheResult() async {
        let store = BrowseFixtures.store(searching())

        await store.send(.rowTapped(folderHit.actionItem))
        await store.receive(\.searchResultTapped) {
            $0.searchQuery = ""
            $0.searchResults = nil
            $0.searchAnsweredTerm = nil
            $0.searchPhase = .idle
        }
        await store.receive(.delegate(.openPath(path: folderHit.id, title: folderHit.name)))
    }
}
