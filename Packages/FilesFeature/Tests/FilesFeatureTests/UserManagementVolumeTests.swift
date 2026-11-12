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
struct UserManagementVolumeTests: UserManagementTestSupport {
    let calls = LockIsolated<[Call]>([])
    let listCalls = LockIsolated(0)
    let featureCalls = LockIsolated(0)
    let volumeLoads = LockIsolated<[String]>([])

    @Test
    func assigningAVolumeSendsTheRequestAndAddsItToTheDetail() async {
        let created = media
        let store = makeStore(loadedState([makeUser(id: "2")], detail: "2", isVolumesEnabled: true, volumes: []), addVolume: { created })

        await store.send(.addVolumeTapped) { $0.volumeSheet = .init(userID: "2") }
        await store.send(.volumePathSelected("/srv/media")) {
            $0.volumeSheet?.selectedPath = "/srv/media"
            $0.volumeSheet?.label = "media"
        }
        await store.send(.volumeLabelChanged(TestFolder.media)) { $0.volumeSheet?.label = TestFolder.media }
        await store.send(.volumeAccessModeChanged(.readonly)) { $0.volumeSheet?.accessMode = .readonly }
        await store.send(.volumeSubmitTapped) { $0.volumeSheet?.isSubmitting = true }
        await store.receive(\.volumeResponse.success) {
            $0.volumeSheet = nil
            $0.volumes[id: "v9"] = created
            $0.toast = L10n.UserManagement.toastVolumeSaved
        }
        #expect(calls.value == [.addVolume(userID: "2", request: AddUserVolumeRequest(label: TestFolder.media, path: "/srv/media", accessMode: .readonly))])
    }

    @Test
    func pickingAPathKeepsALabelTheAdminAlreadyTyped() async {
        var state = loadedState([makeUser(id: "2")], detail: "2")
        state.volumeSheet = .init(userID: "2", label: "Typed")
        let store = makeStore(state)

        await store.send(.volumePathSelected("/srv/media")) { $0.volumeSheet?.selectedPath = "/srv/media" }
        #expect(store.state.volumeSheet?.label == "Typed")
    }

    struct VolumeSheetCase: Sendable {
        let label: String
        let path: String
        let isSubmitting: Bool
        let isSubmitEnabled: Bool
    }

    @Test(
        "The volume sheet needs a label and a path and submits only once",
        arguments: [
            VolumeSheetCase(label: TestFolder.media, path: "/srv/media", isSubmitting: false, isSubmitEnabled: true),
            VolumeSheetCase(label: "  ", path: "/srv/media", isSubmitting: false, isSubmitEnabled: false),
            VolumeSheetCase(label: TestFolder.media, path: "  ", isSubmitting: false, isSubmitEnabled: false),
            VolumeSheetCase(label: TestFolder.media, path: "/srv/media", isSubmitting: true, isSubmitEnabled: false),
        ]
    )
    func volumeSheetValidation(_ testCase: VolumeSheetCase) async {
        var state = loadedState([makeUser(id: "2")], detail: "2")
        state.volumeSheet = .init(userID: "2", label: testCase.label, selectedPath: testCase.path, isSubmitting: testCase.isSubmitting)
        let store = makeStore(state, addVolume: { [media] in media })

        #expect(store.state.volumeSheet?.isSubmitEnabled == testCase.isSubmitEnabled)
        if !testCase.isSubmitEnabled {
            await store.send(.volumeSubmitTapped)
            #expect(calls.value.isEmpty)
        }
    }

    @Test
    func aVolumeSaveFailureKeepsTheSheetOpenWithItsMessage() async {
        let store = makeStore(loadedState([makeUser(id: "2")], detail: "2", isVolumesEnabled: true, volumes: []), addVolume: {
            throw FilesClientError.serverMessage(statusCode: 409, message: "This path is already assigned to this user")
        })

        await store.send(.addVolumeTapped) { $0.volumeSheet = .init(userID: "2") }
        await store.send(.volumePathSelected("/srv/media")) {
            $0.volumeSheet?.selectedPath = "/srv/media"
            $0.volumeSheet?.label = "media"
        }
        await store.send(.volumeSubmitTapped) { $0.volumeSheet?.isSubmitting = true }
        await store.receive(\.volumeResponse.failure) {
            $0.volumeSheet?.isSubmitting = false
            $0.volumeSheet?.errorMessage = "This path is already assigned to this user"
        }
        #expect(store.state.volumes.isEmpty)
    }

