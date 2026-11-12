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
struct TrashSettingsFeatureTests {
    private typealias Store = TestStoreOf<TrashSettingsFeature>
    private typealias Field = TrashSettingsFeature.VersionField

    private let serverURL = SettingsTestSupport.serverURL
    private let gib = 1_073_741_824
    private let settingsGate = AsyncGate()
    private let zonesGate = AsyncGate()
    private let settingsFetches = LockIsolated(0)
    private let zoneFetches = LockIsolated(0)
    private let patches = LockIsolated<[SystemSettingsPatch]>([])
    private let verifyCalls = LockIsolated(0)
    private let maintenanceCalls = LockIsolated(0)

    /// The settings and the volumes load side by side, so a test that loads both holds the
    /// answer it receives second until the first has been received.
    private func store(
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

    /// What the draft shows for a version field, set the way the reducer sets it.
    private func settingText(_ text: String, on field: Field, in draft: inout TrashSettingsFeature.VersionsDraft) {
        switch field {
        case .keepAllHours: draft.keepAllHoursText = text
        case .hourlyDays: draft.hourlyDaysText = text
        case .dailyDays: draft.dailyDaysText = text
        case .maxPerFile: draft.maxPerFileText = text
        case .checkpointMinutes: draft.checkpointMinutesText = text
        }
    }

    // MARK: Loading

    @Test
    func loadingSeedsBothFormsAndTheVolumes() async {
        let trash = TrashSettings(isEnabled: false, retentionDays: 14, maxPercent: 20, maxBytes: 2 * gib)
        let versions = VersionsSettings(isEnabled: false, keepAllHours: 6, hourlyDays: 2, dailyDays: 9, maxPerFile: 12, sessionCheckpointMinutes: 3)
        let zone = TrashZone(id: "z1", name: "files")
        let store = store(
            settings: { SystemSettings(trash: trash, versions: versions) },
            zones: {
                try await self.zonesGate.wait()
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
            try await self.zonesGate.wait()
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
            try await self.zonesGate.wait()
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
            try await self.zonesGate.wait()
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
            try await self.zonesGate.wait()
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

    // MARK: Validation

    @Test(arguments: ["", "0", "3651", "99999"])
    func aTrashRetentionOutsideTheRangeBlocksSaving(text: String) async {
        let store = store(state: loadedState())

        await store.send(.retentionChanged(text)) { $0.trashDraft.retentionText = text }
        await store.send(.saveTapped)

        #expect(store.state.isTrashInvalid)
        #expect(!store.state.isSaveEnabled)
        #expect(patches.value.isEmpty)
    }

    @Test(arguments: ["", "0", "91", "100"])
    func aSharePercentOutsideTheRangeBlocksSaving(text: String) async {
        let store = store(state: loadedState())

        await store.send(.maxPercentChanged(text)) { $0.trashDraft.maxPercentText = text }

        #expect(store.state.isTrashInvalid)
        #expect(!store.state.isSaveEnabled)
    }

    @Test(arguments: ["0", "0.0", "1.2.3", "99999999999", "999999999999999999999999"])
    func aBadSizeCapBlocksSaving(text: String) async {
        let store = store(state: loadedState())

        await store.send(.maxSizeChanged(text)) { $0.trashDraft.maxSizeText = text }

        #expect(store.state.isTrashInvalid)
        #expect(!store.state.isSaveEnabled)
    }

    @Test
    func anEmptySizeCapMeansNoCapAndIsValid() async {
        let store = store(state: loadedState(trash: TrashSettings(maxBytes: gib)))

        await store.send(.maxSizeChanged("")) { $0.trashDraft.maxSizeText = "" }

        #expect(!store.state.isTrashInvalid)
        #expect(store.state.isSaveEnabled)
        #expect(store.state.trashDraft.parsed == TrashSettings(maxBytes: nil))
    }

    @Test
    func numberFieldsKeepOnlyDigitsAndTheSizeKeepsTheDecimalSeparator() async {
        let store = store(state: loadedState())

        await store.send(.retentionChanged("1a2-3")) { $0.trashDraft.retentionText = "123" }
        await store.send(.maxSizeChanged("1,5x GiB")) { $0.trashDraft.maxSizeText = "1,5" }
        await store.send(.versionFieldChanged(.maxPerFile, "4 0")) { $0.versionsDraft.maxPerFileText = "40" }
    }

    @Test
    func numberFieldsDropDigitsOfOtherScripts() async {
        let store = store(state: loadedState())

        await store.send(.retentionChanged("١٢½3")) { $0.trashDraft.retentionText = "3" }
    }

    struct VersionCase: Sendable {
        let field: TrashSettingsFeature.VersionField
        let text: String
    }

    @Test(arguments: [
        VersionCase(field: .keepAllHours, text: "0"),
        VersionCase(field: .keepAllHours, text: "721"),
        VersionCase(field: .hourlyDays, text: "366"),
        VersionCase(field: .dailyDays, text: "3651"),
        VersionCase(field: .maxPerFile, text: "1001"),
        VersionCase(field: .checkpointMinutes, text: "1441"),
        VersionCase(field: .checkpointMinutes, text: ""),
    ])
    func aVersionValueOutsideItsRangeBlocksSaving(_ testCase: VersionCase) async {
        let store = store(state: loadedState())

        await store.send(.versionFieldChanged(testCase.field, testCase.text)) {
            self.settingText(testCase.text, on: testCase.field, in: &$0.versionsDraft)
        }

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

        await store.send(.versionFieldChanged(.maxPerFile, "60")) { $0.versionsDraft.maxPerFileText = "60" }
        #expect(store.state.isSaveEnabled)

        await store.send(.retentionChanged("0")) { $0.trashDraft.retentionText = "0" }
        #expect(!store.state.isSaveEnabled)
    }

    struct TierCase: Sendable {
        let keepAllHours: String
        let hourlyDays: String
        let dailyDays: String
        let expectedHourly: Int
        let expectedDaily: Int
    }

    @Test(arguments: [
        TierCase(keepAllHours: "720", hourlyDays: "1", dailyDays: "1", expectedHourly: 30, expectedDaily: 30),
        TierCase(keepAllHours: "25", hourlyDays: "1", dailyDays: "1", expectedHourly: 2, expectedDaily: 2),
        TierCase(keepAllHours: "24", hourlyDays: "1", dailyDays: "1", expectedHourly: 1, expectedDaily: 1),
        TierCase(keepAllHours: "25", hourlyDays: "7", dailyDays: "30", expectedHourly: 7, expectedDaily: 30),
    ])
    func theTiersAreKeptInOrderTheWayTheServerDoes(_ testCase: TierCase) {
        var draft = TrashSettingsFeature.VersionsDraft()
        draft.keepAllHoursText = testCase.keepAllHours
        draft.hourlyDaysText = testCase.hourlyDays
        draft.dailyDaysText = testCase.dailyDays

        #expect(draft.parsed?.hourlyDays == testCase.expectedHourly)
        #expect(draft.parsed?.dailyDays == testCase.expectedDaily)
    }

    @Test
    func anUntouchedSizeCapIsSentBackAsTheServerHeldIt() async {
        let store = store(state: loadedState(trash: TrashSettings(maxBytes: 1_536_000_000)))

        await store.send(.retentionChanged("14")) { $0.trashDraft.retentionText = "14" }

        #expect(store.state.trashDraft.maxSizeText == "1.43")
        #expect(store.state.trashDraft.parsed?.maxBytes == 1_536_000_000)
    }

    @Test
    func aTinySizeCapThatShowsAsZeroStaysValidUntilEdited() async {
        let store = store(state: loadedState(trash: TrashSettings(maxBytes: 1_000_000)))

        await store.send(.retentionChanged("14")) { $0.trashDraft.retentionText = "14" }

        #expect(store.state.trashDraft.maxSizeText == "0")
        #expect(!store.state.isTrashInvalid)
        #expect(store.state.trashDraft.parsed?.maxBytes == 1_000_000)
    }

    @Test
    func aCapTypedOverTheOldOneIsSentAsTyped() async {
        let store = store(state: loadedState(trash: TrashSettings(maxBytes: 1_536_000_000)))

        await store.send(.maxSizeChanged("2")) { $0.trashDraft.maxSizeText = "2" }

        #expect(store.state.trashDraft.parsed?.maxBytes == 2_147_483_648)
    }

    // MARK: Saving

    @Test
    func savingOnlyTheTrashFormSendsOnlyTheTrashSectionAndReloadsTheVolumes() async {
        let echoed = TrashSettings(isEnabled: true, retentionDays: 7, maxPercent: 10, maxBytes: nil)
        let store = store(state: loadedState(), update: { _ in SystemSettings(trash: echoed, versions: VersionsSettings()) })

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
        let store = store(state: loadedState(), update: { _ in SystemSettings(trash: TrashSettings(), versions: echoed) })

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
        await store.receive(.saveResponse(.success(TrashSettingsFeature.SavedSettings(trash: trash, versions: versions)))) {
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
                try await self.settingsGate.wait()
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
        let store = store(state: loadedState(), update: { _ in throw FilesClientError.serverMessage(statusCode: 400, message: "Bad value.") })

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
        state.errorMessage = "old"
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

    // MARK: Verify and maintenance

    @Test
    func verifyStoresTheResultsAndTotalsTheProblems() async {
        let results = [
            TrashVerification(zoneID: "z1", violations: [
                .init(invariant: "I1", detail: "content missing"),
                .init(invariant: "I4", detail: "left in state x"),
            ]),
            TrashVerification(zoneID: "z2", violations: [.init(invariant: "I1", detail: "content missing")]),
        ]
        let store = store(state: loadedState(), verify: { results })

        await store.send(.verifyTapped) { $0.isVerifying = true }
        await store.receive(\.verifyResponse.success) {
            $0.isVerifying = false
            $0.verification = results
        }

        #expect(store.state.totalViolations == 3)
    }

    @Test
    func aCleanVerifyHasNoProblems() async {
        let store = store(state: loadedState(), verify: { [TrashVerification(zoneID: "z1")] })

        await store.send(.verifyTapped) { $0.isVerifying = true }
        await store.receive(\.verifyResponse.success) {
            $0.isVerifying = false
            $0.verification = [TrashVerification(zoneID: "z1")]
        }

        #expect(store.state.totalViolations == 0)
    }

    @Test
    func aFailedVerifyShowsTheError() async {
        let store = store(state: loadedState(), verify: { throw FilesClientError.server(statusCode: 500) })

        await store.send(.verifyTapped) { $0.isVerifying = true }
        await store.receive(\.verifyResponse.failure) {
            $0.isVerifying = false
            $0.zonesError = L10n.Error.server(500)
        }

        #expect(store.state.verification == nil)
    }

    @Test
    func maintenanceRunsThenReloadsTheVolumesAndForgetsTheVerification() async {
        var state = loadedState()
        state.verification = [TrashVerification(zoneID: "z1", violations: [.init(invariant: "I1", detail: "content missing")])]
        let fresh = TrashZone(id: "z9", name: "fresh")
        let store = store(state: state, zones: { [fresh] })

        await store.send(.maintenanceTapped) { $0.isMaintaining = true }
        await store.receive(\.maintenanceResponse.success) {
            $0.isMaintaining = false
            $0.verification = nil
            $0.zonesPhase = .loading
        }
        await store.receive(\.zonesResponse.success) {
            $0.zonesPhase = .loaded
            $0.zones = [fresh]
        }

        #expect(maintenanceCalls.value == 1)
    }

    @Test
    func aFailedMaintenanceShowsTheErrorAndKeepsTheVolumes() async {
        var state = loadedState()
        state.zones = [TrashZone(id: "z1", name: "files")]
        let store = store(state: state, maintain: { throw FilesClientError.server(statusCode: 500) })

        await store.send(.maintenanceTapped) { $0.isMaintaining = true }
        await store.receive(\.maintenanceResponse.failure) {
            $0.isMaintaining = false
            $0.zonesError = L10n.Error.server(500)
        }

        #expect(store.state.zones.map(\.id) == ["z1"])
        #expect(zoneFetches.value == 0)
    }

    @Test
    func verifyAndMaintenanceDoNotStartTwice() async {
        var state = loadedState()
        state.isVerifying = true
        state.isMaintaining = true
        let store = store(state: state)

        await store.send(.verifyTapped)
        await store.send(.maintenanceTapped)

        #expect(verifyCalls.value == 0)
        #expect(maintenanceCalls.value == 0)
    }

    // MARK: Journal wording

    struct JournalCase: Sendable {
        let kind: String
        let text: String
    }

    @Test(arguments: [
        JournalCase(kind: "evicted", text: L10n.TrashSettings.eventEvicted("a.txt")),
        JournalCase(kind: "adopted", text: L10n.TrashSettings.eventAdopted("a.txt")),
        JournalCase(kind: "lost", text: L10n.TrashSettings.eventLost("a.txt")),
        JournalCase(kind: "failed", text: L10n.TrashSettings.eventFailed("a.txt")),
        JournalCase(kind: "breaker", text: L10n.TrashSettings.eventBreaker),
        JournalCase(kind: "forgotten", text: L10n.TrashSettings.eventForgotten("a.txt")),
        JournalCase(kind: "version-evicted", text: L10n.TrashSettings.eventVersionEvicted("a.txt")),
        JournalCase(kind: "version-failed", text: L10n.TrashSettings.eventVersionFailed),
        JournalCase(kind: "version-lost", text: L10n.TrashSettings.eventVersionLost),
        JournalCase(kind: "version-too-large", text: L10n.TrashSettings.eventVersionTooLarge("a.txt")),
        JournalCase(kind: "versions-breaker", text: L10n.TrashSettings.eventVersionsBreaker),
    ])
    func eachJournalKindHasItsOwnWording(_ testCase: JournalCase) {
        #expect(TrashEventLabel.text(for: TrashEvent(id: "1", kind: testCase.kind, itemName: "a.txt")) == testCase.text)
    }

    @Test
    func anUnknownJournalKindShowsItsOwnName() {
        #expect(TrashEventLabel.text(for: TrashEvent(id: "1", kind: "something-new")) == "something-new")
    }
}
