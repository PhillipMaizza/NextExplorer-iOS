import ComposableArchitecture
import CoreModels
@testable import FilesFeature
import Testing
import TestUtils

@MainActor
@Suite(.isolatedDependencies)
struct MainTabHistoryTests {
    private func folder(_ path: String) -> BrowseFeature.State {
        BrowseFeature.State(serverURL: TestHost.serverURL, directoryPath: path, title: path)
    }

    @Test
    func backAndForwardFollowTheVisibleTab() {
        var state = MainTabFeature.State(serverURL: TestHost.serverURL, user: User.preview)
        #expect(!state.canGoBack)
        #expect(!state.canGoForward)

        state.browse.path.append(folder("docs"))
        #expect(state.canGoBack)

        state.browse.goBack()
        #expect(!state.canGoBack)
        #expect(state.canGoForward)

        state.selectedTab = .shared
        #expect(!state.canGoBack)
        #expect(!state.canGoForward)
    }

    @Test
    func backInTrashClimbsThenClosesTheDeletedFolder() async {
        var state = MainTabFeature.State(serverURL: TestHost.serverURL, user: User.preview)
        state.selectedTab = .trash
        #expect(!state.canGoBack)

        let deleted = TrashItem(id: "t2", name: "Photos", isDirectory: true)
        state.trash.folder = TrashFolderFeature.State(serverURL: TestHost.serverURL, item: deleted)
        #expect(state.canGoBack)

        let store = TestStore(initialState: state) { MainTabFeature() }
        await store.send(.backRequested)
        await store.receive(\.trash.folder.dismiss) {
            $0.trash.folder = nil
        }
        #expect(!store.state.canGoBack)
    }

    @Test
    func backClosesTheTrashBeforeLeavingAFolder() async {
        var state = BrowseTabFeature.State(serverURL: TestHost.serverURL)
        state.path.append(folder("docs"))
        state.trash = TrashFeature.State(serverURL: TestHost.serverURL)
        #expect(state.canGoBackFromScreen)

        let store = TestStore(initialState: state) { BrowseTabFeature() }
        await store.send(.goBack) {
            $0.trash = nil
        }
    }
}
