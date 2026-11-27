@testable import AppFeature
import AuthClient
import AuthFeature
import ComposableArchitecture
import CoreModels
import FilesClient
import FilesFeature
import Foundation
import Testing
import TestUtils

private typealias LockStore = TestStore<AppFeature.State, AppFeature.Action>

private enum LockFixture {
    static let leftAt = MockDate.date
    static let longAway = MockDate.date.addingTimeInterval(120)
    static let shortAway = MockDate.date.addingTimeInterval(10)
}

extension AppSuites {
    @MainActor
    @Suite("Require sign in", .isolatedDependencies)
    struct AppLockTests {
        private let recorder = WipeRecorder()
        private let ended = LockIsolated<[String]>([])
        private let accountList = AsyncGate()

        private var policyA: SessionCredentials {
            var credentials = AppFixtures.credentials(AppFixtures.serverA, TestUser.alice)
            credentials.requireSignIn = RequireSignIn(lockAfter: .oneMinute)
            return credentials
        }

        private var lockedSummaryA: AccountSummary {
            AccountSummary(policyA.locked, isActive: true)
        }

        private func makeStore(
            _ state: AppFeature.State,
            sessions: [SessionCredentials]? = nil,
            configure: (inout DependencyValues) -> Void = { _ in }
        ) -> LockStore {
            let listed = sessions ?? [policyA.locked]
            return TestStore(initialState: state) {
                AppFeature()
            } withDependencies: { [ended, policyA, accountList] in
                recorder.install(into: &$0)
                recorder.installPendingLog(into: &$0)
                $0.date = .constant(LockFixture.leftAt)
                $0.authClient.lockSessions = { shouldLock in shouldLock(policyA) ? [policyA] : [] }
                $0.authClient.endSession = { credentials in ended.withValue { $0.append(credentials.accountID) } }
                $0.authClient.listSessions = {
                    try? await accountList.wait()
                    return listed
                }
                $0.authClient.activeAccountID = { AppFixtures.accountA }
                configure(&$0)
            }
        }

        private func signedInWithPolicy() -> AppFeature.State {
            let state = AppFeature.State(destination: .authenticated(AuthenticatedFeature.State(
                serverURL: AppFixtures.serverA,
                user: AppFixtures.userA
            )))
            state.$accounts.withLock { $0 = [AccountSummary(policyA, isActive: true)] }
            return state
        }

        private func lockedState() -> AppFeature.State {
            let state = AppFeature.State(destination: .locked(LockFeature.State(account: lockedSummaryA)))
            state.$accounts.withLock { [lockedSummaryA] in $0 = [lockedSummaryA] }
            return state
        }

        @Test("A cold launch locks an account that requires sign in and ends its server session")
        func coldLaunchLocks() async {
            let store = makeStore(AppFeature.State()) { [policyA] in
                $0.authClient.restoreSession = { policyA.locked }
            }

            await store.send(.onAppear)
            await store.receive(\.sessionRestoreResponse) {
                $0.destination = .locked(LockFeature.State(account: lockedSummaryA))
            }
            accountList.open()
            await store.receive(\.accountsRefreshed) {
                $0.$accounts.withLock { [lockedSummaryA] in $0 = [lockedSummaryA] }
            }
            await store.finish()

            #expect(ended.value == [AppFixtures.accountA])
            #expect(recorder.events.value.isEmpty, "the account keeps its offline files")
        }

        @Test("Coming back after the lock time locks the account, stops its offline work and ends its session")
        func returnAfterTimeoutLocks() async {
            let store = makeStore(signedInWithPolicy())

            await store.send(.appLeft) {
                $0.leftAt = LockFixture.leftAt
            }
            store.dependencies.date = .constant(LockFixture.longAway)
            await store.send(.appReturned) {
                $0.leftAt = nil
            }
            await store.receive(\.destination.authenticated.mainTab.offline.accountDeactivated, AppFixtures.accountA)
            await store.receive(\.destination.authenticated.mainTab.downloadQueue.accountLeft)
            await store.receive(\.lockShown) {
                $0.destination = .locked(LockFeature.State(account: lockedSummaryA))
            }
            await store.receive(\.accountsLocked)
            accountList.open()
            await store.receive(\.accountsRefreshed) {
                $0.$accounts.withLock { [lockedSummaryA] in $0 = [lockedSummaryA] }
            }
            await store.finish()

            #expect(ended.value == [AppFixtures.accountA])
            #expect(recorder.events.value == [.thumbnailMemoryCleared])
        }

