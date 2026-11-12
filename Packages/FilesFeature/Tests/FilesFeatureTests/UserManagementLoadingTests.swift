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
struct UserManagementLoadingTests: UserManagementTestSupport {
    let calls = LockIsolated<[Call]>([])
    let listCalls = LockIsolated(0)
    let featureCalls = LockIsolated(0)
    let volumeLoads = LockIsolated<[String]>([])

    @Test
    func onAppearLoadsUsersThenTheFeatureFlags() async {
        let users = [makeUser(id: "1", admin: true), makeUser(id: "2")]
        let store = makeStore(
            State(serverURL: serverURL, currentUserID: "me"),
            users: { users },
            features: { ServerFeatures(isUserVolumesEnabled: true) }
        )

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.usersResponse.success) {
            $0.phase = .loaded
            $0.users = IdentifiedArray(uniqueElements: users)
        }
        await store.receive(\.featuresResponse) {
            $0.hasLoadedFeatures = true
            $0.isUserVolumesEnabled = true
        }
    }

    @Test
    func onAppearSurfacesALoadFailureAndStillAsksForTheFeatureFlags() async {
        let store = makeStore(
            State(serverURL: serverURL, currentUserID: "me"),
            users: { throw FilesClientError.server(statusCode: 403) },
            features: { ServerFeatures() }
        )

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.usersResponse.failure) { $0.phase = .failed(L10n.Error.server(403)) }
        await store.receive(\.featuresResponse) { $0.hasLoadedFeatures = true }
    }

    @Test
    func aFailedFeatureFlagLoadNeverBlocksTheList() async {
        let users = [makeUser(id: "1")]
        let store = makeStore(
            State(serverURL: serverURL, currentUserID: "me"),
            users: { users },
            features: { throw FilesClientError.offline }
        )

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.usersResponse.success) {
            $0.phase = .loaded
            $0.users = IdentifiedArray(uniqueElements: users)
        }
        await store.finish()
        #expect(!store.state.hasLoadedFeatures)
        #expect(featureCalls.value == 1)
    }

    @Test
    func aServerAnswerWithDuplicateIdsKeepsTheFirstOfEach() async {
        let first = makeUser(id: "1")
        let duplicate = User(id: "1", username: "other", email: "other@example.com", roles: [])
        let store = makeStore(
            State(serverURL: serverURL, currentUserID: "me"),
            users: { [first, duplicate] },
            features: { ServerFeatures() }
        )

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.usersResponse.success) {
            $0.phase = .loaded
            $0.users = [first]
        }
        await store.receive(\.featuresResponse) { $0.hasLoadedFeatures = true }
    }

    @Test
    func onAppearDoesNothingOnceUsersAreLoaded() async {
        let store = makeStore(loadedState([makeUser(id: "1")]), users: { [] }, features: { ServerFeatures() })

        await store.send(.onAppear)
        #expect(listCalls.value == 0)
    }

    @Test
    func refreshingKeepsTheListVisibleAndReplacesItsUsers() async {
        let refreshed = [makeUser(id: "1"), makeUser(id: "3")]
        let store = makeStore(loadedState([makeUser(id: "1")]), users: { refreshed }, features: { ServerFeatures() })

        await store.send(.refreshRequested)
        await store.receive(\.usersResponse.success) { $0.users = IdentifiedArray(uniqueElements: refreshed) }
        await store.receive(\.featuresResponse)
    }

    @Test
    func aReloadThatDropsTheOpenUserClosesTheDetail() async {
        let remaining = [makeUser(id: "1", admin: true)]
        let store = makeStore(
            loadedState([makeUser(id: "1", admin: true), makeUser(id: "2")], detail: "2"),
            users: { remaining },
            features: { ServerFeatures() }
        )

        await store.send(.refreshRequested)
        await store.receive(\.usersResponse.success) {
            $0.users = IdentifiedArray(uniqueElements: remaining)
            $0.detailUserID = nil
        }
        await store.receive(\.featuresResponse)
    }

    @Test
    func aReloadDoesNotStompUnsavedProfileEdits() async {
        let user = makeUser(id: "2")
        let store = makeStore(loadedState([user], detail: "2"), users: { [user] }, features: { ServerFeatures() })

        await store.send(.editDisplayNameChanged("Half-typed name")) { $0.editDisplayName = "Half-typed name" }
        await store.send(.refreshRequested)
        await store.receive(\.usersResponse.success)
        await store.receive(\.featuresResponse)
        #expect(store.state.editDisplayName == "Half-typed name")
    }
}
