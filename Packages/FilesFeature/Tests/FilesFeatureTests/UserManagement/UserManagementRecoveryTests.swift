import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

@MainActor
struct UserManagementRecoveryTests: UserManagementTestSupport {
    let calls = LockIsolated<[UserManagementCall]>([])
    let listCalls = LockIsolated(0)
    let featureCalls = LockIsolated(0)
    let volumeLoads = LockIsolated<[String]>([])

    private var locked: User {
        makeUser(id: "2", lockedUntil: MockDate.date, twoFactor: true)
    }

    @Test
    func releasingALockRunsAtOnceAndClearsItFromTheUser() async {
        let store = makeStore(loadedState([locked], detail: "2"), resetSecurity: {})

        await store.send(.securityResetTapped(.lock)) { $0.securityResetToConfirm = .lock }
        #expect(!store.state.isConfirmingSecurityReset)
        await store.receive(\.securityResetConfirmed) {
            $0.securityResetToConfirm = nil
            $0.isResettingSecurity = true
        }
        await store.receive(\.securityResetResponse) {
            $0.isResettingSecurity = false
            $0.users[id: "2"] = locked.afterReset(.lock)
            $0.toast = L10n.UserManagement.toastUnlocked
        }
        #expect(calls.value == [.resetSecurity(userID: "2", reset: .lock)])
        #expect(store.state.users[id: "2"]?.isTwoFactorEnabled == true)
    }

    @Test
    func aTwoFactorResetAsksFirstThenClearsTheSecondFactor() async {
        let store = makeStore(loadedState([locked], detail: "2"), resetSecurity: {})

        await store.send(.securityResetTapped(.twoFactor)) { $0.securityResetToConfirm = .twoFactor }
        #expect(store.state.isConfirmingSecurityReset)
        #expect(calls.value.isEmpty)
        await store.send(.securityResetConfirmed) {
            $0.securityResetToConfirm = nil
            $0.isResettingSecurity = true
        }
        await store.receive(\.securityResetResponse) {
            $0.isResettingSecurity = false
            $0.users[id: "2"] = locked.afterReset(.twoFactor)
            $0.toast = L10n.UserManagement.toastTwoFactorReset
        }
        #expect(calls.value == [.resetSecurity(userID: "2", reset: .twoFactor)])
        #expect(store.state.users[id: "2"]?.isLocked == true)
    }

    @Test
    func removingPasskeysKeepsTheUserAsItWasAndToasts() async {
        let store = makeStore(loadedState([locked], detail: "2"), resetSecurity: {})

        await store.send(.securityResetTapped(.passkeys)) { $0.securityResetToConfirm = .passkeys }
        await store.send(.securityResetConfirmed) {
            $0.securityResetToConfirm = nil
            $0.isResettingSecurity = true
        }
        await store.receive(\.securityResetResponse) {
            $0.isResettingSecurity = false
            $0.toast = L10n.UserManagement.toastPasskeysRemoved
        }
        #expect(store.state.users[id: "2"] == locked)
    }

    @Test
    func cancellingTheConfirmationSendsNothing() async {
        let store = makeStore(loadedState([locked], detail: "2"), resetSecurity: {})

        await store.send(.securityResetTapped(.twoFactor)) { $0.securityResetToConfirm = .twoFactor }
        await store.send(.securityResetCancelled) { $0.securityResetToConfirm = nil }
        await store.send(.securityResetConfirmed)
        #expect(calls.value.isEmpty)
    }

    @Test
    func aFailureShowsTheServerMessageAndKeepsTheUserUnchanged() async {
        let store = makeStore(loadedState([locked], detail: "2"), resetSecurity: {
            throw FilesClientError.serverMessage(statusCode: 404, message: "User not found")
        })

        await store.send(.securityResetTapped(.twoFactor)) { $0.securityResetToConfirm = .twoFactor }
        await store.send(.securityResetConfirmed) {
            $0.securityResetToConfirm = nil
            $0.isResettingSecurity = true
        }
        await store.receive(\.securityResetResponse) {
            $0.isResettingSecurity = false
            $0.detailErrorMessage = "User not found"
        }
        #expect(store.state.users[id: "2"] == locked)
    }

    @Test
    func closingTheDetailDropsAPendingConfirmation() async {
        var state = loadedState([locked], detail: "2")
        state.securityResetToConfirm = .passkeys
        let store = makeStore(state)

        await store.send(.detailDismissed) {
            $0.detailUserID = nil
            $0.securityResetToConfirm = nil
        }
    }

    @Test
    func theRecoveryRowsOfferAnUnlockAndTwoFactorOnlyWhileTheyApply() {
        #expect(UserRecoveryRow.rows(for: locked).map(\.reset) == [.lock, .twoFactor, .passkeys])
        #expect(UserRecoveryRow.rows(for: makeUser(id: "3")).map(\.reset) == [.passkeys])
    }
}
