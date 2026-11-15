import ComposableArchitecture
import CoreModels
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

/// The iPad Edit menu acting on the selection of the folder on screen.
@Suite(.isolatedDependencies)
@MainActor
struct BrowseTabFolderCommandTests: MainTabTestSupport {
    private let photo = BrowseFixtures.file(TestFile.aPhoto, in: TestPath.docsLowercase, size: 1)
    private let notes = BrowseFixtures.file(TestFile.notes, in: TestPath.docsLowercase, size: 1)

    private func tabState(root items: [FileItem], pushing pushed: BrowseFeature.State? = nil) -> BrowseTabFeature
        .State
    {
        var state = BrowseTabFeature.State(serverURL: BrowseTestSupport.serverURL)
        state.root = BrowseFixtures.loadedState("", items: items)
        if let pushed {
            state.path.append(pushed)
        }
        return state
    }

    @Test("Select All outside select mode enters it, then selects every item")
    func selectAllEntersSelectMode() async {
        let store = TestStore(initialState: tabState(root: [photo, notes])) { BrowseTabFeature() }

        await store.send(.commandInVisibleFolder(.selectAll))
        await store.receive(\.root.selectModeToggled) { $0.root.isSelecting = true }
        await store.receive(\.root.selectAllTapped) { $0.root.selectedItemIDs = [photo.id, notes.id] }
    }

    @Test("Select All in a folder with nothing to select leaves select mode off")
    func selectAllInAnEmptyFolder() async {
        let store = TestStore(initialState: tabState(root: [])) { BrowseTabFeature() }

        await store.send(.commandInVisibleFolder(.selectAll))
    }

    @Test("Copy goes to the pushed folder on screen, not the root under it")
    func copyReachesTheVisibleFolder() async {
        var pushed = BrowseFixtures.loadedState(TestPath.docsLowercase, items: [photo, notes])
        pushed.isSelecting = true
        pushed.selectedItemIDs = [photo.id]
        let store = TestStore(initialState: tabState(root: [], pushing: pushed)) { BrowseTabFeature() }
        let id = store.state.path.ids[0]

        // The clipboard is shared state, so its change shows at the first assertion.
        await store.send(.commandInVisibleFolder(.copy)) {
            $0.root.$clipboard.withLock { $0 = FileClipboard(items: [photo], operation: .copy) }
        }
        await store.receive(\.path[id: id].copySelectionTapped) {
            $0.path[id: id]?.clipboardStagedMessage = L10n.Browse.clipboardCopiedOne(TestFile.aPhoto)
        }
    }

    @Test("An Edit menu command outside Browse does nothing")
    func folderCommandOutsideBrowse() async {
        let store = makeStore(makeState { $0.selectedTab = .favorites })

        await store.send(.folderCommandRequested(.copy))
    }
}
