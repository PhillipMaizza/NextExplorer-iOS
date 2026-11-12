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

extension AppSuites {
    @MainActor
    @Suite("AppFeature routing", .isolatedDependencies)
    struct AppFeatureTests {
        private typealias Store = TestStore<AppFeature.State, AppFeature.Action>

        private let credentialsA = AppFixtures.credentials(AppFixtures.serverA, "alice")
        private let credentialsB = AppFixtures.credentials(AppFixtures.serverB, "bob")
        private let recorder = WipeRecorder()

        private func makeStore(
            _ state: AppFeature.State = AppFeature.State(),
            configure: (inout DependencyValues) -> Void = { _ in }
        ) -> Store {
            TestStore(initialState: state) {
                AppFeature()
            } withDependencies: {
                recorder.install(into: &$0)
                configure(&$0)
            }
        }

        private func authenticated(_ serverURL: URL, _ user: User) -> AppFeature.State {
            AppFeature.State(destination: .authenticated(AuthenticatedFeature.State(serverURL: serverURL, user: user)))
        }

        /// The session shown straight after a launch or a switch, before `me` confirms the user.
        private func optimistic(_ serverURL: URL, username: String) -> AppFeature.Destination.State {
            .authenticated(AuthenticatedFeature.State(serverURL: serverURL, user: User(id: "", username: username, email: nil)))
        }

        private func confirmed(_ serverURL: URL, _ user: User) -> AppFeature.Destination.State {
            .authenticated(AuthenticatedFeature.State(serverURL: serverURL, user: user))
        }

        private func updateReview(_ state: inout AppFeature.State, _ update: (inout UploadReviewFeature.State?) -> Void) {
            state.destination.modify(\.authenticated) { update(&$0.mainTab.browse.root.uploadReview) }
        }

        // MARK: Launch

        @Test("A valid restored session is shown at once, then confirmed with the server and scoped to its downloads")
        func restoresSessionOnLaunch() async {
            let confirmation = AsyncGate()
            let accountList = AsyncGate()
            let store = makeStore {
                $0.authClient.restoreSession = { [credentialsA] in credentialsA }
                $0.authClient.me = { _ in
                    try await confirmation.wait()
                    return AppFixtures.userA
                }
                $0.authClient.listSessions = { [credentialsA] in
                    try? await accountList.wait()
                    return [credentialsA]
                }
                $0.authClient.activeAccountID = { AppFixtures.accountA }
            }

            await store.send(.onAppear)
            await store.receive(\.sessionRestoreResponse) {
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

            #expect(recorder.events.value.isEmpty, "a valid session wipes nothing")
        }

        @Test("A restored session the server rejects, with no other account, falls back to login and wipes the account then everything")
        func restoredSessionRejectedFallsBackToLogin() async {
            let confirmation = AsyncGate()
            let store = makeStore {
                $0.authClient.restoreSession = { [credentialsA] in credentialsA }
                $0.authClient.me = { _ in
                    try await confirmation.wait()
                    throw AuthClientError.sessionExpired
                }
            }

            await store.send(.onAppear)
            await store.receive(\.sessionRestoreResponse) {
                $0.destination = optimistic(AppFixtures.serverA, username: "alice")
            }
            await store.receive(\.accountsRefreshed)
            confirmation.open()
            await store.receive(\.sessionValidationResponse)
            await store.receive(\.activeAccountTornDown) {
                $0.destination = .unauthenticated(.init())
            }
            await store.receive(\.accountsRefreshed)

            await store.finish()

            #expect(
                recorder.events.value == [.activeSessionCleared] + WipeRecorder.accountWipe(AppFixtures.accountA) + WipeRecorder.fullTeardown
            )
        }

        @Test("A network failure validating a restored session keeps the optimistic session and wipes nothing")
        func networkFailureValidatingKeepsOptimisticSession() async {
            let confirmation = AsyncGate()
            let store = makeStore {
                $0.authClient.restoreSession = { [credentialsA] in credentialsA }
                $0.authClient.me = { _ in
                    try await confirmation.wait()
                    throw AuthClientError.network("offline")
                }
                $0.authClient.clearActiveSession = {
                    Issue.record("an unreachable server does not prove the session is gone")
                    return nil
                }
            }

            await store.send(.onAppear)
            await store.receive(\.sessionRestoreResponse) {
                $0.destination = optimistic(AppFixtures.serverA, username: "alice")
            }
            await store.receive(\.accountsRefreshed)
            confirmation.open()
            await store.receive(\.sessionValidationResponse)

            await store.finish()

            #expect(recorder.events.value.isEmpty)
        }

