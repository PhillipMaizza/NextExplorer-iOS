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
struct UserManagementDetailTests: UserManagementTestSupport {
    let calls = LockIsolated<[Call]>([])
    let listCalls = LockIsolated(0)
    let featureCalls = LockIsolated(0)
    let volumeLoads = LockIsolated<[String]>([])

    @Test
    func tappingAUserOpensDetailAndSeedsTheProfileForm() async {
        var state = loadedState([makeUser(id: "2")])
        state.detailTab = .security
        state.detailErrorMessage = TestValue.outdated
        let store = makeStore(state)

        await store.send(.userTapped("2")) {
            $0.detailUserID = "2"
            $0.detailTab = .profile
            $0.detailErrorMessage = nil
            $0.editDisplayName = "User 2"
            $0.editUsername = "user2"
            $0.editEmail = "user2@example.com"
        }
        #expect(volumeLoads.value.isEmpty)
        #expect(featureCalls.value == 0)
    }

    @Test
    func tappingAnUnknownUserDoesNothing() async {
        let store = makeStore(loadedState([makeUser(id: "2")]))

        await store.send(.userTapped("404"))
    }

    @Test
    func openingDetailRetriesAFailedFeatureFlagLoad() async {
        var state = loadedState([makeUser(id: "2")])
        state.hasLoadedFeatures = false
        let store = makeStore(state, features: { ServerFeatures(isUserVolumesEnabled: true) })

        await store.send(.userTapped("2")) {
            $0.detailUserID = "2"
            $0.editDisplayName = "User 2"
            $0.editUsername = "user2"
            $0.editEmail = "user2@example.com"
        }
        await store.receive(\.featuresResponse) {
            $0.hasLoadedFeatures = true
            $0.isUserVolumesEnabled = true
        }
        #expect(featureCalls.value == 1)
    }

    @Test
    func openingDetailLoadsVolumesWhenTheFeatureIsOn() async {
        let store = makeStore(
            loadedState([makeUser(id: "2")], isVolumesEnabled: true),
            volumes: { [projects] _ in [projects] }
        )

        await store.send(.userTapped("2")) {
            $0.detailUserID = "2"
            $0.editDisplayName = "User 2"
            $0.editUsername = "user2"
            $0.editEmail = "user2@example.com"
            $0.volumesPhase = .loading
        }
        await store.receive(\.volumesResponse.success) {
            $0.volumesPhase = .loaded
            $0.volumes = [projects]
        }
        #expect(volumeLoads.value == ["2"])
    }

    @Test
    func aVolumesLoadFailureIsShownInTheDetailBanner() async {
        let store = makeStore(
            loadedState([makeUser(id: "2")], detail: "2", isVolumesEnabled: true),
            volumes: { _ in throw FilesClientError.server(statusCode: 500) }
        )

        await store.send(.detailTabChanged(.volumes)) {
            $0.detailTab = .volumes
            $0.volumesPhase = .loading
        }
        await store.receive(\.volumesResponse.failure) {
            $0.volumesPhase = .failed(L10n.Error.server(500))
            $0.detailErrorMessage = L10n.Error.server(500)
        }
    }

    @Test
    func theVolumesTabLoadsLazilyOnlyWhenNothingIsLoaded() async {
        let store = makeStore(
            loadedState([makeUser(id: "2")], detail: "2", isVolumesEnabled: true),
            volumes: { [projects] _ in [projects] }
        )

        await store.send(.detailTabChanged(.security)) { $0.detailTab = .security }
        #expect(volumeLoads.value.isEmpty)

        await store.send(.detailTabChanged(.volumes)) {
            $0.detailTab = .volumes
            $0.volumesPhase = .loading
        }
        await store.receive(\.volumesResponse.success) {
            $0.volumesPhase = .loaded
            $0.volumes = [projects]
        }

        await store.send(.detailTabChanged(.security)) { $0.detailTab = .security }
        await store.send(.detailTabChanged(.volumes)) { $0.detailTab = .volumes }
        #expect(volumeLoads.value == ["2"])
    }

    @Test
    func theVolumesTabNeverLoadsWhenTheFeatureIsOff() async {
        let store = makeStore(loadedState([makeUser(id: "2")], detail: "2"), volumes: { _ in [] })

        await store.send(.detailTabChanged(.volumes)) { $0.detailTab = .volumes }
        #expect(volumeLoads.value.isEmpty)
    }

    @Test
    func dismissingTheDetailDropsAVolumesLoadStillInFlight() async {
        let gate = AsyncGate()
        let store = makeStore(
            loadedState([makeUser(id: "2")], isVolumesEnabled: true),
            volumes: { [projects] _ in
                try await gate.wait()
                return [projects]
            }
        )

        await store.send(.userTapped("2")) {
            $0.detailUserID = "2"
            $0.editDisplayName = "User 2"
            $0.editUsername = "user2"
            $0.editEmail = "user2@example.com"
            $0.volumesPhase = .loading
        }
        await store.send(.detailDismissed) {
            $0.detailUserID = nil
            $0.volumesPhase = .idle
        }
        await store.finish()
        #expect(store.state.volumes.isEmpty)
    }

    @Test
    func dismissingTheDetailDropsAProfileSaveStillInFlight() async {
        let gate = AsyncGate()
        let unchanged = makeUser(id: "2")
        let store = makeStore(loadedState([unchanged], detail: "2"), updateUser: {
            try await gate.wait()
            return unchanged
        })

        await store.send(.editDisplayNameChanged("Renamed")) { $0.editDisplayName = "Renamed" }
        await store.send(.saveProfileTapped) { $0.isSavingProfile = true }
        await store.send(.detailDismissed) {
            $0.detailUserID = nil
            $0.isSavingProfile = false
        }
        await store.finish()
        #expect(store.state.toast == nil)
    }

    @Test
    func dismissingTheDetailDropsAPendingGrantAdminConfirmation() async {
        let user = makeUser(id: "2")
        let store = makeStore(loadedState([user], detail: "2"))

        await store.send(.grantAdminTapped) { $0.userToGrantAdmin = user }
        await store.send(.detailDismissed) {
            $0.detailUserID = nil
            $0.userToGrantAdmin = nil
        }
    }

    @Test
    func theOwnAccountIsRecognisedByItsId() async {
        let me = makeUser(id: "me")
        let store = makeStore(loadedState([me, makeUser(id: "2")]))

        await store.send(.userTapped("me")) {
            $0.detailUserID = "me"
            $0.editDisplayName = "User me"
            $0.editUsername = "userme"
            $0.editEmail = "userme@example.com"
        }
        #expect(store.state.isViewingOwnAccount)
        await store.send(.userTapped("2")) {
            $0.detailUserID = "2"
            $0.editDisplayName = "User 2"
            $0.editUsername = "user2"
            $0.editEmail = "user2@example.com"
        }
        #expect(!store.state.isViewingOwnAccount)
    }
}
