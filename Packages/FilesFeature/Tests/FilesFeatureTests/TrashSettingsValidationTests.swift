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
struct TrashSettingsValidationTests: TrashSettingsTestSupport {
    let settingsGate = AsyncGate()
    let zonesGate = AsyncGate()
    let settingsFetches = LockIsolated(0)
    let zoneFetches = LockIsolated(0)
    let patches = LockIsolated<[SystemSettingsPatch]>([])
    let verifyCalls = LockIsolated(0)
    let maintenanceCalls = LockIsolated(0)

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
}
