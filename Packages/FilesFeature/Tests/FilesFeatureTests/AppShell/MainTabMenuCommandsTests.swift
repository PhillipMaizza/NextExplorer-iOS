import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct MainTabMenuCommandsTests: MainTabTestSupport {
    @Test("Refresh on the Downloads tab reloads the downloads")
    func refreshSelectedTabRefreshesTheDownloadsTabWhenItIsSelected() async {
        let store = makeStore(makeState { $0.selectedTab = .downloads }) {
            $0.localDownloadStore.list = { _ in [] }
        }

        await store.send(.refreshSelectedTab)
        await store.receive(\.downloads.refreshButtonTapped) {
            $0.downloads.phase = .loading
        }
        await store.receive(\.downloads.downloadsResponse.success) {
            $0.downloads.phase = .loaded
        }
    }

    @Test("Refresh on the Browse tab reloads the folder on screen")
    func refreshSelectedTabRoutesToTheVisibleBrowseFolder() async {
        let store = makeStore { $0.serveEmptyFolders() }

        await store.send(.refreshSelectedTab)
        await store.receive(\.browse.refreshVisibleFolder)
        await store.receive(\.browse.root.refreshButtonTapped) {
            $0.browse.root.phase = .loading
        }
        await store.receive(\.browse.root.itemsResponse.success) {
            $0.browse.root.phase = .loaded
            $0.browse.root.access = BrowseTestSupport.readOnlyAccess
        }
        await store.receive(\.browse.root.favoritesResponse) {
            $0.browse.root.hasLoadedFavorites = true
        }
    }

    @Test("Refresh on Settings does nothing")
    func refreshSelectedTabDoesNothingOnSettings() async {
        let store = makeStore(makeState { $0.selectedTab = .settings })

        await store.send(.refreshSelectedTab)
    }

    @Test("New Folder is ignored outside Browse")
    func newFolderRequestedIsIgnoredOutsideBrowse() async {
        let store = makeStore(makeState { $0.selectedTab = .favorites })

        await store.send(.newFolderRequested)
    }

    @Test("New Folder at the Browse root is forwarded and then refused, the root is not writable")
    func newFolderRequestedForwardsToBrowse() async {
        let store = makeStore()

        await store.send(.newFolderRequested)
        await store.receive(\.browse.newFolderInVisibleFolder)
    }

    #if os(macOS)
        @Test("A folder stack popping while another section is shown is ignored")
        func aFolderStackPopWhileAnotherSectionIsShownIsIgnored() async {
            var state = makeState()
            state.browse.path.append(BrowseFeature.State(
                serverURL: serverURL,
                directoryPath: TestFolder.documents,
                title: TestFolder.documents
            ))
            state.selectedTab = .shared
            let id = state.browse.path.ids[0]
            let store = makeStore(state)

            await store.send(.browse(.path(.popFrom(id: id))))
        }

        @Test("Back in the visible Browse still pops and offers Forward")
        func backInTheVisibleBrowseStillPopsAndOffersForward() async {
            var state = makeState()
            let documents = BrowseFeature.State(
                serverURL: serverURL,
                directoryPath: TestFolder.documents,
                title: TestFolder.documents
            )
            state.browse.path.append(documents)
            let id = state.browse.path.ids[0]
            let store = makeStore(state)

            await store.send(.browse(.path(.popFrom(id: id)))) {
                $0.browse.path = StackState()
                $0.browse.forwardStack = [documents]
            }
        }
    #endif
}
