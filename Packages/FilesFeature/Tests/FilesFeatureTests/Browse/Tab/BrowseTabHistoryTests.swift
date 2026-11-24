import ComposableArchitecture
import CoreModels
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// The Mac menu's Back, Forward and Enclosing Folder over the tab's folder stack.
@Suite(.isolatedDependencies)
@MainActor
struct BrowseTabHistoryTests {
    private let serverURL = BrowseTestSupport.serverURL

    private func screen(_ path: String) -> BrowseFeature.State {
        BrowseFeature.State(serverURL: serverURL, directoryPath: path, title: (path as NSString).lastPathComponent)
    }

    private func makeStore(pushing paths: [String] = [], forward: [String] = []) -> TestStoreOf<BrowseTabFeature> {
        var state = BrowseTabFeature.State(serverURL: serverURL)
        for path in paths {
            state.path.append(screen(path))
        }
        state.forwardStack = forward.map(screen)
        return TestStore(initialState: state) {
            BrowseTabFeature()
        }
    }

    @Test("Enclosing Folder pops the visible folder when the folder above is the screen under it")
    func goToEnclosingFolderPopsTheVisibleFolder() async {
        let store = makeStore(pushing: ["A", "A/B"])

        await store.send(.goToEnclosingFolder) {
            $0.path.removeLast()
            $0.forwardStack = [screen("A/B")]
        }
    }

    @Test("Forward reopens the folder left by going back, and does nothing when there is none")
    func forwardReopensTheFolderLeftByGoingBack() async {
        let store = makeStore(pushing: ["A"])

        await store.send(.goToEnclosingFolder) {
            $0.path.removeLast()
            $0.forwardStack = [screen("A")]
        }
        await store.send(.goForward) {
            $0.forwardStack = []
            $0.path.append(screen("A"))
        }
        await store.send(.goForward)
    }

    @Test("Navigating somewhere new clears Forward")
    func navigatingSomewhereNewClearsForward() async {
        let store = makeStore(forward: ["A"])

        await store.send(.navigateToDirectory(path: "B", title: "B")) {
            $0.forwardStack = []
            $0.path = StackState([screen("B")])
        }
    }

    @Test("Enclosing Folder at the root does nothing")
    func goToEnclosingFolderAtTheRootDoesNothing() async {
        let store = makeStore()

        await store.send(.goToEnclosingFolder)
    }

    @Test("Back leaves the visible screen and offers Forward")
    func backLeavesTheVisibleScreenAndOffersForward() async {
        let store = makeStore(pushing: ["A/B/C"])

        await store.send(.goBack) {
            $0.path.removeLast()
            $0.forwardStack = [screen("A/B/C")]
        }
    }

    @Test("Enclosing Folder after a jump opens the parent in place and clears Forward")
    func enclosingFolderAfterAJumpOpensTheParentInPlace() async {
        let store = makeStore(pushing: ["A/B/C"], forward: ["X"])

        await store.send(.goToEnclosingFolder) {
            $0.path.removeLast()
            $0.path.append(screen("A/B"))
            $0.forwardStack = []
        }
    }
}