    @Test
    func editingAVolumeGoesThroughUpdateNotAdd() async {
        let saved = UserVolume(id: TestETag.first, userId: "2", label: "Renamed", path: "/srv/projects", accessMode: .readonly)
        let store = makeStore(
            loadedState([makeUser(id: "2")], detail: "2", isVolumesEnabled: true, volumes: [projects]),
            updateVolume: { saved }
        )

        await store.send(.editVolumeTapped(projects)) {
            $0.volumeSheet = .init(userID: "2", editingVolumeID: TestETag.first, label: "Projects", selectedPath: "/srv/projects", accessMode: .readwrite)
        }
        await store.send(.volumeLabelChanged("Renamed")) { $0.volumeSheet?.label = "Renamed" }
        await store.send(.volumeAccessModeChanged(.readonly)) { $0.volumeSheet?.accessMode = .readonly }
        await store.send(.volumeSubmitTapped) { $0.volumeSheet?.isSubmitting = true }
        await store.receive(\.volumeResponse.success) {
            $0.volumeSheet = nil
            $0.volumes[id: TestETag.first] = saved
            $0.toast = L10n.UserManagement.toastVolumeSaved
        }
        #expect(calls.value == [.updateVolume(userID: "2", volumeID: TestETag.first, label: "Renamed", mode: .readonly)])
    }

    @Test
    func dismissingTheVolumeSheetDropsIt() async {
        var state = loadedState([makeUser(id: "2")], detail: "2")
        state.volumeSheet = .init(userID: "2")
        let store = makeStore(state)

        await store.send(.volumeSheetDismissed) { $0.volumeSheet = nil }
    }

    @Test
    func removingAVolumeAsksFirstThenDropsItFromTheDetail() async {
        let store = makeStore(
            loadedState([makeUser(id: "2")], detail: "2", isVolumesEnabled: true, volumes: [projects]),
            removeVolume: { _ in }
        )

        await store.send(.removeVolumeTapped(projects)) { $0.volumeToRemove = projects }
        #expect(calls.value.isEmpty)
        await store.send(.removeVolumeConfirmed) {
            $0.volumeToRemove = nil
            $0.removingVolumeIDs = [TestETag.first]
        }
        await store.receive(\.removeVolumeResponse) {
            $0.removingVolumeIDs = []
            $0.volumes.remove(id: TestETag.first)
            $0.toast = L10n.UserManagement.toastVolumeRemoved
        }
        #expect(calls.value == [.removeVolume(userID: "2", volumeID: TestETag.first)])
    }

    @Test
    func cancellingAVolumeRemovalDeletesNothing() async {
        let store = makeStore(
            loadedState([makeUser(id: "2")], detail: "2", isVolumesEnabled: true, volumes: [projects]),
            removeVolume: { _ in }
        )

        await store.send(.removeVolumeTapped(projects)) { $0.volumeToRemove = projects }
        await store.send(.removeVolumeCancelled) { $0.volumeToRemove = nil }
        await store.send(.removeVolumeConfirmed)
        #expect(calls.value.isEmpty)
    }

    @Test
    func aRemoveVolumeFailureIsSurfacedAndKeepsTheVolume() async {
        let store = makeStore(
            loadedState([makeUser(id: "2")], detail: "2", isVolumesEnabled: true, volumes: [projects]),
            removeVolume: { _ in throw FilesClientError.server(statusCode: 500) }
        )

        await store.send(.removeVolumeTapped(projects)) { $0.volumeToRemove = projects }
        await store.send(.removeVolumeConfirmed) {
            $0.volumeToRemove = nil
            $0.removingVolumeIDs = [TestETag.first]
        }
        await store.receive(\.removeVolumeResponse) {
            $0.removingVolumeIDs = []
            $0.detailErrorMessage = L10n.Error.server(500)
        }
        #expect(store.state.volumes[id: TestETag.first] == projects)
    }

