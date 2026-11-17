import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// The trash as a sidebar section: read again on return and on reconnect, and leaving it for a folder.
@Suite(.isolatedDependencies)
@MainActor
struct MainTabTrashTests: MainTabTestSupport {
    private nonisolated static let item = TrashItem(id: "t1", name: "a.txt")

    @Test("Returning to a trash already shown reads it again; one never opened waits for its screen")
    func returningRefreshesALoadedTrash() async {
        let store = makeStore(makeState { $0.trash.phase = .loaded }) {
            $0.filesClient.fetchTrash = { _ in TrashListing(isEnabled: true, retentionDays: 30, items: [Self.item]) }
        }

        await store.send(.tabSelected(.trash)) { $0.selectedTab = .trash }
        await store.receive(\.trash.refreshPulled)
        await store.receive(\.trash.loadResponse.success) {
            $0.trash.items = [Self.item]
            $0.trash.retentionDays = 30
        }

        let fresh = makeStore()
        await fresh.send(.tabSelected(.trash)) { $0.selectedTab = .trash }
    }

    @Test("Open Original Location leaves the trash for the folder in Browse")
    func openLocationGoesToBrowse() async {
        let store = makeStore(makeState { $0.selectedTab = .trash })

        await store.send(.trash(.delegate(.openPath(path: "", title: "Browse")))) { $0.selectedTab = .browse }
        await store.receive(\.browse.navigateToDirectory)
    }
}
