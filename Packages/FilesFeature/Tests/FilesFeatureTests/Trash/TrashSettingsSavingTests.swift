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
struct TrashSettingsSavingTests: TrashSettingsTestSupport {
    let settingsGate = AsyncGate()
    let zonesGate = AsyncGate()
    let settingsFetches = LockIsolated(0)
    let zoneFetches = LockIsolated(0)
    let patches = LockIsolated<[SystemSettingsPatch]>([])
    let verifyCalls = LockIsolated(0)
    let maintenanceCalls = LockIsolated(0)

    @Test
    func savingOnlyTheTrashFormSendsOnlyTheTrashSectionAndReloadsTheVolumes() async {
        let echoed = TrashSettings(isEnabled: true, retentionDays: 7, maxPercent: 10, maxBytes: nil)
        let store = store(
            state: loadedState(),
            update: { _ in SystemSettings(trash: echoed, versions: VersionsSettings()) }
        )

        await store.send(.retentionChanged("7")) { $0.trashDraft.retentionText = "7" }
        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(.saveResponse(.success(TrashSettingsFeature.SavedSettings(trash: echoed, versions: nil)))) {
            $0.isSaving = false
            $0.loadedTrash = echoed
            $0.zonesPhase = .loading
        }
        await store.receive(\.zonesResponse.success) { $0.zonesPhase = .loaded }

        #expect(patches.value.map(\.trash) == [echoed])
        #expect(patches.value.map(\.versions) == [nil])
        #expect(store.state.trashDraft.retentionText == "7")
        #expect(!store.state.isDirty)
        #expect(zoneFetches.value == 1)
    }

    @Test
    func savingOnlyTheVersionsFormSendsOnlyTheVersionsSection() async {
        let echoed = VersionsSettings(maxPerFile: 60)
        let store = store(
            state: loadedState(),
            update: { _ in SystemSettings(trash: TrashSettings(), versions: echoed) }
        )

        await store.send(.versionFieldChanged(.maxPerFile, "60")) { $0.versionsDraft.maxPerFileText = "60" }
        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(.saveResponse(.success(TrashSettingsFeature.SavedSettings(trash: nil, versions: echoed)))) {
            $0.isSaving = false
            $0.loadedVersions = echoed
            $0.zonesPhase = .loading
        }
        await store.receive(\.zonesResponse.success) { $0.zonesPhase = .loaded }

        #expect(patches.value.map(\.trash) == [nil])
        #expect(patches.value.map(\.versions) == [echoed])
        #expect(!store.state.isDirty)
    }

    @Test
    func savingBothSendsBothAndAdoptsTheServersValues() async {
        let trash = TrashSettings(isEnabled: false)
        let versions = VersionsSettings(isEnabled: false)
        let store = store(state: loadedState(), update: { _ in SystemSettings(trash: trash, versions: versions) })

        await store.send(.trashEnabledChanged(false)) { $0.trashDraft.isEnabled = false }
        await store.send(.versionsEnabledChanged(false)) { $0.versionsDraft.isEnabled = false }
        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(.saveResponse(.success(TrashSettingsFeature.SavedSettings(
            trash: trash,
            versions: versions
        )))) {
            $0.isSaving = false
            $0.loadedTrash = trash
            $0.loadedVersions = versions
            $0.zonesPhase = .loading
        }
        await store.receive(\.zonesResponse.success) { $0.zonesPhase = .loaded }

        #expect(patches.value.map(\.trash) == [trash])
        #expect(patches.value.map(\.versions) == [versions])
        #expect(!store.state.isDirty)
    }

    struct SizeCase: Sendable {
        let text: String
        let bytes: Int?
    }

