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
}