        @Test("Switching to a locked account stops the leaving account's offline work and shows the lock")
        func switchToLockedAccount() async {
            let lockedB = {
                var credentials = AppFixtures.credentials(AppFixtures.serverB, TestUser.bob)
                credentials.requireSignIn = RequireSignIn()
                return credentials.locked
            }()
            let summaryB = AccountSummary(lockedB, isActive: true)
            let store = makeStore(signedInWithPolicy(), sessions: [policyA, lockedB]) {
                $0.authClient.activeAccountID = { AppFixtures.accountB }
            }

            await store.send(.activateAccount(lockedB)) {
                $0.returnAccountID = AppFixtures.accountA
            }
            await store.receive(\.destination.authenticated.mainTab.offline.accountDeactivated, AppFixtures.accountA)
            await store.receive(\.destination.authenticated.mainTab.downloadQueue.accountLeft)
            await store.receive(\.lockShown) {
                $0.destination = .locked(LockFeature.State(account: summaryB))
            }
            accountList.open()
            await store.receive(\.accountsRefreshed) { [policyA] in
                $0.$accounts.withLock { $0 = [AccountSummary(policyA, isActive: false), summaryB] }
            }
            await store.finish()

            #expect(ended.value.isEmpty, "switching never ends a session")
        }

        @Test("Leaving an account set to lock immediately locks it on the way out and ends its session")
        func immediatelyLocksOnLeave() async {
            let immediate = {
                var credentials = policyA
                credentials.requireSignIn = RequireSignIn(lockAfter: .immediately)
                return credentials
            }()
            let state = AppFeature.State(destination: .authenticated(AuthenticatedFeature.State(
                serverURL: AppFixtures.serverA,
                user: AppFixtures.userA
            )))
            state.$accounts.withLock { $0 = [AccountSummary(immediate, isActive: true)] }
            let locked = AccountSummary(immediate.locked, isActive: true)
            let store = makeStore(state, sessions: [immediate.locked]) {
                $0.authClient.lockSessions = { shouldLock in shouldLock(immediate) ? [immediate] : [] }
            }

            await store.send(.appLeft) {
                $0.leftAt = LockFixture.leftAt
            }
            await store.receive(\.destination.authenticated.mainTab.offline.accountDeactivated, AppFixtures.accountA)
            await store.receive(\.destination.authenticated.mainTab.downloadQueue.accountLeft)
            await store.receive(\.lockShown) {
                $0.destination = .locked(LockFeature.State(account: locked))
            }
            await store.receive(\.accountsLocked)
            accountList.open()
            await store.receive(\.accountsRefreshed) {
                $0.$accounts.withLock { $0 = [locked] }
            }
            await store.send(.appReturned) {
                $0.leftAt = nil
            }
            await store.finish()

            #expect(ended.value == [AppFixtures.accountA])
        }

        @Test("A launch whose lock could not be saved still shows the lock for an account that requires sign in")
        func launchFailsClosed() async {
            let store = makeStore(AppFeature.State()) { [policyA] in
                $0.authClient.lockSessions = { _ in throw AuthClientError.network(TestSession.cookieValue) }
                $0.authClient.restoreSession = { policyA }
            }

            await store.send(.onAppear)
            await store.receive(\.sessionRestoreResponse) {
                $0.destination = .locked(LockFeature.State(account: lockedSummaryA))
            }
            accountList.open()
            await store.receive(\.accountsRefreshed) {
                $0.$accounts.withLock { [lockedSummaryA] in $0 = [lockedSummaryA] }
            }
            await store.finish()
        }

        @Test("Changing require sign in in Settings stores it on that account, then lists the accounts again")
        func settingsChangeIsStored() async {
            let saved = LockIsolated<[RequireSignIn?]>([])
            let store = makeStore(signedInWithPolicy(), sessions: [policyA]) {
                $0.authClient.setRequireSignIn = { id, policy in
                    #expect(id == AppFixtures.accountA)
                    saved.withValue { $0.append(policy) }
                }
            }
            let change = AppFeature.Action.destination(.authenticated(.mainTab(.delegate(
                .requireSignInChanged(accountID: AppFixtures.accountA, nil)
            ))))

            await store.send(change)
            accountList.open()
            await store.receive(\.accountsRefreshed)
            await store.finish()

            #expect(saved.value == [nil])
        }

        @Test("Coming back before the lock time keeps the app open")
        func shortAbsenceKeepsOpen() async {
            let store = makeStore(signedInWithPolicy())

            await store.send(.appLeft) {
                $0.leftAt = LockFixture.leftAt
            }
            store.dependencies.date = .constant(LockFixture.shortAway)
            await store.send(.appReturned) {
                $0.leftAt = nil
            }

            #expect(ended.value.isEmpty)
        }

        @Test("Locking with offline files off wipes that account's caches and offline files")
        func lockWithoutOfflineFilesWipes() async {
            let policy = {
                var credentials = policyA
                credentials.requireSignIn?.shouldKeepOfflineFiles = false
                return credentials
            }()
            let store = makeStore(AppFeature.State(), sessions: [policy.locked]) {
                $0.authClient.lockSessions = { _ in [policy] }
                $0.authClient.restoreSession = { policy.locked }
            }
            let locked = AccountSummary(policy.locked, isActive: true)

            await store.send(.onAppear)
            await store.receive(\.sessionRestoreResponse) {
                $0.destination = .locked(LockFeature.State(account: locked))
            }
            accountList.open()
            await store.receive(\.accountsRefreshed) {
                $0.$accounts.withLock { $0 = [locked] }
            }
            await store.finish()

            #expect(
                recorder.events.value == [.pendingAdded(AppFixtures.accountA)]
                    + WipeRecorder.accountWipe(AppFixtures.accountA)
                    + [.pendingRemoved(AppFixtures.accountA)]
            )
        }

