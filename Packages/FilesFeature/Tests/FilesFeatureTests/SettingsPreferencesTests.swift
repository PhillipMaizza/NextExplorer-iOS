import ClientCertificateFeature
import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import NetworkClient
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct SettingsPreferencesTests: SettingsFeatureTestSupport {
    struct ToggleCase: Sendable {
        let action: SettingsFeature.Action
        let key: UserPreferenceKey
        let value: Bool
        let expected: UserPreferences
    }

    @Test(arguments: [
        ToggleCase(
            action: .setShowHiddenFiles(true),
            key: .showHiddenFiles,
            value: true,
            expected: UserPreferences(showHiddenFiles: true, showThumbnails: true)
        ),
        ToggleCase(
            action: .setShowThumbnails(false),
            key: .showThumbnails,
            value: false,
            expected: UserPreferences(showHiddenFiles: false, showThumbnails: false)
        ),
    ])
    func aToggleUpdatesTheSharedPreferencesAndPersistsOptimistically(_ testCase: ToggleCase) async {
        let recorded = LockIsolated<[String]>([])
        let store = TestStore(initialState: makeState()) {
            SettingsFeature()
        } withDependencies: {
            $0.filesClient.updatePreference = { _, key, value in
                recorded.withValue { $0.append("\(key.rawValue)=\(value)") }
            }
        }

        await store.send(testCase.action) { state in
            state.$preferences.withLock { $0 = testCase.expected }
        }
        await store.receive(\.updatePreferenceResponse)

        #expect(recorded.value == ["\(testCase.key.rawValue)=\(testCase.value)"])
    }

    @Test
    func aFailedPersistLeavesTheOptimisticToggleInPlace() async {
        // Fire and forget by design: a failed PATCH does not roll the switch back.
        let store = TestStore(initialState: makeState()) {
            SettingsFeature()
        } withDependencies: {
            $0.filesClient.updatePreference = { _, _, _ in throw FilesClientError.network(TestFailure.offline) }
        }

        await store.send(.setShowHiddenFiles(true)) { state in
            state.$preferences.withLock { $0 = UserPreferences(showHiddenFiles: true, showThumbnails: true) }
        }
        await store.receive(\.updatePreferenceResponse)

        #expect(store.state.preferences.showHiddenFiles)
    }

    @Test
    func aSecondToggleOfTheSameSwitchReplacesTheSaveStillInFlight() async throws {
        let firstStarted = AsyncGate()
        let hold = AsyncGate()
        let calls = LockIsolated<[Bool]>([])
        let store = TestStore(initialState: makeState()) {
            SettingsFeature()
        } withDependencies: {
            $0.filesClient.updatePreference = { _, _, value in
                let isFirst = calls.withValue { calls -> Bool in
                    calls.append(value)
                    return calls.count == 1
                }
                if isFirst {
                    firstStarted.open()
                    try await hold.wait()
                }
            }
        }

        await store.send(.setShowHiddenFiles(true)) { state in
            state.$preferences.withLock { $0 = UserPreferences(showHiddenFiles: true, showThumbnails: true) }
        }
        try await firstStarted.wait()
        await store.send(.setShowHiddenFiles(false)) { state in
            state.$preferences.withLock { $0 = UserPreferences(showHiddenFiles: false, showThumbnails: true) }
        }
        await store.receive(\.updatePreferenceResponse)
        await store.finish()

        #expect(calls.value == [true, false])
    }

    @Test
    func theSignOutButtonAsksFirstAndCancelWithdrawsTheQuestion() async {
        let store = makeStore()

        await store.send(.signOutButtonTapped) { $0.isConfirmingSignOut = true }
        await store.send(.cancelSignOutTapped) { $0.isConfirmingSignOut = false }
    }

    @Test
    func confirmSignOutTappedKeepsTheSheetUpAndDelegatesTheActualSignOut() async {
        var state = makeState()
        state.isConfirmingSignOut = true
        let store = makeStore(state: state)

        // The sheet stays presented so its confirm button can show the spinner the parent drives
        // through `isSigningOut`; the whole scope is torn down once sign out completes.
        await store.send(.confirmSignOutTapped)
        await store.receive(\.delegate, .signOutButtonTapped)

        #expect(store.state.isConfirmingSignOut)
    }
}
