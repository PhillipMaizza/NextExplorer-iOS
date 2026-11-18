import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// Taking the last items of a kept folder off the device takes the folder off with them: the
/// confirmation says so, and the Offline tab closes the screen.
@Suite(.isolatedDependencies)
@MainActor
struct BrowseKeptFolderEmptiedTests {
    private enum Constants {
        static let hiddenName = ".hidden"
    }

    private let photo = BrowseFixtures.file(TestFile.aPhoto, in: TestPath.docsLowercase, size: 1)
    private let notes = BrowseFixtures.file(TestFile.notes, in: TestPath.docsLowercase, size: 1)
    private let hidden = BrowseFixtures.file(Constants.hiddenName, in: TestPath.docsLowercase, size: 1)

    private func keptScreen(_ items: [FileItem], isKeptOffline: Bool = true) -> BrowseFeature.State {
        var state = BrowseFixtures.loadedState(TestPath.docsLowercase, items: items)
        state.title = TestFolder.docs
        state.isKeptOffline = isKeptOffline
        state.offlineItemIDs = Set(items.map(\.id))
        return state
    }

    private func pinnedDocs() -> OfflineFileStore {
        let offline = OfflineFileStore.inMemory()
        offline.setPinnedRoots([OfflinePinnedRoot(path: TestPath.docsLowercase, isDirectory: true)])
        return offline
    }

    @Test("Removing the last item asks to take the folder off too, then unpins it and closes the screen")
    func theLastItemTakesTheFolderOff() async {
        let offline = pinnedDocs()
        let store = BrowseFixtures.store(keptScreen([photo])) { $0.offlineFileStore = offline }

        await store.send(.offlineToggleTapped(photo)) {
            $0.offlineRemoval = OfflineRemovalRequest(
                paths: [TestPath.docsLowercase],
                names: [TestFile.aPhoto],
                emptiedFolderName: TestFolder.docs
            )
        }
        await store.send(.offlineRemovalConfirmed) {
            $0.offlineRemoval = nil
            $0.offlineItemIDs = []
        }
        await store.receive(.delegate(.offlineUnpinRequested(path: TestPath.docsLowercase)))
        await store.receive(.delegate(.keptFolderEmptied(removedPaths: [TestPath.docsLowercase])))
    }

    @Test("A hidden file the screen does not show does not keep the folder")
    func hiddenFilesDoNotCount() async {
        let store = BrowseFixtures.store(keptScreen([photo, hidden])) { $0.offlineFileStore = pinnedDocs() }

        await store.send(.offlineToggleTapped(photo)) {
            $0.offlineRemoval = OfflineRemovalRequest(
                paths: [TestPath.docsLowercase],
                names: [TestFile.aPhoto],
                emptiedFolderName: TestFolder.docs
            )
        }
    }

    @Test("With other items left, only the picked one comes off")
    func otherItemsKeepTheFolder() async {
        let store = BrowseFixtures.store(keptScreen([photo, notes])) { $0.offlineFileStore = pinnedDocs() }

        await store.send(.offlineToggleTapped(photo)) {
            $0.offlineRemoval = OfflineRemovalRequest(paths: [photo.id], names: [TestFile.aPhoto])
        }
        await store.send(.offlineRemovalConfirmed) {
            $0.offlineRemoval = nil
            $0.offlineItemIDs = [notes.id]
            $0.items = [notes]
        }
        await store.receive(.delegate(.offlineUnpinRequested(path: photo.id)))
    }

    @Test("A Browse screen never takes its folder off, even with every item picked")
    func aLiveScreenKeepsTheFolder() async {
        let store = BrowseFixtures.store(keptScreen([photo], isKeptOffline: false)) {
            $0.offlineFileStore = pinnedDocs()
        }

        await store.send(.offlineToggleTapped(photo)) {
            $0.offlineRemoval = OfflineRemovalRequest(paths: [photo.id], names: [TestFile.aPhoto])
        }
    }

    @Test("A screen below the closed one stops listing what came off")
    func aScreenBelowDropsTheRemovedFolder() async {
        let folder = BrowseFixtures.folder(TestFolder.docs, in: "")
        var state = BrowseFixtures.loadedState("", items: [folder, notes])
        state.isKeptOffline = true
        state.offlineItemIDs = [folder.id, notes.id]
        state.selectedItemIDs = [folder.id]
        let store = BrowseFixtures.store(state)

        await store.send(.keptItemsRemoved(paths: [folder.id])) {
            $0.offlineItemIDs = [notes.id]
            $0.items = [notes]
            $0.selectedItemIDs = []
        }
    }

    @Test("The Offline tab closes the emptied screen and tells the ones below")
    func theOfflineTabClosesTheEmptiedScreen() async {
        var state = OfflineTabFeature.State(serverURL: BrowseTestSupport.serverURL)
        var parent = BrowseFixtures.loadedState("", items: [])
        parent.isKeptOffline = true
        state.path.append(parent)
        state.path.append(keptScreen([]))
        let store = TestStore(initialState: state) { OfflineTabFeature() }

        await store.send(.path(.element(id: 1, action: .delegate(.keptFolderEmptied(
            removedPaths: [TestPath.docsLowercase]
        ))))) {
            $0.path.pop(from: 1)
        }
        await store.receive(\.path[id: 0].keptItemsRemoved)
    }
}