        @Test("No stored session stays on the login flow")
        func noStoredSessionStaysUnauthenticated() async {
            let store = makeStore {
                $0.authClient.restoreSession = { nil }
            }

            await store.send(.onAppear)
            await store.receive(\.sessionRestoreResponse) {
                $0.destination = .unauthenticated(.init())
            }
            await store.receive(\.accountsRefreshed)

            await store.finish()

            #expect(recorder.events.value.isEmpty)
        }

        // MARK: Signing in and out

        @Test("Signing in from the login flow switches to the authenticated destination after wiping every cache")
        func authenticatingSwitchesDestination() async {
            let wipeFinished = AsyncGate()
            let store = makeStore(AppFeature.State(destination: .unauthenticated(.init()))) {
                $0.authClient.listSessionsOrThrow = { [credentialsA] in
                    try await wipeFinished.wait()
                    return [credentialsA]
                }
                $0.sessionScratchStore.purge = { [recorder] scope in
                    recorder.record(.scratchPurged(scope))
                    wipeFinished.open()
                }
            }

            await store.send(.destination(.unauthenticated(.delegate(.authenticated(AppFixtures.userA, AppFixtures.serverA))))) {
                $0.$downloadScope.withLock { $0 = AppFixtures.downloadScopeA }
                $0.didAuthenticateFromLogin = true
                $0.destination = confirmed(AppFixtures.serverA, AppFixtures.userA)
            }
            await store.receive(\.accountsRefreshed)
            await store.finish()

            #expect(
                recorder.events.value == [
                    .directoryCacheCleared, .jsonCacheCleared, .thumbnailMemoryCleared,
                    .previewCacheCleared, .offlineFilesCleared, .scratchPurged(.keepingActiveTransfers),
                ] + WipeRecorder.prune(origins: [AppFixtures.originA], accounts: [AppFixtures.accountA]),
                "the sign in wipes every store, then the pruning keeps only the accounts that remain"
            )
        }

        @Test("Signing the last account out switches back to the login flow and wipes everything")
        func signOutLastAccountSwitchesToLogin() async {
            let store = makeStore(authenticated(AppFixtures.serverA, AppFixtures.userA))

            await store.send(.destination(.authenticated(.delegate(.activeAccountChanged(nil))))) {
                $0.destination = .unauthenticated(.init())
            }
            await store.receive(\.accountsRefreshed)

            await store.finish()

            #expect(recorder.events.value == WipeRecorder.fullTeardown + WipeRecorder.lastSignOutCredentialWipe)
        }

