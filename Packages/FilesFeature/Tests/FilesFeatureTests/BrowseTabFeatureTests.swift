import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Testing

@testable import FilesFeature

@MainActor
@Suite
struct BrowseTabFeatureTests {
    private let serverURL = URL(string: "https://example.com")!

    // MARK: Happy path

    @Test
    func openingAFolderFromTheRootPushesItOntoThePathStack() async {
        let item = FileItem(name: "Photos", path: "", dateModified: Date(), size: 0, kind: "directory")
        let store = TestStore(initialState: BrowseTabFeature.State(serverURL: serverURL)) {
            BrowseTabFeature()
        }

        await store.send(.root(.delegate(.openFolder(item)))) {
            $0.path.append(BrowseFeature.State(serverURL: self.serverURL, directoryPath: item.id, title: item.name))
        }
    }

    @Test
    func openingAFolderFromAPushedScreenPushesAnotherLevel() async {
        let root = FileItem(name: "Photos", path: "", dateModified: Date(), size: 0, kind: "directory")
        var state = BrowseTabFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: root.id, title: root.name))
        let nested = FileItem(name: "Vacation", path: "Photos", dateModified: Date(), size: 0, kind: "directory")

        let store = TestStore(initialState: state) {
            BrowseTabFeature()
        }

        await store.send(.path(.element(id: 0, action: .delegate(.openFolder(nested))))) {
            $0.path.append(BrowseFeature.State(serverURL: self.serverURL, directoryPath: nested.id, title: nested.name))
        }
    }

    @Test
    func navigatingToANonEmptyPathReplacesTheEntirePathStack() async {
        var state = BrowseTabFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "A", title: "A"))
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "A/B", title: "B"))

        let store = TestStore(initialState: state) {
            BrowseTabFeature()
        }

        await store.send(.navigateToDirectory(path: "Photos", title: "Photos")) {
            $0.path = StackState([BrowseFeature.State(serverURL: self.serverURL, directoryPath: "Photos", title: "Photos")])
        }
    }

    // MARK: Edge cases

    @Test
    func navigatingToAnEmptyPathClearsTheStackAndStaysOnRoot() async {
        var state = BrowseTabFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "A", title: "A"))

        let store = TestStore(initialState: state) {
            BrowseTabFeature()
        }

        await store.send(.navigateToDirectory(path: "", title: "Home")) {
            $0.path = StackState()
        }
    }

    @Test
    func openPathDelegateFromTheRootForwardsToNavigateToDirectory() async {
        // Exhaustivity off: the pushed `BrowseFeature.State` gets a fresh `StackElementID`
        // whose exact value isn't reproducible in a `receive`-triggered assertion closure
        // (unlike `send`, TCA's test generator snapshotting doesn't line the two up here) —
        // asserting the resulting path's content is what actually matters.
        let store = TestStore(initialState: BrowseTabFeature.State(serverURL: serverURL)) {
            BrowseTabFeature()
        }
        store.exhaustivity = .off

        await store.send(.root(.delegate(.openPath(path: "Photos", title: "Photos"))))
        await store.receive(\.navigateToDirectory)

        #expect(store.state.path.map(\.directoryPath) == ["Photos"])
        #expect(store.state.path.map(\.title) == ["Photos"])
    }

    @Test
    func openPathDelegateFromAPushedScreenForwardsToNavigateToDirectory() async {
        var state = BrowseTabFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "A", title: "A"))

        let store = TestStore(initialState: state) {
            BrowseTabFeature()
        }

        await store.send(.path(.element(id: 0, action: .delegate(.openPath(path: "", title: "Home")))))
        await store.receive(.navigateToDirectory(path: "", title: "Home")) {
            $0.path = StackState()
        }
    }

    @Test
    func navigatingToTheSamePathTwiceStillReplacesTheStackWithAFreshBrowseFeatureState() async {
        // Regression guard: a breadcrumb re-tap on the currently-open folder should still
        // reset the stack to a single fresh element, not leave stale nested screens behind.
        var state = BrowseTabFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos", title: "Photos"))
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos/Old", title: "Old"))

        let store = TestStore(initialState: state) {
            BrowseTabFeature()
        }

        await store.send(.navigateToDirectory(path: "Photos", title: "Photos")) {
            $0.path = StackState([BrowseFeature.State(serverURL: self.serverURL, directoryPath: "Photos", title: "Photos")])
        }
    }

    // MARK: Sync on app open

    @Test
    func syncPathStackRefreshesOnlyTheRootWhenNoFolderIsPushed() async {
        let refreshed = FileItem(name: "New", path: "", dateModified: Date(), size: 0, kind: "directory")
        let store = TestStore(initialState: BrowseTabFeature.State(serverURL: serverURL)) {
            BrowseTabFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in
                BrowseResult(items: [refreshed], access: FileAccess(canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true), path: "")
            }
            $0.filesClient.favorites = { _ in [] }
        }
        store.exhaustivity = .off

        await store.send(.syncPathStack)
        await store.receive(\.root.refreshButtonTapped) {
            $0.root.phase = .loading
        }
    }

    @Test
    func syncPathStackRefreshesTheRootAndEveryPushedSubfolder() async {
        var state = BrowseTabFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos", title: "Photos"))
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos/Old", title: "Old"))
        let refreshed = FileItem(name: "New", path: "", dateModified: Date(), size: 0, kind: "directory")

        let store = TestStore(initialState: state) {
            BrowseTabFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in
                BrowseResult(items: [refreshed], access: FileAccess(canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true), path: "")
            }
            $0.filesClient.favorites = { _ in [] }
        }
        store.exhaustivity = .off
        let pathIDs = state.path.ids

        await store.send(.syncPathStack)
        await store.receive(\.root.refreshButtonTapped) {
            $0.root.phase = .loading
        }
        await store.receive(\.path[id: pathIDs[0]].refreshButtonTapped) {
            $0.path[id: pathIDs[0]]?.phase = .loading
        }
        await store.receive(\.path[id: pathIDs[1]].refreshButtonTapped) {
            $0.path[id: pathIDs[1]]?.phase = .loading
        }
    }

    @Test
    func directoryContentsChangedFromAPushedScreenReSyncsTheWholeStack() async {
        var state = BrowseTabFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos", title: "Photos"))
        let refreshed = FileItem(name: "New", path: "", dateModified: Date(), size: 0, kind: "directory")

        let store = TestStore(initialState: state) {
            BrowseTabFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in
                BrowseResult(items: [refreshed], access: FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: false, canDownload: true), path: "")
            }
            $0.filesClient.favorites = { _ in [] }
        }
        store.exhaustivity = .off
        let pathIDs = state.path.ids

        await store.send(.path(.element(id: pathIDs[0], action: .delegate(.directoryContentsChanged))))
        await store.receive(\.syncPathStack)
        await store.receive(\.root.refreshButtonTapped)
        await store.receive(\.path[id: pathIDs[0]].refreshButtonTapped)
    }

    // MARK: Favorites-changed delegate bubbling

    @Test
    func favoritesChangedFromTheRootBubblesUpAsADelegate() async {
        let store = TestStore(initialState: BrowseTabFeature.State(serverURL: serverURL)) {
            BrowseTabFeature()
        }

        await store.send(.root(.delegate(.favoritesChanged)))
        await store.receive(.delegate(.favoritesChanged))
    }

    @Test
    func favoritesChangedFromAPushedScreenAlsoBubblesUpAsADelegate() async {
        var state = BrowseTabFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos", title: "Photos"))

        let store = TestStore(initialState: state) {
            BrowseTabFeature()
        }

        await store.send(.path(.element(id: 0, action: .delegate(.favoritesChanged))))
        await store.receive(.delegate(.favoritesChanged))
    }

    // MARK: Open-downloads delegate bubbling

    @Test
    func openDownloadsTappedFromTheRootBubblesUpAsADelegate() async {
        let store = TestStore(initialState: BrowseTabFeature.State(serverURL: serverURL)) {
            BrowseTabFeature()
        }

        await store.send(.root(.delegate(.openDownloadsTapped)))
        await store.receive(.delegate(.openDownloadsTapped))
    }

    @Test
    func openDownloadsTappedFromAPushedScreenAlsoBubblesUpAsADelegate() async {
        var state = BrowseTabFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos", title: "Photos"))

        let store = TestStore(initialState: state) {
            BrowseTabFeature()
        }

        await store.send(.path(.element(id: 0, action: .delegate(.openDownloadsTapped))))
        await store.receive(.delegate(.openDownloadsTapped))
    }

    @Test
    func goToSharedTabBubblesUpAsADelegate() async {
        let store = TestStore(initialState: BrowseTabFeature.State(serverURL: serverURL)) {
            BrowseTabFeature()
        }

        await store.send(.root(.delegate(.goToSharedTab)))
        await store.receive(.delegate(.goToSharedTab))
    }
}
