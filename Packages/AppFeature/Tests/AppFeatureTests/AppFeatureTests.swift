@testable import AppFeature
import AuthClient
import AuthFeature
import ComposableArchitecture
import CoreModels
import Foundation
import Testing

@MainActor
// Serialized: these tests drive session-boundary transitions that write the process-wide
// `@Shared(.inMemory)` download scope; running them in parallel lets one test's scope write
// race into another's assertions.
@Suite("AppFeature", .serialized)
struct AppFeatureTests {
    /// Runs before each test (swift-testing makes a fresh suite instance per test). The download
    /// scope lives in process-wide `@Shared(.inMemory)`, so clear it so one test's session write
    /// can't leak into the next test's baseline.
    init() {
        @Shared(.inMemory(DownloadAccountScope.sharedKey)) var downloadScope = ""
        $downloadScope.withLock { $0 = "" }
        @Shared(.inMemory(AccountSummary.sharedKey)) var accounts: [AccountSummary] = []
        $accounts.withLock { $0 = [] }
    }

    private let serverURL = URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/")

    private func credentials(serverURL: URL, username: String) -> SessionCredentials {
        SessionCredentials(
            serverBaseURL: serverURL,
            authMode: .local,
            cookieName: "connect.sid",
            cookieValue: "abc",
            cookieDomain: serverURL.host ?? "",
            cookiePath: "/",
            cookieIsSecure: true,
            expiresAt: nil,
            username: username
        )
    }