        @Test("Switching to another account remounts the authenticated UI, stops the left account's offline work and wipes no cache")
        func switchingAccountRemountsWithoutClearingCache() async {
            let confirmation = AsyncGate()
            let accountList = AsyncGate()
            let store = makeStore(authenticated(AppFixtures.serverA, AppFixtures.userA)) {
                $0.authClient.me = { _ in
                    try await confirmation.wait()
                    return AppFixtures.userB
                }
                $0.authClient.listSessions = {
                    try? await accountList.wait()
                    return []
                }
                $0.authClient.listSessionsOrThrow = { [credentialsA, credentialsB] in [credentialsA, credentialsB] }
            }

            await store.send(.destination(.authenticated(.delegate(.activeAccountChanged(credentialsB)))))
            await store.receive(\.activateAccount) {
                $0.destination = optimistic(AppFixtures.serverB, username: "bob")
            }
            await store.receive(\.destination.authenticated.mainTab.offline.accountDeactivated, AppFixtures.accountA)
            accountList.open()
            await store.receive(\.accountsRefreshed)
            confirmation.open()
            await store.receive(\.sessionValidationResponse) {
                $0.$downloadScope.withLock { $0 = AppFixtures.downloadScopeB }
                $0.destination = confirmed(AppFixtures.serverB, AppFixtures.userB)
            }
            await store.receive(\.accountsRefreshed)

            await store.finish()

            #expect(
                recorder.events.value == WipeRecorder.prune(
                    origins: [AppFixtures.originA, AppFixtures.originB], accounts: [AppFixtures.accountA, AppFixtures.accountB]
                ),
                "both accounts keep their caches, only what belongs to no remaining account is pruned"
            )
        }

        @Test("Removing a non active account leaves the current UI in place and wipes no cache")
        func removingNonActiveAccountKeepsUI() async {
            let store = makeStore(authenticated(AppFixtures.serverA, AppFixtures.userA)) {
                $0.authClient.listSessionsOrThrow = { [credentialsA] in [credentialsA] }
            }

            await store.send(.destination(.authenticated(.delegate(.activeAccountChanged(credentialsA)))))
            await store.receive(\.accountsRefreshed)

            await store.finish()

            #expect(recorder.events.value == WipeRecorder.prune(origins: [AppFixtures.originA], accounts: [AppFixtures.accountA]))
        }

        // MARK: Shared files

        @Test("Files shared in while signed out wait in the inbox")
        func incomingFilesWhileSignedOutAreQueued() async {
            let scan = URL(fileURLWithPath: "/tmp/Scan.pdf")
            let store = makeStore(AppFeature.State(destination: .unauthenticated(.init())))

            await store.send(.incomingFiles([scan])) {
                $0.$sharedFileInbox.withLock { $0 = [scan] }
            }
        }

        @Test("Files shared in while signed in go straight to the tab shell, which drains the inbox and stages them for review")
        func incomingFilesWhileSignedInAreHandedOver() async {
            let scan = URL(fileURLWithPath: "/tmp/Scan.pdf")
            let prepared = PickedFile(id: TestID.uuid(), fileURL: scan, fileName: "Scan.pdf", size: 10)
            let stagedURLs = LockIsolated<[URL]>([])
            let store = makeStore(authenticated(AppFixtures.serverA, AppFixtures.userA)) {
                $0.uploadStaging.stageDocuments = { urls in
                    stagedURLs.setValue(urls)
                    return AsyncStream { continuation in
                        continuation.yield(prepared)
                        continuation.finish()
                    }
                }
            }

            // The tab shell drains the inbox before the store compares, so the append and the drain net to no change.
            await store.send(.incomingFiles([scan])) {
                $0.$sharedFileInbox.withLock { $0 = [] }
            }
            await store.receive(\.destination.authenticated.mainTab.sharedFilesArrived)
            await store.receive(\.destination.authenticated.mainTab.browse.receiveSharedFiles)
            await store.receive(\.destination.authenticated.mainTab.browse.root.receiveSharedFiles)
            await store.receive(\.destination.authenticated.mainTab.browse.root.reviewSharedFiles) {
                updateReview(&$0) {
                    $0 = UploadReviewFeature.State(serverURL: AppFixtures.serverA, startingDestination: "")
                }
            }
            await store.receive(\.destination.authenticated.mainTab.browse.root.uploadReview.presented.stage) {
                updateReview(&$0) { $0?.preparingCount = 1 }
            }
            await store.receive(\.destination.authenticated.mainTab.browse.root.uploadReview.presented.filePrepared) {
                updateReview(&$0) {
                    $0?.files = [prepared]
                    $0?.preparingCount = 0
                }
            }
            await store.receive(\.destination.authenticated.mainTab.browse.root.uploadReview.presented.stagingBatchFinished)

            await store.finish()

            #expect(stagedURLs.value == [scan])
        }

        @Test("A non file URL is ignored")
        func incomingNonFileURLIsIgnored() async throws {
            let web = try #require(URL(string: "https://example.com/doc.pdf"))
            let store = makeStore(AppFeature.State(destination: .unauthenticated(.init())))

            await store.send(.incomingFiles([web]))
        }

        // MARK: Adding an account

        @Test("Adding an account adopts it once the sheet is dismissed, without wiping caches")
        func addAccountAdoptsWithoutClearingCache() async {
            var state = authenticated(AppFixtures.serverA, AppFixtures.userA)
            state.addAccount = LoginFormFeature.State()
            let accountList = AsyncGate()
            let store = makeStore(state) {
                $0.authClient.listSessions = {
                    try? await accountList.wait()
                    return []
                }
                $0.authClient.listSessionsOrThrow = { [credentialsA, credentialsB] in [credentialsA, credentialsB] }
            }

            await store.send(.addAccount(.presented(.delegate(.authenticated(AppFixtures.userB, AppFixtures.serverB))))) {
                $0.addAccount = nil
                $0.pendingAddedAccount = AppFeature.AddedAccount(user: AppFixtures.userB, serverURL: AppFixtures.serverB)
            }

            #expect(recorder.events.value.isEmpty, "nothing is adopted or wiped while the sheet is still dismissing")

            await store.send(.addAccountSheetDismissed) {
                $0.pendingAddedAccount = nil
                $0.$downloadScope.withLock { $0 = AppFixtures.downloadScopeB }
                $0.destination = confirmed(AppFixtures.serverB, AppFixtures.userB)
            }
            await store.receive(\.destination.authenticated.mainTab.offline.accountDeactivated, AppFixtures.accountA)
            accountList.open()
            await store.receive(\.accountsRefreshed)
            await store.finish()

            #expect(
                recorder.events.value == WipeRecorder.prune(
                    origins: [AppFixtures.originA, AppFixtures.originB], accounts: [AppFixtures.accountA, AppFixtures.accountB]
                )
            )
        }

        // MARK: Session expiry

        @Test("A mid session 401 with another account signed in wipes only the expired account, twice, and switches to the next")
        func midSessionExpiryFallsThroughToNextAccount() async {
            let json = JSONCacheStore.inMemory()
            json.bound(to: AppFixtures.accountA).write(key: "favorites", data: Data("a".utf8))
            json.bound(to: AppFixtures.accountB).write(key: "favorites", data: Data("b".utf8))
            let pending = PendingAccountWipes.inMemory()
            let confirmation = AsyncGate()
            let store = makeStore(authenticated(AppFixtures.serverA, AppFixtures.userA)) {
                $0.pendingAccountWipes = pending
                $0.authClient.clearActiveSession = { [recorder, credentialsB] in
                    recorder.record(.activeSessionCleared)
                    return credentialsB
                }
                $0.authClient.listSessionsOrThrow = { [credentialsB] in [credentialsB] }
                $0.authClient.me = { url in
                    if url == AppFixtures.serverA {
                        throw AuthClientError.sessionExpired
                    }
                    try await confirmation.wait()
                    return AppFixtures.userB
                }
                $0.jsonCacheStore = json
            }
            store.state.$sessionDidExpire.withLock { $0 = true }

            await store.send(.sessionExpiryDetected) {
                $0.$sessionDidExpire.withLock { $0 = false }
            }
            await store.receive(\.sessionExpiryConfirmed)
            await store.receive(\.activeAccountTornDown)
            await store.receive(\.activateAccount) {
                $0.destination = optimistic(AppFixtures.serverB, username: "bob")
            }
            await store.receive(\.destination.authenticated.mainTab.offline.accountDeactivated, AppFixtures.accountA)
            await store.receive(\.accountsRefreshed)
            confirmation.open()
            await store.receive(\.sessionValidationResponse) {
                $0.$downloadScope.withLock { $0 = AppFixtures.downloadScopeB }
                $0.destination = confirmed(AppFixtures.serverB, AppFixtures.userB)
            }
            await store.receive(\.accountsRefreshed)

            await store.finish()

            #expect(json.bound(to: AppFixtures.accountA).read(key: "favorites") == nil)
            #expect(json.bound(to: AppFixtures.accountB).read(key: "favorites") != nil)
            let expiredAccountWipe: [WipeRecorder.Event] = [
                .directoryAccountCleared(AppFixtures.accountA),
                .previewAccountCleared(AppFixtures.accountA),
                .offlineAccountCleared(AppFixtures.accountA),
                .thumbnailMemoryCleared,
            ]
            #expect(
                recorder.events.value == [.activeSessionCleared] + expiredAccountWipe + expiredAccountWipe,
                "the expired account is wiped on expiry and again by the second pass, the next account's caches stay"
            )
            #expect(pending.accounts().isEmpty)
        }

        @Test("A mid session 401 with no other account drops to the login flow and wipes the account then everything")
        func midSessionExpiryDropsToLogin() async {
            let store = makeStore(authenticated(AppFixtures.serverA, AppFixtures.userA)) {
                $0.authClient.me = { _ in throw AuthClientError.sessionExpired }
            }
            store.state.$sessionDidExpire.withLock { $0 = true }

            await store.send(.sessionExpiryDetected) {
                $0.$sessionDidExpire.withLock { $0 = false }
            }
            await store.receive(\.sessionExpiryConfirmed)
            await store.receive(\.activeAccountTornDown) {
                $0.destination = .unauthenticated(.init())
            }
            await store.receive(\.accountsRefreshed)

            await store.finish()

            #expect(
                recorder.events.value == [.activeSessionCleared] + WipeRecorder.accountWipe(AppFixtures.accountA) + WipeRecorder.fullTeardown
            )
        }

        @Test("sessionExpiryDetected while already signed out only resets the flag and asks the server nothing")
        func expiryWhileUnauthenticatedIsANoOp() async {
            let store = makeStore(AppFeature.State(destination: .unauthenticated(.init()))) {
                $0.authClient.me = { _ in
                    Issue.record("there is no session to check")
                    return AppFixtures.userA
                }
            }
            store.state.$sessionDidExpire.withLock { $0 = true }

            await store.send(.sessionExpiryDetected) {
                $0.$sessionDidExpire.withLock { $0 = false }
            }

            await store.finish()

            #expect(recorder.events.value.isEmpty)
        }
    }
}
