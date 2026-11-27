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

    @Test("Returning to Shared already shown fetches its segment again; one never opened waits for its screen")
    func returningRevalidatesALoadedShared() async {
        let share = Share(
            id: "s1",
            shareToken: "tok",
            ownerId: "u1",
            isDirectory: true,
            accessMode: .readonly,
            sharingType: .anyone,
            hasPassword: false,
            createdAt: MockDate.date,
            updatedAt: MockDate.date
        )
        let store = makeStore(makeState { $0.shared.phases[.byMe] = .loaded }) {
            $0.filesClient.mySharedLinks = { _ in [share] }
        }

        await store.send(.tabSelected(.shared)) { $0.selectedTab = .shared }
        await store.receive(\.shared.segmentChanged)
        await store.receive(\.shared.sharesResponse) {
            $0.shared.dataSources[.byMe] = .live
            $0.shared.byMe = [share]
        }

        let fresh = makeStore()
        await fresh.send(.tabSelected(.shared)) { $0.selectedTab = .shared }
    }

    @Test("Go to Shared from the empty Browse root opens Shared on the links shared with me")
    func sharedWithMeRequestedOpensSharedWithMe() async {
        let store = makeStore {
            $0.filesClient.sharedWithMeLinks = { _ in [] }
        }

        await store.send(.sharedWithMeRequested) { $0.selectedTab = .shared }
        await store.receive(\.shared.segmentChanged) {
            $0.shared.segment = .withMe
            $0.shared.phases[.withMe] = .loading
        }
        await store.receive(\.shared.sharesResponse) {
            $0.shared.phases[.withMe] = .loaded
            $0.shared.dataSources[.withMe] = .live
        }
    }

    @Test("Open Original Location leaves the trash for the folder in Browse")
    func openLocationGoesToBrowse() async {
        let store = makeStore(makeState { $0.selectedTab = .trash })

        await store.send(.trash(.delegate(.openPath(path: "", title: "Browse")))) { $0.selectedTab = .browse }
        await store.receive(\.browse.navigateToDirectory)
    }
}
