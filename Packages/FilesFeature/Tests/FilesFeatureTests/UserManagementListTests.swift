import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import TestUtils
import Testing

@Suite(.isolatedDependencies)
@MainActor
struct UserManagementListTests: UserManagementTestSupport {
    let calls = LockIsolated<[Call]>([])
    let listCalls = LockIsolated(0)
    let featureCalls = LockIsolated(0)
    let volumeLoads = LockIsolated<[String]>([])

    @Test
    func dismissingTheToastClearsIt() async {
        var state = loadedState([])
        state.toast = "Saved"
        let store = makeStore(state)

        await store.send(.toastDismissed) { $0.toast = nil }
    }

    @Test
    func searchFiltersByNameUsernameOrEmailIgnoringCase() async {
        let users = [
            makeUser(id: "1"),
            User(id: "2", username: "jrivera", email: "jamie@corp.com", displayName: "Jamie Rivera"),
            User(id: "3", username: "sokafor", email: "sam@corp.com", displayName: "Sam Okafor"),
        ]
        let store = makeStore(loadedState(users))

        await store.send(.searchQueryChanged("RIVERA")) { $0.searchQuery = "RIVERA" }
        #expect(store.state.displayedUsers.map(\.id) == ["2"])

        await store.send(.searchQueryChanged("sokafor")) { $0.searchQuery = "sokafor" }
        #expect(store.state.displayedUsers.map(\.id) == ["3"])

        await store.send(.searchQueryChanged("corp.com")) { $0.searchQuery = "corp.com" }
        #expect(store.state.displayedUsers.map(\.id) == ["2", "3"])
        #expect(!store.state.isSearchWithoutResults)

        await store.send(.searchQueryChanged("nobody")) { $0.searchQuery = "nobody" }
        #expect(store.state.displayedUsers.isEmpty)
        #expect(store.state.isSearchWithoutResults)

        await store.send(.searchQueryChanged(TestValue.blank)) { $0.searchQuery = TestValue.blank }
        #expect(store.state.displayedUsers.count == 3)
        #expect(!store.state.isSearchWithoutResults)
    }

    @Test
    func theListSortsByTypeThenNameByDefaultAndFollowsTheSortSheet() async {
        let users = [
            User(id: "1", username: "amy", email: "zed@corp.com", displayName: "Amy"),
            User(id: "2", username: "mia", email: "bob@corp.com", displayName: "Mia", roles: ["admin"]),
            User(id: "3", username: "zoe", email: "amy@corp.com", displayName: "Zoe"),
        ]
        let store = makeStore(loadedState(users))

        #expect(store.state.displayedUsers.map(\.id) == ["2", "1", "3"])

        await store.send(.sortOptionChanged(.name)) { $0.sortOption = .name }
        #expect(store.state.displayedUsers.map(\.id) == ["1", "2", "3"])

        await store.send(.sortOptionChanged(.email)) { $0.sortOption = .email }
        #expect(store.state.displayedUsers.map(\.id) == ["3", "2", "1"])

        await store.send(.sortDirectionChanged(.descending)) { $0.sortDirection = .descending }
        #expect(store.state.displayedUsers.map(\.id) == ["1", "2", "3"])

        await store.send(.sortOptionChanged(.type)) { $0.sortOption = .type }
        #expect(store.state.displayedUsers.map(\.id) == ["3", "1", "2"])
    }

    @Test
    func usersWithTheSameNameSortByIdSoTheOrderIsStable() {
        var state = loadedState([
            User(id: "b", username: "same", email: nil, displayName: "Same"),
            User(id: "a", username: "same", email: nil, displayName: "Same"),
        ])
        state.sortOption = .name

        #expect(state.displayedUsers.map(\.id) == ["a", "b"])
    }
}
