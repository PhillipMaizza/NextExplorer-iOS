import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

@MainActor
protocol TrashSettingsTestSupport {
    var settingsGate: AsyncGate { get }
    var zonesGate: AsyncGate { get }
    var settingsFetches: LockIsolated<Int> { get }
    var zoneFetches: LockIsolated<Int> { get }
    var patches: LockIsolated<[SystemSettingsPatch]> { get }
    var verifyCalls: LockIsolated<Int> { get }
    var maintenanceCalls: LockIsolated<Int> { get }
}

extension TrashSettingsTestSupport {
    typealias Store = TestStoreOf<TrashSettingsFeature>
    typealias Field = TrashSettingsFeature.VersionField

    var serverURL: URL {
        SettingsTestSupport.serverURL
    }

    var gib: Int {
        1_073_741_824
    }

    /// The settings and the volumes load side by side, so a test that loads both holds the
    /// answer it receives second until the first has been received.
    func store(
        state: TrashSettingsFeature.State? = nil,
        settings: @escaping @Sendable () async throws -> SystemSettings = { SystemSettings(trash: TrashSettings(), versions: VersionsSettings()) },
        zones: @escaping @Sendable () async throws -> [TrashZone] = { [] },
        update: @escaping @Sendable (SystemSettingsPatch) throws -> SystemSettings = { _ in SystemSettings() },
        verify: @escaping @Sendable () throws -> [TrashVerification] = { [] },
        maintain: @escaping @Sendable () throws -> Void = {}
    ) -> Store {
        let settingsFetches = settingsFetches
        let zoneFetches = zoneFetches
        let patches = patches
        let verifyCalls = verifyCalls
        let maintenanceCalls = maintenanceCalls
        return TestStore(initialState: state ?? TrashSettingsFeature.State(serverURL: serverURL)) {
            TrashSettingsFeature()
        } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in
                settingsFetches.withValue { $0 += 1 }
                return try await settings()
            }
            $0.filesClient.fetchTrashZones = { _ in
                zoneFetches.withValue { $0 += 1 }
                return try await zones()
            }
            $0.filesClient.updateSystemSettings = { _, patch in
                patches.withValue { $0.append(patch) }
                return try update(patch)
            }
            $0.filesClient.verifyTrash = { _ in
                verifyCalls.withValue { $0 += 1 }
                return try verify()
            }
            $0.filesClient.runTrashMaintenance = { _ in
                maintenanceCalls.withValue { $0 += 1 }
                try maintain()
            }
        }
    }

    func loadedState(
        trash: TrashSettings = TrashSettings(),
        versions: VersionsSettings = VersionsSettings()
    ) -> TrashSettingsFeature.State {
        var state = TrashSettingsFeature.State(serverURL: serverURL)
        state.loadedTrash = trash
        state.loadedVersions = versions
        state.trashDraft = .init(trash)
        state.versionsDraft = .init(versions)
        state.phase = .loaded
        return state
    }

    /// What the draft shows for a version field, set the way the reducer sets it.
    func settingText(_ text: String, on field: Field, in draft: inout TrashSettingsFeature.VersionsDraft) {
        switch field {
        case .keepAllHours: draft.keepAllHoursText = text
        case .hourlyDays: draft.hourlyDaysText = text
        case .dailyDays: draft.dailyDaysText = text
        case .maxPerFile: draft.maxPerFileText = text
        case .checkpointMinutes: draft.checkpointMinutesText = text
        }
    }
}
