import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FolderPickerFeature
import Foundation
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct DestinationPickerRecentsTests: DestinationPickerTestHelpers {
    @Test
    func recentsLoadAfterTheFoldersWithBlanksAndRepeatsDropped() async {
        let store = TestStore(
            initialState: DestinationPickerFeature.State(
                serverURL: serverURL,
                items: [file(TestFile.aText, path: TestFolder.inbox)]
            )
        ) {
            DestinationPickerFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in BrowseResult(items: [], access: access(), path: "") }
            $0.filesClient
                .recentDestinations = { _ in [TestFolder.documents, "", TestFolder.documents, TestFolder.media] }
        }

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.foldersResponse.success) { finishLoad(&$0, folders: []) }
        await store.receive(\.recentsResponse) { $0.recents = [TestFolder.documents, TestFolder.media] }
        await store.receive(\.locationsResponse)
    }

    @Test
    func aFailedRecentsLoadLeavesTheListEmptyWithoutAnError() async {
        let store = TestStore(
            initialState: DestinationPickerFeature.State(
                serverURL: serverURL,
                items: [file(TestFile.aText, path: TestFolder.inbox)]
            )
        ) {
            DestinationPickerFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in BrowseResult(items: [], access: access(), path: "") }
            $0.filesClient.recentDestinations = { _ in throw FilesClientError.offline }
        }

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.foldersResponse.success) { finishLoad(&$0, folders: []) }
        await store.receive(\.recentsResponse)
        await store.receive(\.locationsResponse)
        #expect(store.state.recents.isEmpty)
        #expect(store.state.phase == .loaded)
    }

    @Test
    func tappingARecentDrillsInLikeAFolderAndBackReturns() async {
        var state = DestinationPickerFeature.State(
            serverURL: serverURL,
            items: [file(TestFile.aText, path: TestFolder.inbox)]
        )
        state.recents = [TestFolder.documents]
        finishLoad(&state, folders: [])
        let store = TestStore(initialState: state) {
            DestinationPickerFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, path in BrowseResult(items: [], access: access(), path: path) }
        }

        await store.send(.recentTapped(TestFolder.documents)) {
            $0.directoryPath = TestFolder.documents
            $0.navigationHistory = [TestFolder.inbox]
            $0.phase = .loading
            $0.currentAccess = nil
        }
        await store.receive(\.foldersResponse.success) { finishLoad(&$0, folders: []) }
        #expect(store.state.showsRecentsSection == false)
    }

    @Test
    func tappingTheFolderAlreadyOnScreenDoesNothing() async {
        var state = DestinationPickerFeature.State(
            serverURL: serverURL,
            items: [file(TestFile.aText, path: TestFolder.inbox)]
        )
        state.recents = [TestFolder.inbox]
        let store = TestStore(initialState: state) { DestinationPickerFeature() }

        await store.send(.recentTapped(TestFolder.inbox))
        #expect(state.displayedRecents.isEmpty)
    }

    @Test
    func theRecentSectionShowsOnlyOnTheOpeningFolderWithNothingTyped() {
        var state = DestinationPickerFeature.State(
            serverURL: serverURL,
            items: [file(TestFile.aText, path: TestFolder.inbox)]
        )
        #expect(!state.showsRecentsSection)

        state.recents = [TestFolder.documents]
        #expect(state.showsRecentsSection)

        state.searchQuery = "Do"
        #expect(!state.showsRecentsSection)
        state.searchQuery = ""

        state.navigationHistory = [TestFolder.inbox]
        #expect(!state.showsRecentsSection)
    }
}
