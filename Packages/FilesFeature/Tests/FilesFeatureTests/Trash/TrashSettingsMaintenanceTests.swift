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
struct TrashSettingsMaintenanceTests: TrashSettingsTestSupport {
    let settingsGate = AsyncGate()
    let zonesGate = AsyncGate()
    let settingsFetches = LockIsolated(0)
    let zoneFetches = LockIsolated(0)
    let patches = LockIsolated<[SystemSettingsPatch]>([])
    let verifyCalls = LockIsolated(0)
    let maintenanceCalls = LockIsolated(0)

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
        state.verification = [TrashVerification(
            zoneID: "z1",
            violations: [.init(invariant: "I1", detail: "content missing")]
        )]
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
        #expect(TrashEventLabel
            .text(for: TrashEvent(id: "1", kind: testCase.kind, itemName: TestFile.aText)) == testCase.text)
    }

    @Test
    func anUnknownJournalKindShowsItsOwnName() {
        #expect(TrashEventLabel.text(for: TrashEvent(id: "1", kind: "something-new")) == "something-new")
    }
}