        @Test("Signing in again as the locked account opens it without any wipe")
        func unlockSameAccountKeepsData() async {
            let store = makeStore(lockedState(), sessions: [policyA]) { [policyA] in
                $0.authClient.listSessionsOrThrow = { [policyA] }
            }

            await store.send(.destination(.locked(.delegate(.signedIn(AppFixtures.userA, AppFixtures.serverA))))) {
                $0.$downloadScope.withLock { $0 = AppFixtures.downloadScopeA }
                $0.destination = .authenticated(AuthenticatedFeature.State(
                    serverURL: AppFixtures.serverA,
                    user: AppFixtures.userA
                ))
            }
            accountList.open()
            await store.receive(\.accountsRefreshed) { [policyA] in
                $0.$accounts.withLock { $0 = [AccountSummary(policyA, isActive: true)] }
            }
            await store.finish()

            #expect(recorder.events.value == [.pendingRemoved(AppFixtures.accountA)])
        }

        @Test("Signing in as another account at the lock is refused and the locked account stays active")
        func otherAccountRefused() async {
            let switched = LockIsolated<[String]>([])
            let store = makeStore(lockedState()) { [policyA] in
                $0.authClient.switchAccount = { id in
                    switched.withValue { $0.append(id) }
                    return policyA.locked
                }
            }

            await store.send(.destination(.locked(.delegate(.signedIn(AppFixtures.userB, AppFixtures.serverB)))))
            await store.receive(\.destination.locked.otherAccountRefused) {
                $0.destination.modify(\.locked) { $0.problem = .otherAccount }
            }
            accountList.open()
            await store.receive(\.accountsRefreshed)
            await store.finish()

            #expect(recorder.events.value == [.accountRemoved(AppFixtures.accountB)])
            #expect(switched.value == [AppFixtures.accountA])
        }

        @Test("Signing the last locked account out wipes it and returns to the login screen")
        func signOutFromLock() async {
            let store = makeStore(lockedState(), sessions: [])

            await store.send(.destination(.locked(.delegate(.signOutRequested))))
            await store.receive(\.lockedAccountSignedOut) {
                $0.destination = .unauthenticated(.init())
            }
            accountList.open()
            await store.receive(\.accountsRefreshed) {
                $0.$accounts.withLock { $0 = [] }
            }
            await store.finish()

            #expect(
                recorder.events.value == [.pendingAdded(AppFixtures.accountA), .accountRemoved(AppFixtures.accountA)]
                    + WipeRecorder.accountWipe(AppFixtures.accountA)
                    + WipeRecorder.fullTeardown
                    + WipeRecorder.lastSignOutCredentialWipe
            )
        }

        @Test("A late 401 while locked never tears anything down")
        func expiryWhileLockedIsIgnored() async {
            let store = makeStore(lockedState())

            store.state.$sessionDidExpire.withLock { $0 = true }
            await store.send(.sessionExpiryDetected) {
                $0.$sessionDidExpire.withLock { $0 = false }
            }

            #expect(recorder.events.value.isEmpty)
        }

        @Test("Picking another locked account on the lock switches to it and shows its own lock")
        func lockPicksLockedAccount() async {
            let lockedB = {
                var credentials = AppFixtures.credentials(AppFixtures.serverB, TestUser.bob)
                credentials.requireSignIn = RequireSignIn()
                return credentials.locked
            }()
            let summaryB = AccountSummary(lockedB, isActive: true)
            let switched = LockIsolated<[String]>([])
            let store = makeStore(lockedState(), sessions: [policyA.locked, lockedB]) {
                $0.authClient.activeAccountID = { AppFixtures.accountB }
                $0.authClient.switchAccount = { accountID in
                    switched.withValue { $0.append(accountID) }
                    return lockedB
                }
            }

            await store.send(.destination(.locked(.delegate(.switchAccount(AppFixtures.accountB)))))
            await store.receive(\.activateAccount, lockedB)
            await store.receive(\.lockShown) {
                $0.destination = .locked(LockFeature.State(account: summaryB))
            }
            accountList.open()
            await store.receive(\.accountsRefreshed) { [policyA] in
                $0.$accounts.withLock { $0 = [AccountSummary(policyA.locked, isActive: false), summaryB] }
            }
            await store.finish()

            #expect(switched.value == [AppFixtures.accountB])
            #expect(ended.value.isEmpty, "switching never ends a session")
        }
    }
}
