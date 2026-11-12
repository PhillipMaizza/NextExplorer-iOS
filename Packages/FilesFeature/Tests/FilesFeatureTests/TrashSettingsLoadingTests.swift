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
struct TrashSettingsLoadingTests: TrashSettingsTestSupport {
    let settingsGate = AsyncGate()
    let zonesGate = AsyncGate()
    let settingsFetches = LockIsolated(0)
    let zoneFetches = LockIsolated(0)
    let patches = LockIsolated<[SystemSettingsPatch]>([])
    let verifyCalls = LockIsolated(0)
    let maintenanceCalls = LockIsolated(0)

    @Test
    func loadingSeedsBothFormsAndTheVolumes() async {
        let trash = TrashSettings(isEnabled: false, retentionDays: 14, maxPercent: 20, maxBytes: 2 * gib)
        let versions = VersionsSettings(isEnabled: false, keepAllHours: 6, hourlyDays: 2, dailyDays: 9, maxPerFile: 12, sessionCheckpointMinutes: 3)
        let zone = TrashZone(id: "z1", name: "files")
        let store = store(
            settings: { SystemSettings(trash: trash, versions: versions) },
            zones: {
                try await zonesGate.wait()
                return [zone]
            }
        )

        await store.send(.onAppear) {
            $0.phase = .loading
            $0.zonesPhase = .loading
        }
        await store.receive(\.settingsResponse.success) {
            $0.phase = .loaded
            $0.loadedTrash = trash
            $0.loadedVersions = versions
            $0.trashDraft = TrashSettingsFeature.TrashDraft(trash)
            $0.versionsDraft = TrashSettingsFeature.VersionsDraft(versions)
        }
        zonesGate.open()
        await store.receive(\.zonesResponse.success) {
            $0.zonesPhase = .loaded
            $0.zones = [zone]
        }

        let trashDraft = store.state.trashDraft
        #expect(!trashDraft.isEnabled)
        #expect(trashDraft.retentionText == "14")
        #expect(trashDraft.maxPercentText == "20")
        #expect(trashDraft.maxSizeText == "2")
        let versionsDraft = store.state.versionsDraft
        #expect(!versionsDraft.isEnabled)
        #expect([versionsDraft.keepAllHoursText, versionsDraft.hourlyDaysText, versionsDraft.dailyDaysText, versionsDraft.maxPerFileText, versionsDraft.checkpointMinutesText] == ["6", "2", "9", "12", "3"])
        #expect(!store.state.isDirty)
        #expect(settingsFetches.value == 1)
        #expect(zoneFetches.value == 1)
    }

    @Test(arguments: [
        SystemSettings(),
        SystemSettings(trash: TrashSettings()),
        SystemSettings(versions: VersionsSettings()),
    ])
    func aResponseWithoutBothSectionsIsUnavailable(_ response: SystemSettings) async {
        let store = store(settings: { response }, zones: {
            try await zonesGate.wait()
            return []
        })

        await store.send(.onAppear) {
            $0.phase = .loading
            $0.zonesPhase = .loading
        }
        await store.receive(\.settingsResponse.success) {
            $0.phase = .loaded
            $0.isUnavailable = true
        }
        zonesGate.open()
        await store.receive(\.zonesResponse.success) { $0.zonesPhase = .loaded }

        #expect(store.state.loadedTrash == nil)
    }

    @Test
    func aSettingsFailureIsTheFailedPhase() async {
        let store = store(settings: { throw FilesClientError.server(statusCode: 500) }, zones: {
            try await zonesGate.wait()
            return []
        })

        await store.send(.onAppear) {
            $0.phase = .loading
            $0.zonesPhase = .loading
        }
        await store.receive(\.settingsResponse.failure) { $0.phase = .failed(L10n.Error.server(500)) }
        zonesGate.open()
        await store.receive(\.zonesResponse.success) { $0.zonesPhase = .loaded }
    }

    @Test
    func aZonesFailureShowsInTheVolumesAndKeepsTheSettings() async {
        let store = store(settings: {
            SystemSettings(trash: TrashSettings(), versions: VersionsSettings())
        }, zones: {
            try await zonesGate.wait()
            throw FilesClientError.offline
        })

        await store.send(.onAppear) {
            $0.phase = .loading
            $0.zonesPhase = .loading
        }
        await store.receive(\.settingsResponse.success) {
            $0.phase = .loaded
            $0.loadedTrash = TrashSettings()
            $0.loadedVersions = VersionsSettings()
        }
        zonesGate.open()
        await store.receive(\.zonesResponse.failure) {
            $0.zonesPhase = .failed(L10n.Error.offline)
            $0.zonesError = L10n.Error.offline
        }
    }

    @Test
    func reloadingKeepsAFormBeingEdited() async {
        var state = loadedState()
        state.trashDraft.retentionText = "99"
        let store = store(state: state, settings: {
            SystemSettings(trash: TrashSettings(retentionDays: 7), versions: VersionsSettings(maxPerFile: 5))
        }, zones: {
            try await zonesGate.wait()
            return []
        })

        await store.send(.onAppear) { $0.zonesPhase = .loading }
        await store.receive(\.settingsResponse.success) {
            $0.loadedTrash = TrashSettings(retentionDays: 7)
            $0.loadedVersions = VersionsSettings(maxPerFile: 5)
            $0.versionsDraft = TrashSettingsFeature.VersionsDraft(VersionsSettings(maxPerFile: 5))
        }
        zonesGate.open()
        await store.receive(\.zonesResponse.success) { $0.zonesPhase = .loaded }

        #expect(store.state.trashDraft.retentionText == "99")
        #expect(store.state.versionsDraft.maxPerFileText == "5")
    }

    @Test
    func aSaveInFlightIgnoresAnAppearingAgain() async {
        var state = loadedState()
        state.isSaving = true
        let store = store(state: state)

        await store.send(.onAppear)

        #expect(settingsFetches.value == 0)
        #expect(zoneFetches.value == 0)
    }

    @Test
    func aReloadThatLandsDuringASaveIsIgnored() async {
        var state = loadedState()
        state.isSaving = true
        let store = store(state: state)

        await store.send(.settingsResponse(.success(SystemSettings(trash: TrashSettings(retentionDays: 1), versions: VersionsSettings()))))

        #expect(store.state.loadedTrash == TrashSettings(retentionDays: 30))
    }

    @Test
    func aFailedReloadKeepsTheLoadedFormAndShowsTheMessage() async {
        let store = store(state: loadedState())

        await store.send(.settingsResponse(.failure(.offline))) { $0.errorMessage = L10n.Error.offline }

        #expect(store.state.phase == .loaded)
    }

    @Test
    func aFailedVolumesReadWithNothingShownIsTheFailedPhase() async {
        let store = store(state: loadedState())

        await store.send(.zonesResponse(.failure(.offline))) {
            $0.zonesPhase = .failed(L10n.Error.offline)
            $0.zonesError = L10n.Error.offline
        }
    }

    @Test
    func aFailedVolumesReadKeepsTheVolumesAlreadyShown() async {
        var state = loadedState()
        state.zones = [TrashZone(id: "z1", name: "files")]
        let store = store(state: state)

        await store.send(.zonesResponse(.failure(.offline))) {
            $0.zonesPhase = .loaded
            $0.zonesError = L10n.Error.offline
        }

        #expect(store.state.zones.map(\.id) == ["z1"])
    }
}
