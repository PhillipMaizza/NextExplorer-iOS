@testable import AppFeature
import AuthClient
import AuthFeature
import ComposableArchitecture
import CoreModels
import FilesClient
import FilesFeature
import Foundation
import NetworkClient
import Testing
import TestUtils

extension AppSuites {
    /// Account boundaries: a stale signal about an account that was already left must never act on the
    /// account that is active now, and the record that lets a killed wipe finish is written before the
    /// session goes.
    @MainActor
    @Suite("Account boundary", .isolatedDependencies)
    struct AccountBoundaryTests {
        private typealias Store = TestStore<AppFeature.State, AppFeature.Action>
        private typealias AuthenticatedStore = TestStore<AuthenticatedFeature.State, AuthenticatedFeature.Action>

        private enum Fixture {
            static let path = "Docs"
            static let keychainFailure = "keychain unreadable"
        }

        private let credentialsA = AppFixtures.credentials(AppFixtures.serverA, "alice")
        private let credentialsB = AppFixtures.credentials(AppFixtures.serverB, "bob")
        private let recorder = WipeRecorder()

        init() {
            AppSuites.resetSharedState()
        }

        private func listing() -> BrowseResult {
            BrowseResult(
                items: [],
                access: FileAccess(canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true),
                path: Fixture.path
            )
        }

        private func activeState(_ serverURL: URL, _ user: User) -> AppFeature.State {
            AppFeature.State(destination: .authenticated(AuthenticatedFeature.State(serverURL: serverURL, user: user)))
        }

        private func makeStore(
            _ state: AppFeature.State,
            configure: (inout DependencyValues) -> Void = { _ in }
        ) -> Store {
            TestStore(initialState: state) {
                AppFeature()
            } withDependencies: {
                recorder.install(into: &$0)
                configure(&$0)
            }
        }

        private func makeAuthenticatedStore(
            _ serverURL: URL,
            _ user: User,
            clock: TestClock<Duration>,
            configure: (inout DependencyValues) -> Void = { _ in }
        ) -> AuthenticatedStore {
            TestStore(initialState: AuthenticatedFeature.State(serverURL: serverURL, user: user)) {
                AuthenticatedFeature()
            } withDependencies: {
                recorder.install(into: &$0)
                recorder.installPendingLog(into: &$0)
                $0.continuousClock = clock
                configure(&$0)
            }
        }

        private func optimistic(_ serverURL: URL, username: String) -> AppFeature.Destination.State {
            .authenticated(AuthenticatedFeature.State(serverURL: serverURL, user: User(id: "", username: username, email: nil)))
        }

        private func confirmed(_ serverURL: URL, _ user: User) -> AppFeature.Destination.State {
            .authenticated(AuthenticatedFeature.State(serverURL: serverURL, user: user))
        }

        // MARK: Stale signals

        @Test("A 401 burst from an account that was already left does not tear down the active account")
        func staleExpiryAfterASwitchLeavesTheNewAccountAlone() async {
            let pending = PendingAccountWipes.inMemory()
            let store = makeStore(activeState(AppFixtures.serverB, AppFixtures.userB)) {
                $0.pendingAccountWipes = pending
                $0.authClient.me = { _ in AppFixtures.userB }
                $0.authClient.clearActiveSession = {
                    Issue.record("the active account must not be signed out for another account's 401")
                    return nil
                }
            }
            store.state.$sessionDidExpire.withLock { $0 = true }

            await store.send(.sessionExpiryDetected) {
                $0.$sessionDidExpire.withLock { $0 = false }
            }
            await store.finish()

            #expect(pending.accounts().isEmpty)
            #expect(recorder.events.value.isEmpty, "nothing is wiped for a 401 the server does not confirm")
            #expect(store.state.currentAccountID == AppFixtures.accountB)
        }

        @Test("A network error while confirming an expiry leaves the session in place")
        func unconfirmedExpiryIsIgnored() async {
            let store = makeStore(activeState(AppFixtures.serverA, AppFixtures.userA)) {
                $0.authClient.me = { _ in throw AuthClientError.network("offline") }
                $0.authClient.clearActiveSession = {
                    Issue.record("an unreachable server does not prove the session is gone")
                    return nil
                }
            }
            store.state.$sessionDidExpire.withLock { $0 = true }

            await store.send(.sessionExpiryDetected) {
                $0.$sessionDidExpire.withLock { $0 = false }
            }
            await store.finish()

            #expect(recorder.events.value.isEmpty)
        }

