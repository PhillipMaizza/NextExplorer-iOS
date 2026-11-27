@testable import AppFeature
import AuthClient
import ComposableArchitecture
import CoreModels
import Foundation
import Localization
import Testing
import TestUtils

extension AppSuites {
    @MainActor
    @Suite("Account fallback", .isolatedDependencies)
    struct AccountFallbackTests {
        private let credentialsA = AppFixtures.credentials(AppFixtures.serverA, TestUser.alice)
        private let credentialsB = AppFixtures.credentials(AppFixtures.serverB, TestUser.bob)
        private let recorder = WipeRecorder()

        private func makeStore(
            _ state: AppFeature.State,
            configure: (inout DependencyValues) -> Void = { _ in }
        ) -> TestStore<AppFeature.State, AppFeature.Action> {
            TestStore(initialState: state) {
                AppFeature()
            } withDependencies: {
                recorder.install(into: &$0)
                configure(&$0)
            }
        }

        @Test("Confirming the signed in user keeps what the account already loaded")
        func validationKeepsTheLoadedTree() async {
            var state = AppFeature.State(destination: AppFixtures.confirmed(AppFixtures.serverA, AppFixtures.userA))
            let placeholder = User(id: "", username: AppFixtures.userA.username, email: nil)
            var loaded = AuthenticatedFeature.State(serverURL: AppFixtures.serverA, user: placeholder)
            loaded.mainTab.browse.root.isTrashAvailable = true
            state.destination = .authenticated(loaded)
            let store = makeStore(state) {
                $0.authClient.setDisplayName = { _, _ in }
                $0.authClient.listSessions = { [] }
            }

            var confirmed = loaded
            confirmed.user = AppFixtures.userA
            confirmed.mainTab.settings.user = AppFixtures.userA

            await store.send(.sessionValidationResponse(.success(AppFixtures.userA), credentialsA)) {
                $0.$downloadScope.withLock { $0 = AppFixtures.downloadScopeA }
                $0.destination = .authenticated(confirmed)
            }
            await store.receive(\.accountsRefreshed)
            await store.finish()
        }

        @Test("An account dropped for an ended session is named once the next account is up")
        func droppedAccountIsAnnouncedOnTheNextAccount() async {
            let state = AppFeature.State(destination: AppFixtures.confirmed(AppFixtures.serverA, AppFixtures.userA))
            state.$accounts.withLock {
                $0 = [AccountSummary(credentialsA, isActive: true), AccountSummary(credentialsB, isActive: false)]
            }
            let credentialsB = credentialsB
            let confirmation = AsyncGate()
            let accountList = AsyncGate()
            let store = makeStore(state) {
                recorder.installPendingLog(into: &$0)
                $0.authClient.listSessions = {
                    try? await accountList.wait()
                    return []
                }
                $0.authClient.clearActiveSession = { credentialsB }
                $0.authClient.me = { [userB = AppFixtures.userB] _ in
                    try await confirmation.wait()
                    return userB
                }
            }

            let droppedName = AccountSummary(credentialsA, isActive: true).displayName
            var announced = AuthenticatedFeature.State(serverURL: AppFixtures.serverB, user: AppFixtures.userB)
            announced.mainTab.signedOutNotice = L10n.Error.accountsSignedOut(droppedName)

            await store.send(.sessionValidationResponse(.failure(.sessionExpired), credentialsA))
            await store.receive(\.activeAccountTornDown) {
                $0.expiredAccountNames = [droppedName]
            }
            await store.receive(\.activateAccount) {
                $0.returnAccountID = AppFixtures.accountA
                $0.destination = AppFixtures.optimistic(AppFixtures.serverB, username: TestUser.bob)
            }
            await store.receive(\.destination.authenticated.mainTab.offline.accountDeactivated, AppFixtures.accountA)
            await store.receive(\.destination.authenticated.mainTab.downloadQueue.accountLeft)
            accountList.open()
            await store.receive(\.accountsRefreshed) {
                $0.$accounts.withLock { $0 = [] }
            }
            confirmation.open()
            await store.receive(\.sessionValidationResponse) {
                $0.returnAccountID = nil
                $0.$downloadScope.withLock { $0 = AppFixtures.downloadScopeB }
                $0.expiredAccountNames = []
                $0.destination = AppFixtures.confirmed(AppFixtures.serverB, AppFixtures.userB)
            }
            await store.receive(\.destination.authenticated.mainTab.accountsSignedOut) {
                $0.destination = .authenticated(announced)
            }
            await store.receive(\.accountsRefreshed)
            await store.finish()
        }

        @Test("A switch to an account whose session ended goes back to the account it came from")
        func failedSwitchReturnsToThePreviousAccount() async {
            let credentialsC = AppFixtures.credentials(AppFixtures.serverA, TestUser.jane)
            var state = AppFeature.State(destination: AppFixtures.confirmed(AppFixtures.serverA, AppFixtures.userA))
            state.returnAccountID = credentialsB.accountID
            state.$accounts.withLock {
                $0 = [
                    AccountSummary(credentialsC, isActive: false),
                    AccountSummary(credentialsA, isActive: true),
                    AccountSummary(credentialsB, isActive: false),
                ]
            }
            let credentialsB = credentialsB
            let confirmation = AsyncGate()
            let accountList = AsyncGate()
            let store = makeStore(state) {
                recorder.installPendingLog(into: &$0)
                $0.authClient.listSessions = {
                    try? await accountList.wait()
                    return []
                }
                $0.authClient.clearActiveSession = { credentialsC }
                $0.authClient.switchAccount = { $0 == credentialsB.accountID ? credentialsB : nil }
                $0.authClient.me = { [userB = AppFixtures.userB] _ in
                    try await confirmation.wait()
                    return userB
                }
            }
            let droppedName = AccountSummary(credentialsA, isActive: true).displayName
            var announced = AuthenticatedFeature.State(serverURL: AppFixtures.serverB, user: AppFixtures.userB)
            announced.mainTab.signedOutNotice = L10n.Error.accountsSignedOut(droppedName)

            await store.send(.sessionValidationResponse(.failure(.sessionExpired), credentialsA))
            await store.receive(\.activeAccountTornDown) {
                $0.expiredAccountNames = [droppedName]
            }
            await store.receive(\.activateAccount) {
                $0.destination = AppFixtures.optimistic(AppFixtures.serverB, username: TestUser.bob)
            }
            await store.receive(\.destination.authenticated.mainTab.offline.accountDeactivated, AppFixtures.accountA)
            await store.receive(\.destination.authenticated.mainTab.downloadQueue.accountLeft)
            accountList.open()
            await store.receive(\.accountsRefreshed) {
                $0.$accounts.withLock { $0 = [] }
            }
            confirmation.open()
            await store.receive(\.sessionValidationResponse) {
                $0.returnAccountID = nil
                $0.$downloadScope.withLock { $0 = AppFixtures.downloadScopeB }
                $0.expiredAccountNames = []
                $0.destination = AppFixtures.confirmed(AppFixtures.serverB, AppFixtures.userB)
            }
            await store.receive(\.destination.authenticated.mainTab.accountsSignedOut) {
                $0.destination = .authenticated(announced)
            }
            await store.receive(\.accountsRefreshed)
            await store.finish()
        }
    }
}
