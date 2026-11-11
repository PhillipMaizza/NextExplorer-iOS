import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing

@MainActor
struct TrashSettingsFeatureTests {
    private let serverURL = URL(string: "https://files.example.com")!
    private let gib = TrashSettings.bytesPerGiB

    private func store(
        state: TrashSettingsFeature.State? = nil,
        settings: @escaping @Sendable () throws -> SystemSettings = { SystemSettings(trash: TrashSettings(), versions: VersionsSettings()) },
        zones: @escaping @Sendable () throws -> [TrashZone] = { [] },
        update: @escaping @Sendable (SystemSettingsPatch) throws -> SystemSettings = { _ in SystemSettings() },
        verify: @escaping @Sendable () throws -> [TrashVerification] = { [] },
        maintain: @escaping @Sendable () throws -> Void = {}
    ) -> TestStoreOf<TrashSettingsFeature> {
        let store = TestStore(initialState: state ?? TrashSettingsFeature.State(serverURL: serverURL)) {
            TrashSettingsFeature()
        } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in try settings() }
            $0.filesClient.fetchTrashZones = { _ in try zones() }
            $0.filesClient.updateSystemSettings = { _, patch in try update(patch) }
            $0.filesClient.verifyTrash = { _ in try verify() }
            $0.filesClient.runTrashMaintenance = { _ in try maintain() }
        }
        store.exhaustivity = .off
        return store
    }

    private func loadedState(
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

    // MARK: Loading

    @Test
    func loadingSeedsBothFormsAndTheVolumes() async {
        let trash = TrashSettings(isEnabled: false, retentionDays: 14, maxPercent: 20, maxBytes: 2 * gib)
        let versions = VersionsSettings(isEnabled: false, keepAllHours: 6, hourlyDays: 2, dailyDays: 9, maxPerFile: 12, sessionCheckpointMinutes: 3)
        let store = store(
            settings: { SystemSettings(trash: trash, versions: versions) },
            zones: { [TrashZone(id: "z1", name: "files")] }
        )

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.loadedTrash == trash)
        #expect(store.state.loadedVersions == versions)
        #expect(store.state.trashDraft == .init(trash))
        #expect(store.state.trashDraft.maxSizeText == "2")
        #expect(store.state.versionsDraft == .init(versions))
        #expect(store.state.zones.map(\.id) == ["z1"])
        #expect(!store.state.isDirty)
    }

    @Test
    func aNonAdminResponseWithoutTheSectionsIsUnavailable() async {
        let store = store(settings: { SystemSettings() })

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.isUnavailable)
    }

    @Test
    func aResponseWithOnlyOneSectionIsUnavailable() async {
        let store = store(settings: { SystemSettings(trash: TrashSettings()) })

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.isUnavailable)
    }

    @Test
    func aSettingsFailureIsTheFailedPhase() async {
        let store = store(settings: { throw FilesClientError.server(statusCode: 500) })

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.phase.errorMessage != nil)
    }

    @Test
    func aZonesFailureShowsInTheVolumesAndKeepsTheSettings() async {
        let store = store(zones: { throw FilesClientError.offline })

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.zonesError != nil)
        #expect(store.state.loadedTrash != nil)
        #expect(store.state.phase == .loaded)
    }

    @Test
    func reloadingKeepsAFormBeingEdited() async {
        var state = loadedState()
        state.trashDraft.retentionText = "99"
        let store = store(state: state, settings: {
            SystemSettings(trash: TrashSettings(retentionDays: 7), versions: VersionsSettings(maxPerFile: 5))
        })

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.trashDraft.retentionText == "99")
        #expect(store.state.versionsDraft.maxPerFileText == "5")
        #expect(store.state.loadedTrash?.retentionDays == 7)
    }

    // MARK: Validation

    @Test(arguments: ["", "0", "3651", "99999"])
    func aTrashRetentionOutsideTheRangeBlocksSaving(text: String) async {
        let store = store(state: loadedState())

        await store.send(.retentionChanged(text))
        await store.send(.saveTapped)

        #expect(!store.state.isSaveEnabled)
        #expect(!store.state.isSaving)

        #expect(store.state.isTrashInvalid)
        #expect(!store.state.isSaveEnabled)
        #expect(!store.state.isSaving)
    }

    @Test(arguments: ["", "0", "91", "100"])
    func aSharePercentOutsideTheRangeBlocksSaving(text: String) async {
        let store = store(state: loadedState())

        await store.send(.maxPercentChanged(text))

        #expect(store.state.isTrashInvalid)
        #expect(!store.state.isSaveEnabled)
    }

    @Test(arguments: ["0", "0.0", "1.2.3", "99999999999", "999999999999999999999999"])
    func aBadSizeCapBlocksSaving(text: String) async {
        let store = store(state: loadedState())

        await store.send(.maxSizeChanged(text))

        #expect(store.state.isTrashInvalid)
    }

    @Test
    func anEmptySizeCapMeansNoCapAndIsValid() async {
        let store = store(state: loadedState(trash: TrashSettings(maxBytes: gib)))

        await store.send(.maxSizeChanged(""))

        #expect(!store.state.isTrashInvalid)
        #expect(store.state.isSaveEnabled)
        #expect(store.state.trashDraft.parsed?.maxBytes == nil)
    }

    @Test
    func numberFieldsKeepOnlyDigitsAndTheSizeKeepsTheDecimalSeparator() async {
        let store = store(state: loadedState())

        await store.send(.retentionChanged("1a2-3"))
        await store.send(.maxSizeChanged("1,5x GiB"))
        await store.send(.versionFieldChanged(.maxPerFile, "4 0"))

        #expect(store.state.trashDraft.retentionText == "123")
        #expect(store.state.trashDraft.maxSizeText == "1,5")
        #expect(store.state.versionsDraft.maxPerFileText == "40")
    }

    @Test(arguments: [
        (TrashSettingsFeature.VersionField.keepAllHours, "0"),
        (.keepAllHours, "721"),
        (.hourlyDays, "366"),
        (.dailyDays, "3651"),
        (.maxPerFile, "1001"),
        (.checkpointMinutes, "1441"),
        (.checkpointMinutes, ""),
    ])
    func aVersionValueOutsideItsRangeBlocksSaving(field: TrashSettingsFeature.VersionField, text: String) async {
        let store = store(state: loadedState())

        await store.send(.versionFieldChanged(field, text))

        #expect(store.state.isVersionsInvalid)
        #expect(!store.state.isSaveEnabled)
    }

    @Test
    func anUntouchedFormIsNeverInvalid() {
        let state = loadedState()

        #expect(!state.isTrashInvalid)
        #expect(!state.isVersionsInvalid)
        #expect(!state.isSaveEnabled)
    }

    @Test
    func aBadTrashFormBlocksSavingEvenWhenTheVersionsFormIsFine() async {
        let store = store(state: loadedState())

        await store.send(.versionFieldChanged(.maxPerFile, "60"))
        #expect(store.state.isSaveEnabled)

        await store.send(.retentionChanged("0"))
        #expect(!store.state.isSaveEnabled)
    }

    // MARK: Saving

    @Test
    func savingOnlyTheTrashFormSendsOnlyTheTrashSection() async {
        let sent = LockIsolated<SystemSettingsPatch?>(nil)
        let echoed = TrashSettings(isEnabled: true, retentionDays: 7, maxPercent: 10, maxBytes: nil)
        let store = store(state: loadedState(), update: { patch in
            sent.setValue(patch)
            return SystemSettings(trash: echoed, versions: VersionsSettings())
        })

        await store.send(.retentionChanged("7"))
        await store.send(.saveTapped)
        await store.skipReceivedActions()

        #expect(sent.value?.trash == echoed)
        #expect(sent.value?.versions == nil)
        #expect(store.state.loadedTrash == echoed)
        #expect(!store.state.isDirty)
        #expect(!store.state.isSaving)
    }

    @Test
    func savingOnlyTheVersionsFormSendsOnlyTheVersionsSection() async {
        let sent = LockIsolated<SystemSettingsPatch?>(nil)
        let echoed = VersionsSettings(maxPerFile: 60)
        let store = store(state: loadedState(), update: { patch in
            sent.setValue(patch)
            return SystemSettings(trash: TrashSettings(), versions: echoed)
        })

        await store.send(.versionFieldChanged(.maxPerFile, "60"))
        await store.send(.saveTapped)
        await store.skipReceivedActions()

        #expect(sent.value?.trash == nil)
        #expect(sent.value?.versions == echoed)
        #expect(store.state.loadedVersions == echoed)
    }

    @Test
    func savingBothSendsBothAndAdoptsTheServersValues() async {
        let sent = LockIsolated<SystemSettingsPatch?>(nil)
        let store = store(state: loadedState(), update: { patch in
            sent.setValue(patch)
            return SystemSettings(trash: TrashSettings(isEnabled: false), versions: VersionsSettings(isEnabled: false))
        })

        await store.send(.trashEnabledChanged(false))
        await store.send(.versionsEnabledChanged(false))
        await store.send(.saveTapped)
        await store.skipReceivedActions()

        #expect(sent.value?.trash?.isEnabled == false)
        #expect(sent.value?.versions?.isEnabled == false)
        #expect(!store.state.isDirty)
    }

    @Test
    func theSizeCapIsSavedInBytesAndAClearedCapGoesOutAsNone() async {
        let sent = LockIsolated<SystemSettingsPatch?>(nil)
        let store = store(state: loadedState(trash: TrashSettings(maxBytes: gib)), update: { patch in
            sent.setValue(patch)
            return SystemSettings(trash: patch.trash, versions: VersionsSettings())
        })

        await store.send(.maxSizeChanged("2,5"))
        await store.send(.saveTapped)
        await store.skipReceivedActions()
        #expect(sent.value?.trash?.maxBytes == 2_684_354_560)

        await store.send(.maxSizeChanged(""))
        await store.send(.saveTapped)
        await store.skipReceivedActions()
        #expect(sent.value?.trash?.maxBytes == nil)
    }

    @Test
    func aFailedSaveKeepsTheDraftAndShowsTheMessage() async {
        let store = store(state: loadedState(), update: { _ in throw FilesClientError.serverMessage(statusCode: 400, message: "Bad value.") })

        await store.send(.retentionChanged("7"))
        await store.send(.saveTapped)
        await store.skipReceivedActions()

        #expect(store.state.errorMessage == "Bad value.")
        #expect(store.state.trashDraft.retentionText == "7")
        #expect(store.state.isDirty)
        #expect(!store.state.isSaving)
    }

    @Test
    func anEchoWithoutTheSectionIsAFailedSave() async {
        let store = store(state: loadedState(), update: { _ in SystemSettings() })

        await store.send(.retentionChanged("7"))
        await store.send(.saveTapped)
        await store.skipReceivedActions()

        #expect(store.state.errorMessage != nil)
        #expect(!store.state.isSaving)
    }

    @Test
    func discardingRestoresBothForms() async {
        let store = store(state: loadedState())

        await store.send(.retentionChanged("7"))
        await store.send(.versionFieldChanged(.maxPerFile, "9"))
        await store.send(.discardTapped)

        #expect(!store.state.isDirty)
        #expect(store.state.trashDraft.retentionText == "30")
        #expect(store.state.versionsDraft.maxPerFileText == "50")
    }

    @Test
    func savingReloadsTheVolumes() async {
        let calls = LockIsolated(0)
        let store = store(state: loadedState(), zones: {
            calls.withValue { $0 += 1 }
            return []
        }, update: { _ in SystemSettings(trash: TrashSettings(retentionDays: 7), versions: VersionsSettings()) })

        await store.send(.retentionChanged("7"))
        await store.send(.saveTapped)
        await store.skipReceivedActions()

        #expect(calls.value == 1)
    }

    // MARK: Verify and maintenance

    @Test
    func verifyStoresTheResultsAndTotalsTheProblems() async {
        let store = store(state: loadedState(), verify: {
            [TrashVerification(zoneID: "z1", violations: [.init(invariant: "I1", detail: "content missing"), .init(invariant: "I4", detail: "left in state x")]), TrashVerification(zoneID: "z2", violations: [.init(invariant: "I1", detail: "content missing")])]
        })

        await store.send(.verifyTapped)
        await store.skipReceivedActions()

        #expect(store.state.totalViolations == 3)
        #expect(!store.state.isVerifying)
    }

    @Test
    func aCleanVerifyHasNoProblems() async {
        let store = store(state: loadedState(), verify: { [TrashVerification(zoneID: "z1")] })

        await store.send(.verifyTapped)
        await store.skipReceivedActions()

        #expect(store.state.verification != nil)
        #expect(store.state.totalViolations == 0)
    }

    @Test
    func aFailedVerifyShowsTheError() async {
        let store = store(state: loadedState(), verify: { throw FilesClientError.server(statusCode: 500) })

        await store.send(.verifyTapped)
        await store.skipReceivedActions()

        #expect(store.state.zonesError != nil)
        #expect(store.state.verification == nil)
        #expect(!store.state.isVerifying)
    }

    @Test
    func maintenanceRunsThenReloadsTheVolumesAndForgetsTheVerification() async {
        let ran = LockIsolated(false)
        var state = loadedState()
        state.verification = [TrashVerification(zoneID: "z1", violations: [.init(invariant: "I1", detail: "content missing")])]
        let store = store(state: state, zones: { [TrashZone(id: "z9", name: "fresh")] }, maintain: {
            ran.setValue(true)
        })

        await store.send(.maintenanceTapped)
        await store.skipReceivedActions()

        #expect(ran.value)
        #expect(store.state.verification == nil)
        #expect(store.state.zones.map(\.id) == ["z9"])
        #expect(!store.state.isMaintaining)
    }

    @Test
    func aFailedMaintenanceShowsTheErrorAndKeepsTheVolumes() async {
        var state = loadedState()
        state.zones = [TrashZone(id: "z1", name: "files")]
        let store = store(state: state, maintain: { throw FilesClientError.server(statusCode: 500) })

        await store.send(.maintenanceTapped)
        await store.skipReceivedActions()

        #expect(store.state.zonesError != nil)
        #expect(store.state.zones.map(\.id) == ["z1"])
        #expect(!store.state.isMaintaining)
    }

    // MARK: Journal wording

    @Test(arguments: [
        ("evicted", "a.txt"),
        ("version-evicted", "a.txt"),
        ("version-too-large", "a.txt"),
        ("forgotten", "a.txt"),
    ])
    func journalLinesNameTheItem(kind: String, name: String) {
        #expect(TrashEventLabel.text(for: TrashEvent(id: "1", kind: kind, itemName: name)).contains(name))
    }

    @Test
    func anUnknownJournalKindShowsItsOwnName() {
        #expect(TrashEventLabel.text(for: TrashEvent(id: "1", kind: "something-new")) == "something-new")
    }

    // MARK: Admin only

    @Test
    func aNonAdminCannotOpenTrashSettings() async {
        let user = User(id: "1", username: "jdoe", email: nil, roles: [])
        let store = TestStore(initialState: SettingsFeature.State(serverURL: serverURL, user: user)) { SettingsFeature() }

        await store.send(.trashSettingsButtonTapped)

        #expect(store.state.trashSettings == nil)
    }

    @Test
    func anAdminOpensTrashSettings() async {
        let admin = User(id: "a", username: "boss", email: nil, roles: [UserRole.admin])
        let store = TestStore(initialState: SettingsFeature.State(serverURL: serverURL, user: admin)) { SettingsFeature() }

        await store.send(.trashSettingsButtonTapped) { $0.trashSettings = TrashSettingsFeature.State(serverURL: serverURL) }
    }

    // MARK: Reloads, tiers and volumes

    @Test
    func aReloadThatLandsDuringASaveIsIgnored() async {
        var state = loadedState()
        state.isSaving = true
        let store = store(state: state)

        await store.send(.settingsResponse(.success(SystemSettings(trash: TrashSettings(retentionDays: 1), versions: VersionsSettings()))))

        #expect(store.state.loadedTrash?.retentionDays == 30)
    }

    @Test
    func aFailedReloadKeepsTheLoadedFormAndShowsTheMessage() async {
        let store = store(state: loadedState())

        await store.send(.settingsResponse(.failure(.offline)))

        #expect(store.state.phase == .loaded)
        #expect(store.state.errorMessage != nil)
        #expect(store.state.loadedTrash != nil)
    }

    @Test
    func aFailedVolumesReadWithNothingShownIsTheFailedPhase() async {
        let store = store(state: loadedState())

        await store.send(.zonesResponse(.failure(.offline)))

        #expect(store.state.zonesPhase.errorMessage != nil)
        #expect(store.state.zonesError != nil)
    }

    @Test
    func theTiersAreKeptInOrderTheWayTheServerDoes() {
        var draft = TrashSettingsFeature.VersionsDraft()
        draft.keepAllHoursText = "720"
        draft.hourlyDaysText = "1"
        draft.dailyDaysText = "1"

        #expect(draft.parsed?.hourlyDays == 30)
        #expect(draft.parsed?.dailyDays == 30)
    }

    @Test
    func tiersAlreadyInOrderAreSentAsTyped() {
        var draft = TrashSettingsFeature.VersionsDraft()
        draft.keepAllHoursText = "25"
        draft.hourlyDaysText = "7"
        draft.dailyDaysText = "30"

        #expect(draft.parsed?.hourlyDays == 7)
        #expect(draft.parsed?.dailyDays == 30)
    }

    @Test
    func numberFieldsDropDigitsOfOtherScripts() async {
        let store = store(state: loadedState())

        await store.send(.retentionChanged("١٢½3"))

        #expect(store.state.trashDraft.retentionText == "3")
    }

    @Test
    func anUntouchedSizeCapIsSentBackAsTheServerHeldIt() async {
        let cap = 1_536_000_000
        let store = store(state: loadedState(trash: TrashSettings(maxBytes: cap)))

        await store.send(.retentionChanged("14"))

        #expect(store.state.trashDraft.parsed?.maxBytes == cap)
    }

    @Test
    func aTinySizeCapThatShowsAsZeroStaysValidUntilEdited() async {
        let cap = 1_000_000
        let store = store(state: loadedState(trash: TrashSettings(maxBytes: cap)))

        await store.send(.retentionChanged("14"))

        #expect(store.state.trashDraft.maxSizeText == "0")
        #expect(!store.state.isTrashInvalid)
        #expect(store.state.trashDraft.parsed?.maxBytes == cap)
    }

    @Test
    func aCapTypedOverTheOldOneIsSentAsTyped() async {
        let store = store(state: loadedState(trash: TrashSettings(maxBytes: 1_536_000_000)))

        await store.send(.maxSizeChanged("2"))

        #expect(store.state.trashDraft.parsed?.maxBytes == 2 * gib)
    }

    @Test
    func aSaveInFlightIgnoresAnAppearingAgain() async {
        var state = loadedState()
        state.isSaving = true
        let store = store(state: state, settings: {
            Issue.record("No reload while a save is under way")
            return SystemSettings()
        })

        await store.send(.onAppear)
    }
}