        @Test("An expiry confirmed for an account that is no longer active is dropped")
        func staleConfirmationIsDropped() async {
            let store = makeStore(activeState(AppFixtures.serverB, AppFixtures.userB)) {
                $0.authClient.clearActiveSession = {
                    Issue.record("the active account must not be signed out")
                    return nil
                }
            }

            await store.send(.sessionExpiryConfirmed(accountID: AppFixtures.accountA))
            await store.finish()

            #expect(recorder.events.value.isEmpty)
        }

        @Test("A session check answered for an account that was left changes nothing, success or failure")
        func staleValidationResponsesAreDropped() async {
            let store = makeStore(activeState(AppFixtures.serverB, AppFixtures.userB)) {
                $0.authClient.clearActiveSession = {
                    Issue.record("a stale failure must not sign the active account out")
                    return nil
                }
            }

            await store.send(.sessionValidationResponse(.failure(.sessionExpired), credentialsA))
            await store.send(.sessionValidationResponse(.success(AppFixtures.userA), credentialsA))
            await store.finish()

            #expect(store.state.currentAccountID == AppFixtures.accountB)
            #expect(store.state.downloadScope.isEmpty)
            #expect(recorder.events.value.isEmpty)
        }

        // MARK: Record before the session goes

        @Test("An expired session is listed as pending before its session is cleared, then wiped")
        func expiryRecordsThePendingWipeFirst() async {
            let store = makeStore(activeState(AppFixtures.serverA, AppFixtures.userA)) {
                recorder.installPendingLog(into: &$0)
                $0.authClient.me = { _ in throw AuthClientError.sessionExpired }
            }

            await withMainSerialExecutor {
                await store.send(.sessionExpiryDetected)
                await store.receive(\.sessionExpiryConfirmed)
                await store.receive(\.activeAccountTornDown) {
                    $0.destination = .unauthenticated(.init())
                }
                await store.receive(\.accountsRefreshed)
            }

            #expect(
                recorder.events.value == [.pendingAdded(AppFixtures.accountA), .activeSessionCleared]
                    + WipeRecorder.accountWipe(AppFixtures.accountA) + WipeRecorder.fullTeardown
            )
        }