    @Test("happy path: a valid restored session is confirmed with the server, then routes to authenticated")
    func restoresSessionOnLaunch() async {
        let credentials = credentials(serverURL: serverURL, username: "phillip")
        let user = User(id: "1", username: "phillip", email: nil, roles: [])
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.authClient.restoreSession = { credentials }
            $0.authClient.me = { _ in user }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.sessionValidationResponse)
        store.assert {
            $0.destination = .authenticated(AuthenticatedFeature.State(serverURL: serverURL, user: user))
        }
    }

    @Test("edge case: a restored session the server no longer honors, with no other account, falls back to login and clears it")
    func restoredSessionRejectedFallsBackToLogin() async {
        let credentials = credentials(serverURL: serverURL, username: "phillip")
        let clearAllSessionsCalled = LockIsolated(false)
        let cacheCleared = LockIsolated(false)
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.authClient.restoreSession = { credentials }
            $0.authClient.me = { _ in throw AuthClientError.sessionExpired }
            $0.authClient.clearActiveSession = { nil }
            $0.authClient.clearAllSessions = { clearAllSessionsCalled.setValue(true) }
            $0.directoryCacheStore.clearAll = { cacheCleared.setValue(true) }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.sessionValidationResponse)
        await store.receive(\.activeAccountTornDown)
        store.assert {
            $0.destination = .unauthenticated(.init())
        }
        await store.finish()
        #expect(clearAllSessionsCalled.value)
        #expect(cacheCleared.value)
    }

    @Test("edge case: a network hiccup validating a restored session keeps the optimistic session")
    func networkFailureValidatingKeepsOptimisticSession() async {
        let credentials = credentials(serverURL: serverURL, username: "phillip")
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.authClient.restoreSession = { credentials }
            $0.authClient.me = { _ in throw AuthClientError.network("offline") }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.sessionValidationResponse)
        store.assert {
            $0.destination = .authenticated(
                AuthenticatedFeature.State(serverURL: serverURL, user: User(id: "", username: "phillip", email: nil))
            )
        }
    }

    @Test("edge case: no stored session stays on the unauthenticated flow")
    func noStoredSessionStaysUnauthenticated() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.authClient.restoreSession = { nil }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.sessionRestoreResponse) {
            $0.destination = .unauthenticated(.init())
        }
    }

    @Test("happy path: authenticating from the login flow switches to the authenticated destination")
    func authenticatingSwitchesDestination() async {
        let cacheCleared = LockIsolated(false)
        let store = TestStore(initialState: AppFeature.State(destination: .unauthenticated(.init()))) {
            AppFeature()
        } withDependencies: {
            $0.authClient.listSessions = { [] }
            $0.authClient.activeAccountID = { nil }
            $0.directoryCacheStore.clearAll = { cacheCleared.setValue(true) }
        }
        store.exhaustivity = .off
        let user = User(id: "1", username: "phillip", email: nil, roles: [])

        await store.send(.destination(.unauthenticated(.delegate(.authenticated(user, serverURL))))) {
            $0.$downloadScope.withLock { $0 = DownloadAccountScope.identifier(serverURL: serverURL, userID: user.id) }
            $0.didAuthenticateFromLogin = true
            $0.destination = .authenticated(AuthenticatedFeature.State(serverURL: serverURL, user: user))
        }
        await store.finish()
        #expect(cacheCleared.value)
    }

    @Test("happy path: signing the last account out switches back to the login flow and clears everything")
    func signOutLastAccountSwitchesToLogin() async {
        let user = User(id: "1", username: "phillip", email: nil, roles: [])
        let clearAllSessionsCalled = LockIsolated(false)
        let cacheCleared = LockIsolated(false)
        let store = TestStore(
            initialState: AppFeature.State(
                destination: .authenticated(AuthenticatedFeature.State(serverURL: serverURL, user: user))
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.authClient.clearAllSessions = { clearAllSessionsCalled.setValue(true) }
            $0.directoryCacheStore.clearAll = { cacheCleared.setValue(true) }
        }
        store.exhaustivity = .off

        await store.send(.destination(.authenticated(.delegate(.activeAccountChanged(nil))))) {
            $0.destination = .unauthenticated(.init())
        }
        await store.finish()
        #expect(clearAllSessionsCalled.value)
        #expect(cacheCleared.value)
    }

    @Test("happy path: switching to another account remounts the authenticated UI without clearing caches")
    func switchingAccountRemountsWithoutClearingCache() async {
        let user = User(id: "1", username: "phillip", email: nil, roles: [])
        let otherServer = URL(string: "https://other.example.com") ?? URL(fileURLWithPath: "/")
        let otherUser = User(id: "2", username: "jane", email: nil, roles: [])
        let next = credentials(serverURL: otherServer, username: "jane")
        let cacheCleared = LockIsolated(false)
        let store = TestStore(
            initialState: AppFeature.State(
                destination: .authenticated(AuthenticatedFeature.State(serverURL: serverURL, user: user))
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.authClient.me = { _ in otherUser }
            $0.directoryCacheStore.clearAll = { cacheCleared.setValue(true) }
        }
        store.exhaustivity = .off

        await store.send(.destination(.authenticated(.delegate(.activeAccountChanged(next)))))
        await store.receive(\.activateAccount)
        await store.receive(\.sessionValidationResponse)
        store.assert {
            $0.destination = .authenticated(AuthenticatedFeature.State(serverURL: otherServer, user: otherUser))
        }
        await store.finish()
        // Switching keeps both accounts' caches: no clear.
        #expect(cacheCleared.value == false)
    }

    @Test("edge case: removing a non-active account leaves the current UI in place")
    func removingNonActiveAccountKeepsUI() async {
        let user = User(id: "1", username: "phillip", email: nil, roles: [])
        // The returned active account is the same one currently shown (a non-active account was
        // removed), so the UI must not remount.
        let sameActive = credentials(serverURL: serverURL, username: "phillip")
        let store = TestStore(
            initialState: AppFeature.State(
                destination: .authenticated(AuthenticatedFeature.State(serverURL: serverURL, user: user))
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.authClient.listSessions = { [] }
            $0.authClient.activeAccountID = { nil }
        }
        store.exhaustivity = .off

        await store.send(.destination(.authenticated(.delegate(.activeAccountChanged(sameActive)))))
        await store.receive(\.accountsRefreshed)
        store.assert {
            $0.destination = .authenticated(AuthenticatedFeature.State(serverURL: serverURL, user: user))
        }
    }

    @Test("happy path: adding an account adopts it without clearing existing caches")
    func addAccountAdoptsWithoutClearingCache() async {
        let user = User(id: "1", username: "phillip", email: nil, roles: [])
        let newServer = URL(string: "https://new.example.com") ?? URL(fileURLWithPath: "/")
        let newUser = User(id: "2", username: "jane", email: nil, roles: [])
        let cacheCleared = LockIsolated(false)
        var initialState = AppFeature.State(
            destination: .authenticated(AuthenticatedFeature.State(serverURL: serverURL, user: user))
        )
        initialState.addAccount = LoginFormFeature.State()
        let store = TestStore(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.authClient.listSessions = { [] }
            $0.authClient.activeAccountID = { nil }
            $0.directoryCacheStore.clearAll = { cacheCleared.setValue(true) }
        }
        store.exhaustivity = .off

        await store.send(.addAccount(.presented(.delegate(.authenticated(newUser, newServer)))))
        store.assert {
            $0.addAccount = nil
            $0.destination = .authenticated(AuthenticatedFeature.State(serverURL: newServer, user: newUser))
        }
        await store.finish()
        #expect(cacheCleared.value == false)
    }

    @Test("edge case: a mid-session 401 with another account signed in switches to it")
    func midSessionExpiryFallsThroughToNextAccount() async {
        let user = User(id: "1", username: "phillip", email: nil, roles: [])
        let otherServer = URL(string: "https://other.example.com") ?? URL(fileURLWithPath: "/")
        let otherUser = User(id: "2", username: "jane", email: nil, roles: [])
        let next = credentials(serverURL: otherServer, username: "jane")
        let store = TestStore(
            initialState: AppFeature.State(
                destination: .authenticated(AuthenticatedFeature.State(serverURL: serverURL, user: user))
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.authClient.clearActiveSession = { next }
            $0.authClient.me = { _ in otherUser }
        }
        store.exhaustivity = .off
        store.state.$sessionDidExpire.withLock { $0 = true }

        await store.send(.sessionExpiryDetected)
        await store.receive(\.activeAccountTornDown)
        await store.receive(\.activateAccount)
        await store.receive(\.sessionValidationResponse)
        store.assert {
            $0.sessionDidExpire = false
            $0.destination = .authenticated(AuthenticatedFeature.State(serverURL: otherServer, user: otherUser))
        }
    }

    @Test("edge case: a mid-session 401 with no other account drops to the login flow")
    func midSessionExpiryDropsToLogin() async {
        let user = User(id: "1", username: "phillip", email: nil, roles: [])
        let clearAllSessionsCalled = LockIsolated(false)
        let cacheCleared = LockIsolated(false)
        let store = TestStore(
            initialState: AppFeature.State(
                destination: .authenticated(AuthenticatedFeature.State(serverURL: serverURL, user: user))
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.authClient.clearActiveSession = { nil }
            $0.authClient.clearAllSessions = { clearAllSessionsCalled.setValue(true) }
            $0.directoryCacheStore.clearAll = { cacheCleared.setValue(true) }
        }
        store.exhaustivity = .off
        store.state.$sessionDidExpire.withLock { $0 = true }

        await store.send(.sessionExpiryDetected)
        await store.receive(\.activeAccountTornDown)
        store.assert {
            $0.sessionDidExpire = false
            $0.destination = .unauthenticated(.init())
        }
        await store.finish()
        #expect(clearAllSessionsCalled.value)
        #expect(cacheCleared.value)
    }

    @Test("edge case: sessionExpiryDetected while already unauthenticated is a no-op")
    func expiryWhileUnauthenticatedIsANoOp() async {
        let store = TestStore(initialState: AppFeature.State(destination: .unauthenticated(.init()))) {
            AppFeature()
        }
        store.exhaustivity = .off
        store.state.$sessionDidExpire.withLock { $0 = true }

        await store.send(.sessionExpiryDetected) {
            $0.sessionDidExpire = false
        }
    }
}