    @Test(arguments: [
        SizeCase(text: "2,5", bytes: 2_684_354_560),
        SizeCase(text: "", bytes: nil),
    ])
    func theSizeCapIsSavedInBytesAndAClearedCapGoesOutAsNone(_ testCase: SizeCase) async {
        let echoed = TrashSettings(maxBytes: testCase.bytes)
        let store = store(state: loadedState(trash: TrashSettings(maxBytes: 1_073_741_824)), update: { _ in
            SystemSettings(trash: echoed, versions: VersionsSettings())
        })

        await store.send(.maxSizeChanged(testCase.text)) { $0.trashDraft.maxSizeText = testCase.text }
        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(.saveResponse(.success(TrashSettingsFeature.SavedSettings(trash: echoed, versions: nil)))) {
            $0.isSaving = false
            $0.loadedTrash = echoed
            $0.trashDraft = TrashSettingsFeature.TrashDraft(echoed)
            $0.zonesPhase = .loading
        }
        await store.receive(\.zonesResponse.success) { $0.zonesPhase = .loaded }

        #expect(patches.value.map(\.trash) == [echoed])
    }

    @Test
    func aSaveStartedWhileAnotherIsRunningSendsNothing() async {
        var state = loadedState()
        state.trashDraft.retentionText = "7"
        state.isSaving = true
        let store = store(state: state)

        await store.send(.saveTapped)

        #expect(patches.value.isEmpty)
    }

    @Test
    func aSaveStopsAnOlderSettingsReadSoItCannotLandOverIt() async {
        let echoed = TrashSettings(retentionDays: 7)
        let store = store(
            state: loadedState(),
            settings: {
                try await settingsGate.wait()
                return SystemSettings(trash: TrashSettings(retentionDays: 1), versions: VersionsSettings())
            },
            update: { _ in SystemSettings(trash: echoed, versions: VersionsSettings()) }
        )

        await store.send(.onAppear) { $0.zonesPhase = .loading }
        await store.receive(\.zonesResponse.success) { $0.zonesPhase = .loaded }
        await store.send(.retentionChanged("7")) { $0.trashDraft.retentionText = "7" }
        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(.saveResponse(.success(TrashSettingsFeature.SavedSettings(trash: echoed, versions: nil)))) {
            $0.isSaving = false
            $0.loadedTrash = echoed
        }
        await store.receive(\.zonesResponse.success)
        await store.finish()

        #expect(store.state.loadedTrash == echoed)
    }

    @Test
    func aFailedSaveKeepsTheDraftAndShowsTheMessage() async {
        let store = store(
            state: loadedState(),
            update: { _ in throw FilesClientError.serverMessage(statusCode: 400, message: "Bad value.") }
        )

        await store.send(.retentionChanged("7")) { $0.trashDraft.retentionText = "7" }
        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(\.saveResponse.failure) {
            $0.isSaving = false
            $0.errorMessage = "Bad value."
        }

        #expect(store.state.isDirty)
    }

    @Test
    func anEchoWithoutTheTrashSectionIsAFailedSave() async {
        let store = store(state: loadedState(), update: { _ in SystemSettings(versions: VersionsSettings()) })

        await store.send(.retentionChanged("7")) { $0.trashDraft.retentionText = "7" }
        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(.saveResponse(.failure(.decoding("Settings response carried no trash settings.")))) {
            $0.isSaving = false
            $0.errorMessage = L10n.Error.decoding
        }
    }

    @Test
    func anEchoWithoutTheVersionsSectionIsAFailedSave() async {
        let store = store(state: loadedState(), update: { _ in SystemSettings(trash: TrashSettings()) })

        await store.send(.versionFieldChanged(.maxPerFile, "9")) { $0.versionsDraft.maxPerFileText = "9" }
        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(.saveResponse(.failure(.decoding("Settings response carried no version settings.")))) {
            $0.isSaving = false
            $0.errorMessage = L10n.Error.decoding
        }
    }

    @Test
    func discardingRestoresBothForms() async {
        var state = loadedState()
        state.errorMessage = TestValue.outdated
        let store = store(state: state)

        await store.send(.retentionChanged("7")) {
            $0.trashDraft.retentionText = "7"
            $0.errorMessage = nil
        }
        await store.send(.versionFieldChanged(.maxPerFile, "9")) { $0.versionsDraft.maxPerFileText = "9" }
        await store.send(.discardTapped) {
            $0.trashDraft.retentionText = "30"
            $0.versionsDraft.maxPerFileText = "50"
        }

        #expect(!store.state.isDirty)
    }
}