        @Test("A rejected restored session is listed as pending before its session is cleared, then wiped")
        func rejectedValidationRecordsThePendingWipeFirst() async {
            let store = makeStore(activeState(AppFixtures.serverA, AppFixtures.userA)) {
                recorder.installPendingLog(into: &$0)
            }

            await withMainSerialExecutor {
                await store.send(.sessionValidationResponse(.failure(.sessionExpired), credentialsA))
                await store.receive(\.activeAccountTornDown) {
                    $0.destination = .unauthenticated(.init())
                }
                await store.receive(\.accountsRefreshed)
            }

            #expect(
                recorder.events.value == [.pendingAdded(AppFixtures.accountA), .activeSessionCleared]
                    + WipeRecorder.accountWipe(AppFixtures.accountA) + WipeRecorder.fullTeardown
            )
        }

        @Test("Signing out lists the account as pending before removing its session, then wipes it")
        func signOutRecordsThePendingWipeFirst() async {
            let clock = TestClock()
            let store = makeAuthenticatedStore(AppFixtures.serverA, AppFixtures.userA, clock: clock)

            await store.send(.mainTab(.delegate(.signOutButtonTapped))) {
                $0.mainTab.settings.isSigningOut = true
            }
            await store.receive(\.accountChangeResolved, nil)
            await clock.advance(by: .seconds(0.4))
            await store.receive(\.delegate.activeAccountChanged, nil)

            #expect(
                recorder.events.value == [.pendingAdded(AppFixtures.accountA), .accountRemoved(AppFixtures.accountA)]
                    + WipeRecorder.accountWipe(AppFixtures.accountA)
            )
        }

        @Test("Removing an account lists it as pending before removing its session, then wipes it")
        func removeAccountRecordsThePendingWipeFirst() async {
            let clock = TestClock()
            let store = makeAuthenticatedStore(AppFixtures.serverA, AppFixtures.userA, clock: clock)

            await store.send(.mainTab(.delegate(.removeAccount(AppFixtures.accountB))))
            await store.receive(\.accountChangeResolved, nil)
            await clock.advance(by: .seconds(0.4))
            await store.receive(\.delegate.activeAccountChanged, nil)

            #expect(
                recorder.events.value == [.pendingAdded(AppFixtures.accountB), .accountRemoved(AppFixtures.accountB)]
                    + WipeRecorder.accountWipe(AppFixtures.accountB)
            )
        }

        // MARK: The pending list drains

        @Test("An expiry that falls through to another account finishes its second pass, wipes what a late writer left and drains the list")
        func fallThroughDrainsThePendingList() async {
            let pending = PendingAccountWipes.inMemory()
            let directory = DirectoryCacheStore.inMemory()
            let secondPass = AsyncGate()
            let confirmation = AsyncGate()
            let accountList = AsyncGate()
            let store = makeStore(activeState(AppFixtures.serverA, AppFixtures.userA)) {
                $0.pendingAccountWipes = pending
                $0.directoryCacheStore = directory
                $0.authClient.me = { [userB = AppFixtures.userB] url in
                    if url == AppFixtures.serverA {
                        throw AuthClientError.sessionExpired
                    }
                    try await confirmation.wait()
                    return userB
                }
                $0.authClient.clearActiveSession = { [recorder, credentialsB] in
                    recorder.record(.activeSessionCleared)
                    return credentialsB
                }
                $0.authClient.listSessions = { [credentialsB] in
                    try? await accountList.wait()
                    return [credentialsB]
                }
                $0.authClient.listSessionsOrThrow = { [credentialsB] in
                    try await secondPass.wait()
                    return [credentialsB]
                }
                $0.authClient.activeAccountID = { AppFixtures.accountB }
            }

            await withMainSerialExecutor {
                await store.send(.sessionExpiryDetected)
                await store.receive(\.sessionExpiryConfirmed)
                await store.receive(\.activeAccountTornDown)
                await store.receive(\.activateAccount) {
                    $0.destination = optimistic(AppFixtures.serverB, username: "bob")
                }
                await store.receive(\.destination.authenticated.mainTab.offline.accountDeactivated, AppFixtures.accountA)
                accountList.open()
                await store.receive(\.accountsRefreshed) {
                    $0.$accounts.withLock { $0 = [AppFixtures.summaryB] }
                }

                directory.bound(to: AppFixtures.accountA).write(
                    serverURL: AppFixtures.serverA, path: Fixture.path, result: listing(), etag: nil, fetchedAt: MockDate.date
                )
                secondPass.open()
                confirmation.open()
                await store.receive(\.sessionValidationResponse) {
                    $0.$downloadScope.withLock { $0 = AppFixtures.downloadScopeB }
                    $0.destination = confirmed(AppFixtures.serverB, AppFixtures.userB)
                }
                await store.receive(\.accountsRefreshed)
                await store.finish()
            }

            #expect(pending.accounts().isEmpty, "the second pass never ran for \(pending.accounts())")
            #expect(
                directory.bound(to: AppFixtures.accountA).read(serverURL: AppFixtures.serverA, path: Fixture.path) == nil,
                "an entry written after the first wipe is removed by the second pass"
            )
            let accountWipeWithoutDirectory: [WipeRecorder.Event] = [
                .jsonAccountCleared(AppFixtures.accountA),
                .previewAccountCleared(AppFixtures.accountA),
                .offlineAccountCleared(AppFixtures.accountA),
                .thumbnailMemoryCleared,
            ]
            #expect(
                recorder.events.value == [.activeSessionCleared] + accountWipeWithoutDirectory + accountWipeWithoutDirectory,
                "wiped once on expiry and once more by the second pass"
            )
        }

        @Test("Activating an account unlists a stale pending entry for it, so it is never wiped")
        func activatingAnAccountDropsItsStalePendingEntry() async {
            let pending = PendingAccountWipes.inMemory()
            pending.add(AppFixtures.accountA)
            let directory = DirectoryCacheStore.inMemory()
            directory.bound(to: AppFixtures.accountA).write(
                serverURL: AppFixtures.serverA, path: Fixture.path, result: listing(), etag: nil, fetchedAt: MockDate.date
            )
            let confirmation = AsyncGate()
            let accountList = AsyncGate()
            let store = makeStore(activeState(AppFixtures.serverB, AppFixtures.userB)) {
                $0.pendingAccountWipes = pending
                $0.directoryCacheStore = directory
                $0.authClient.me = { _ in
                    try await confirmation.wait()
                    return AppFixtures.userA
                }
                $0.authClient.listSessions = { [credentialsA] in
                    try? await accountList.wait()
                    return [credentialsA]
                }
                $0.authClient.listSessionsOrThrow = { [] }
                $0.authClient.activeAccountID = { AppFixtures.accountA }
            }

            await withMainSerialExecutor {
                await store.send(.activateAccount(credentialsA)) {
                    $0.destination = optimistic(AppFixtures.serverA, username: "alice")
                }
                await store.receive(\.destination.authenticated.mainTab.offline.accountDeactivated, AppFixtures.accountB)
                accountList.open()
                await store.receive(\.accountsRefreshed) {
                    $0.$accounts.withLock { $0 = [AppFixtures.summaryA] }
                }
                confirmation.open()
                await store.receive(\.sessionValidationResponse) {
                    $0.$downloadScope.withLock { $0 = AppFixtures.downloadScopeA }
                    $0.destination = confirmed(AppFixtures.serverA, AppFixtures.userA)
                }
                await store.receive(\.accountsRefreshed)
                await store.finish()
            }

            #expect(pending.accounts().isEmpty)
            #expect(directory.bound(to: AppFixtures.accountA).read(serverURL: AppFixtures.serverA, path: Fixture.path) != nil)
            #expect(recorder.events.value.isEmpty, "the account was signed back in, so nothing is wiped")
        }

        @Test("Restoring a session at launch unlists a stale pending entry for it, so it is never wiped")
        func restoringAnAccountDropsItsStalePendingEntry() async {
            let pending = PendingAccountWipes.inMemory()
            pending.add(AppFixtures.accountA)
            let directory = DirectoryCacheStore.inMemory()
            directory.bound(to: AppFixtures.accountA).write(
                serverURL: AppFixtures.serverA, path: Fixture.path, result: listing(), etag: nil, fetchedAt: MockDate.date
            )
            let confirmation = AsyncGate()
            let accountList = AsyncGate()
            let store = makeStore(AppFeature.State()) {
                $0.pendingAccountWipes = pending
                $0.directoryCacheStore = directory
                $0.authClient.me = { _ in
                    try await confirmation.wait()
                    return AppFixtures.userA
                }
                $0.authClient.listSessions = { [credentialsA] in
                    try? await accountList.wait()
                    return [credentialsA]
                }
                $0.authClient.listSessionsOrThrow = { [] }
                $0.authClient.activeAccountID = { AppFixtures.accountA }
            }

            await withMainSerialExecutor {
                await store.send(.sessionRestoreResponse(credentialsA)) {
                    $0.destination = optimistic(AppFixtures.serverA, username: "alice")
                }
                accountList.open()
                await store.receive(\.accountsRefreshed) {
                    $0.$accounts.withLock { $0 = [AppFixtures.summaryA] }
                }
                confirmation.open()
                await store.receive(\.sessionValidationResponse) {
                    $0.$downloadScope.withLock { $0 = AppFixtures.downloadScopeA }
                    $0.destination = confirmed(AppFixtures.serverA, AppFixtures.userA)
                }
                await store.receive(\.accountsRefreshed)
                await store.finish()
            }

            #expect(pending.accounts().isEmpty)
            #expect(directory.bound(to: AppFixtures.accountA).read(serverURL: AppFixtures.serverA, path: Fixture.path) != nil)
            #expect(recorder.events.value.isEmpty, "the account has a session again, so nothing is wiped")
        }

        @Test("Signing in again at the login screen unlists a stale pending entry for the account")
        func signingInAgainDropsTheStalePendingEntry() async {
            let pending = PendingAccountWipes.inMemory()
            pending.add(AppFixtures.accountA)
            let store = makeStore(AppFeature.State(destination: .unauthenticated(.init()))) {
                $0.pendingAccountWipes = pending
            }

            await withMainSerialExecutor {
                await store.send(.destination(.unauthenticated(.delegate(.authenticated(AppFixtures.userA, AppFixtures.serverA))))) {
                    $0.$downloadScope.withLock { $0 = AppFixtures.downloadScopeA }
                    $0.didAuthenticateFromLogin = true
                    $0.destination = confirmed(AppFixtures.serverA, AppFixtures.userA)
                }
                await store.receive(\.accountsRefreshed)
                await store.finish()
            }

            #expect(pending.accounts().isEmpty)
        }

        @Test("Adding an account unlists a stale pending entry for it and finishes the other wipes")
        func addingAnAccountDropsItsStalePendingEntry() async {
            let pending = PendingAccountWipes.inMemory()
            pending.add(AppFixtures.accountB)
            let directory = DirectoryCacheStore.inMemory()
            directory.bound(to: AppFixtures.accountB).write(
                serverURL: AppFixtures.serverB, path: Fixture.path, result: listing(), etag: nil, fetchedAt: MockDate.date
            )
            var state = activeState(AppFixtures.serverA, AppFixtures.userA)
            state.pendingAddedAccount = AppFeature.AddedAccount(user: AppFixtures.userB, serverURL: AppFixtures.serverB)
            let accountList = AsyncGate()
            let store = makeStore(state) {
                $0.pendingAccountWipes = pending
                $0.directoryCacheStore = directory
                $0.authClient.listSessions = { [credentialsB] in
                    try? await accountList.wait()
                    return [credentialsB]
                }
                $0.authClient.listSessionsOrThrow = { [] }
                $0.authClient.activeAccountID = { AppFixtures.accountB }
            }

            await withMainSerialExecutor {
                await store.send(.addAccountSheetDismissed) {
                    $0.pendingAddedAccount = nil
                    $0.$downloadScope.withLock { $0 = AppFixtures.downloadScopeB }
                    $0.destination = confirmed(AppFixtures.serverB, AppFixtures.userB)
                }
                await store.receive(\.destination.authenticated.mainTab.offline.accountDeactivated, AppFixtures.accountA)
                accountList.open()
                await store.receive(\.accountsRefreshed) {
                    $0.$accounts.withLock { $0 = [AppFixtures.summaryB] }
                }
                await store.finish()
            }

            #expect(pending.accounts().isEmpty)
            #expect(directory.bound(to: AppFixtures.accountB).read(serverURL: AppFixtures.serverB, path: Fixture.path) != nil)
            #expect(
                recorder.events.value == WipeRecorder.prune(origins: [AppFixtures.originB], accounts: []),
                "the account that was added is not wiped, and the stored list is empty here on purpose so the pending entry can only be saved by unlisting"
            )
        }

        // MARK: Certificates

        @Test("An unreadable keychain never prunes certificates, share uploads or upload defaults")
        func unreadableKeychainDoesNotPrune() async {
            let store = makeStore(activeState(AppFixtures.serverA, AppFixtures.userA)) {
                $0.authClient.listSessionsOrThrow = { throw AuthClientError.keychain(Fixture.keychainFailure) }
            }

            await withMainSerialExecutor {
                await store.send(.destination(.authenticated(.delegate(.activeAccountChanged(credentialsA)))))
                await store.receive(\.accountsRefreshed)
                await store.finish()
            }

            #expect(recorder.events.value.isEmpty, "pruned \(recorder.events.value) on a keychain that could not be read")
        }

        @Test("A readable keychain still prunes to the servers and accounts that remain")
        func readableKeychainPrunes() async {
            let store = makeStore(activeState(AppFixtures.serverA, AppFixtures.userA)) {
                $0.authClient.listSessionsOrThrow = { [credentialsA] in [credentialsA] }
            }

            await withMainSerialExecutor {
                await store.send(.destination(.authenticated(.delegate(.activeAccountChanged(credentialsA)))))
                await store.receive(\.accountsRefreshed)
                await store.finish()
            }

            #expect(recorder.events.value == WipeRecorder.prune(origins: [AppFixtures.originA], accounts: [AppFixtures.accountA]))
        }
    }
}
