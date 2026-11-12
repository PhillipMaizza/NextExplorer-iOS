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
    /// Rule #11 end to end: every store that can hold one account's data is wiped at every
    /// session boundary. Runs on iOS and macOS, so the Mac sign in path is covered by the same
    /// assertions as the phone's.
    @MainActor
    @Suite("Session boundary wipe", .isolatedDependencies)
    struct SessionBoundaryWipeTests {
        private typealias Store = TestStore<AppFeature.State, AppFeature.Action>

        private let recorder = WipeRecorder()

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

        private func signedIn(_ serverURL: URL, _ user: User) -> AppFeature.State {
            AppFeature.State(destination: .authenticated(.init(serverURL: serverURL, user: user)))
        }

        private func optimistic(_ serverURL: URL, username: String) -> AppFeature.Destination.State {
            .authenticated(AuthenticatedFeature.State(serverURL: serverURL, user: User(id: "", username: username, email: nil)))
        }

        private func confirmed(_ serverURL: URL, _ user: User) -> AppFeature.Destination.State {
            .authenticated(AuthenticatedFeature.State(serverURL: serverURL, user: user))
        }

        /// Switches to `next` while `me` and the account list are held, so the strict store sees the remount,
        /// then the refreshed list, then the confirmation, in that order.
        private func switchToAccount(
            _ store: Store,
            next: SessionCredentials,
            user: User,
            serverURL: URL,
            downloadScope: String,
            leaving: String,
            accountList: AsyncGate,
            confirmation: AsyncGate
        ) async {
            await store.send(.destination(.authenticated(.delegate(.activeAccountChanged(next)))))
            await store.receive(\.activateAccount) {
                $0.destination = optimistic(serverURL, username: next.username ?? "")
            }
            await store.receive(\.destination.authenticated.mainTab.offline.accountDeactivated, leaving)
            accountList.open()
            await store.receive(\.accountsRefreshed)
            confirmation.open()
            await store.receive(\.sessionValidationResponse) {
                $0.$downloadScope.withLock { $0 = downloadScope }
                $0.destination = confirmed(serverURL, user)
            }
            await store.receive(\.accountsRefreshed)
        }

        @Test("A fresh sign in from the login screen wipes every store and keeps only the certificates of servers with an account")
        func freshSignIn() async {
            let wipeFinished = AsyncGate()
            let store = makeStore(AppFeature.State(destination: .unauthenticated(.init()))) {
                $0.authClient.listSessionsOrThrow = {
                    try await wipeFinished.wait()
                    return []
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
                ] + WipeRecorder.prune(origins: [AppFixtures.originA], accounts: []),
                "scratch files keep active transfers and the certificate the sign in just used survives"
            )
        }

        @Test("Signing the last account out wipes every store, then removes the certificates, upload defaults and share uploads")
        func lastSignOut() async {
            let store = makeStore(signedIn(AppFixtures.serverA, AppFixtures.userA))

            await store.send(.destination(.authenticated(.delegate(.activeAccountChanged(nil))))) {
                $0.destination = .unauthenticated(.init())
            }
            await store.receive(\.accountsRefreshed)

            await store.finish()

            #expect(recorder.events.value == WipeRecorder.fullTeardown + WipeRecorder.lastSignOutCredentialWipe)
        }

        @Test("An expired session with no other account wipes the account then every store but keeps the certificate")
        func expiry() async {
            let store = makeStore(signedIn(AppFixtures.serverA, AppFixtures.userA)) {
                $0.authClient.me = { _ in throw AuthClientError.sessionExpired }
            }

            await store.send(.sessionExpiryDetected)
            await store.receive(\.sessionExpiryConfirmed)
            await store.receive(\.activeAccountTornDown) {
                $0.destination = .unauthenticated(.init())
            }
            await store.receive(\.accountsRefreshed)

            await store.finish()

            #expect(
                recorder.events.value == [.activeSessionCleared] + WipeRecorder.accountWipe(AppFixtures.accountA) + WipeRecorder.fullTeardown,
                "no certificate, upload default or share upload is removed"
            )
        }

        @Test("Removing an account drops certificates for servers no remaining account uses")
        func accountRemovalPrunesCertificates() async throws {
            let remainingServer = try #require(URL(string: "https://b.example.com:8443"))
            let remaining = AppFixtures.credentials(remainingServer, "bob")
            let confirmation = AsyncGate()
            let accountList = AsyncGate()
            let store = makeStore(signedIn(AppFixtures.serverA, AppFixtures.userA)) {
                $0.authClient.listSessions = {
                    try? await accountList.wait()
                    return []
                }
                $0.authClient.listSessionsOrThrow = { [remaining] in [remaining] }
                $0.authClient.me = { _ in
                    try await confirmation.wait()
                    return AppFixtures.userB
                }
            }

            await switchToAccount(
                store,
                next: remaining,
                user: AppFixtures.userB,
                serverURL: remainingServer,
                downloadScope: "f3431ef88b6625ded950bbeb20ea9249",
                leaving: AppFixtures.accountA,
                accountList: accountList,
                confirmation: confirmation
            )

            #expect(
                recorder.events.value == WipeRecorder.prune(
                    origins: [ClientCertificateOrigin(host: "b.example.com", port: 8443)],
                    accounts: ["https://b.example.com:8443|bob"]
                )
            )
        }

        @Test("Certificates are not pruned while Add Account is open, so its new certificate survives")
        func noPruneWhileAddingAccount() async {
            let confirmation = AsyncGate()
            let accountList = AsyncGate()
            var state = signedIn(AppFixtures.serverA, AppFixtures.userA)
            state.addAccount = LoginFormFeature.State()
            let credentialsB = AppFixtures.credentials(AppFixtures.serverB, "bob")
            let store = makeStore(state) {
                $0.authClient.listSessions = {
                    try? await accountList.wait()
                    return []
                }
                $0.authClient.me = { _ in
                    try await confirmation.wait()
                    return AppFixtures.userB
                }
            }

            await switchToAccount(
                store,
                next: credentialsB,
                user: AppFixtures.userB,
                serverURL: AppFixtures.serverB,
                downloadScope: AppFixtures.downloadScopeB,
                leaving: AppFixtures.accountA,
                accountList: accountList,
                confirmation: confirmation
            )

            #expect(recorder.events.value.isEmpty, "no store is wiped and nothing is pruned")
        }
    }
}