    @Test
    func removingAVolumeWhileASaveIsInFlightDoesNotCancelTheSave() async {
        let saveGate = AsyncGate()
        let created = media
        let store = makeStore(
            loadedState([makeUser(id: "2")], detail: "2", isVolumesEnabled: true, volumes: [projects]),
            addVolume: {
                try await saveGate.wait()
                return created
            },
            removeVolume: { _ in }
        )

        await store.send(.addVolumeTapped) { $0.volumeSheet = .init(userID: "2") }
        await store.send(.volumePathSelected("/srv/media")) {
            $0.volumeSheet?.selectedPath = "/srv/media"
            $0.volumeSheet?.label = "media"
        }
        await store.send(.volumeSubmitTapped) { $0.volumeSheet?.isSubmitting = true }

        await store.send(.removeVolumeTapped(projects)) { $0.volumeToRemove = projects }
        await store.send(.removeVolumeConfirmed) {
            $0.volumeToRemove = nil
            $0.removingVolumeIDs = [TestETag.first]
        }
        await store.receive(\.removeVolumeResponse) {
            $0.removingVolumeIDs = []
            $0.volumes.remove(id: TestETag.first)
            $0.toast = L10n.UserManagement.toastVolumeRemoved
        }
        saveGate.open()
        await store.receive(\.volumeResponse.success) {
            $0.volumeSheet = nil
            $0.volumes[id: "v9"] = created
            $0.toast = L10n.UserManagement.toastVolumeSaved
        }
    }

    @Test
    func twoDifferentVolumeRemovalsBothComplete() async {
        let second = UserVolume(id: TestETag.second, userId: "2", label: "B", path: "/b", accessMode: .readwrite)
        let gates = [TestETag.first: AsyncGate(), TestETag.second: AsyncGate()]
        let store = makeStore(
            loadedState([makeUser(id: "2")], detail: "2", isVolumesEnabled: true, volumes: [projects, second]),
            removeVolume: { id in try await gates[id]?.wait() }
        )

        await store.send(.removeVolumeTapped(projects)) { $0.volumeToRemove = projects }
        await store.send(.removeVolumeConfirmed) {
            $0.volumeToRemove = nil
            $0.removingVolumeIDs = [TestETag.first]
        }
        await store.send(.removeVolumeTapped(second)) { $0.volumeToRemove = second }
        await store.send(.removeVolumeConfirmed) {
            $0.volumeToRemove = nil
            $0.removingVolumeIDs = [TestETag.first, TestETag.second]
        }
        gates[TestETag.first]?.open()
        await store.receive(\.removeVolumeResponse) {
            $0.removingVolumeIDs = [TestETag.second]
            $0.volumes.remove(id: TestETag.first)
            $0.toast = L10n.UserManagement.toastVolumeRemoved
        }
        gates[TestETag.second]?.open()
        await store.receive(\.removeVolumeResponse) {
            $0.removingVolumeIDs = []
            $0.volumes.remove(id: TestETag.second)
        }
        #expect(calls.value == [.removeVolume(userID: "2", volumeID: TestETag.first), .removeVolume(userID: "2", volumeID: TestETag.second)])
    }

    @Test
    func confirmingTheSameVolumeRemovalTwiceRunsASingleDeleteThatIsNeverCancelled() async {
        let gate = AsyncGate()
        let store = makeStore(
            loadedState([makeUser(id: "2")], detail: "2", isVolumesEnabled: true, volumes: [projects]),
            removeVolume: { _ in try await gate.wait() }
        )

        await store.send(.removeVolumeTapped(projects)) { $0.volumeToRemove = projects }
        await store.send(.removeVolumeConfirmed) {
            $0.volumeToRemove = nil
            $0.removingVolumeIDs = [TestETag.first]
        }
        await store.send(.removeVolumeTapped(projects)) { $0.volumeToRemove = projects }
        await store.send(.removeVolumeConfirmed) { $0.volumeToRemove = nil }
        gate.open()
        await store.receive(\.removeVolumeResponse) {
            $0.removingVolumeIDs = []
            $0.volumes.remove(id: TestETag.first)
            $0.toast = L10n.UserManagement.toastVolumeRemoved
        }
        #expect(calls.value == [.removeVolume(userID: "2", volumeID: TestETag.first)])
    }
}
