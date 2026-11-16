import ComposableArchitecture
import CoreModels
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// The trash pushed over the Browse root, and leaving it for an item's original folder.
@Suite(.isolatedDependencies)
@MainActor
struct BrowseTabTrashTests {
    private let serverURL = BrowseTestSupport.serverURL

    private func screen(_ path: String) -> BrowseFeature.State {
        BrowseFeature.State(serverURL: serverURL, directoryPath: path, title: (path as NSString).lastPathComponent)
    }

    @Test("Open Trash from a pushed folder returns to the root and pushes the trash")
    func openTrashFromAFolder() async {
        var state = BrowseTabFeature.State(serverURL: serverURL)
        state.path.append(screen("A"))
        let store = TestStore(initialState: state) { BrowseTabFeature() }

        await store.send(.path(.element(id: 0, action: .delegate(.openTrashTapped))))
        await store.receive(\.openTrash) {
            $0.path = StackState()
            $0.trash = TrashFeature.State(serverURL: serverURL)
        }
    }

    @Test("Open Original Location closes the trash and opens the folder")
    func openLocationLeavesTheTrash() async {
        var state = BrowseTabFeature.State(serverURL: serverURL)
        state.trash = TrashFeature.State(serverURL: serverURL)
        let store = TestStore(initialState: state) { BrowseTabFeature() }

        // The volume root: the jump itself is covered by the history tests, this checks the routing.
        await store.send(.trash(.presented(.delegate(.openPath(path: "", title: "Browse"))))) {
            $0.trash = nil
        }
        await store.receive(\.navigateToDirectory)
    }
}
