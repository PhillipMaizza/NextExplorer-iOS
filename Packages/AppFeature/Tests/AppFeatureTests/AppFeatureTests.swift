import AuthClient
import AuthFeature
import ComposableArchitecture
import CoreModels
import Foundation
import Testing
@testable import AppFeature

@MainActor
@Suite("AppFeature")
struct AppFeatureTests {
    private let serverURL = URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/")

    @Test("happy path: a valid restored session is confirmed with the server, then routes to authenticated")
    func restoresSessionOnLaunch() async {
        let credentials = SessionCredentials(
            serverBaseURL: serverURL,
            authMode: .local,
            cookieName: "connect.sid",
            cookieValue: "abc",
            cookieDomain: "nextexplorer.example.com",
            cookiePath: "/",
            cookieIsSecure: true,
            expiresAt: nil,
            username: "phillip"
        )
        let user = User(id: "1", username: "phillip", email: nil, roles: [])
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.authClient.restoreSession = { credentials }
            $0.authClient.me = { _ in user }
        }

        await store.send(.onAppear)
        // Optimistic: the app shows immediately with a placeholder user from the credentials.
        await store.receive(\.sessionRestoreResponse) {
            $0.destination = .authenticated(
                AuthenticatedFeature.State(
                    serverURL: self.serverURL,
                    user: User(id: "", username: "phillip", email: nil)
                )
            )
        }
        await store.receive(\.sessionValidationResponse) {
            $0.destination = .authenticated(AuthenticatedFeature.State(serverURL: self.serverURL, user: user))
        }
    }

    @Test("edge case: a restored session the server no longer honors falls back to unauthenticated and clears it locally")
    func restoredSessionRejectedByServerFallsBackToUnauthenticated() async {
        let credentials = SessionCredentials(
            serverBaseURL: serverURL,
            authMode: .local,
            cookieName: "connect.sid",
            cookieValue: "stale",
            cookieDomain: "nextexplorer.example.com",
            cookiePath: "/",
            cookieIsSecure: true,
            expiresAt: nil,
            username: "phillip"
        )
        let clearSessionCalled = LockIsolated(false)
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.authClient.restoreSession = { credentials }
            $0.authClient.me = { _ in throw AuthClientError.sessionExpired }
            $0.authClient.clearSession = { clearSessionCalled.setValue(true) }
        }

        await store.send(.onAppear)
        await store.receive(\.sessionRestoreResponse) {
            $0.destination = .authenticated(
                AuthenticatedFeature.State(
                    serverURL: self.serverURL,
                    user: User(id: "", username: "phillip", email: nil)
                )
            )
        }
        await store.receive(\.sessionValidationResponse) {
            $0.destination = .unauthenticated(.init())
        }
        #expect(clearSessionCalled.value)
    }

    @Test("edge case: a network hiccup validating a restored session keeps the optimistic session")
    func networkFailureValidatingKeepsOptimisticSession() async {
        let credentials = SessionCredentials(
            serverBaseURL: serverURL,
            authMode: .local,
            cookieName: "connect.sid",
            cookieValue: "abc",
            cookieDomain: "nextexplorer.example.com",
            cookiePath: "/",
            cookieIsSecure: true,
            expiresAt: nil,
            username: "phillip"
        )
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.authClient.restoreSession = { credentials }
            $0.authClient.me = { _ in throw AuthClientError.network("offline") }
        }

        await store.send(.onAppear)
        await store.receive(\.sessionRestoreResponse) {
            $0.destination = .authenticated(
                AuthenticatedFeature.State(
                    serverURL: self.serverURL,
                    user: User(id: "", username: "phillip", email: nil)
                )
            )
        }
        // Failure is a network error, not an auth rejection: destination is left as-is.
        await store.receive(\.sessionValidationResponse)
    }

    @Test("edge case: no stored session stays on the unauthenticated flow")
    func noStoredSessionStaysUnauthenticated() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.authClient.restoreSession = { nil }
        }

        await store.send(.onAppear)
        // Initial state is `.loading`, so a nil credentials result is a real transition
        // to `.unauthenticated(.init())`, not a no-op.
        await store.receive(\.sessionRestoreResponse) {
            $0.destination = .unauthenticated(.init())
        }
    }

    @Test("happy path: authenticating from the login flow switches to the authenticated destination")
    func authenticatingSwitchesDestination() async {
        // This action is only ever sent while `.unauthenticated` is showing (the login
        // form itself emits it), so the store has to start there rather than at the
        // default `.loading`: TCA raises an error if a scoped action arrives while the
        // destination is a different case.
        let store = TestStore(initialState: AppFeature.State(destination: .unauthenticated(.init()))) {
            AppFeature()
        }
        let user = User(id: "1", username: "phillip", email: nil, roles: [])

        await store.send(.destination(.unauthenticated(.delegate(.authenticated(user, serverURL))))) {
            $0.didAuthenticateFromLogin = true
            $0.destination = .authenticated(AuthenticatedFeature.State(serverURL: self.serverURL, user: user))
        }
    }

    @Test("happy path: signing out switches back to the unauthenticated flow")
    func signOutSwitchesDestination() async {
        let user = User(id: "1", username: "phillip", email: nil, roles: [])
        let store = TestStore(
            initialState: AppFeature.State(
                destination: .authenticated(AuthenticatedFeature.State(serverURL: serverURL, user: user))
            )
        ) {
            AppFeature()
        }

        await store.send(.destination(.authenticated(.delegate(.loggedOut)))) {
            $0.destination = .unauthenticated(.init())
        }
    }

    @Test("edge case: a mid-session 401 drops to the login flow and clears the session")
    func midSessionExpiryDropsToLogin() async {
        let user = User(id: "1", username: "phillip", email: nil, roles: [])
        let cleared = LockIsolated(false)
        let store = TestStore(
            initialState: AppFeature.State(
                destination: .authenticated(AuthenticatedFeature.State(serverURL: serverURL, user: user))
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.authClient.clearSession = { cleared.setValue(true) }
        }
        store.exhaustivity = .off

        // apiResult would set this from any feature's effect; simulate that here.
        store.state.$sessionDidExpire.withLock { $0 = true }

        await store.send(.sessionExpiryDetected) {
            $0.sessionDidExpire = false
            $0.destination = .unauthenticated(.init())
        }
        await store.finish()
        #expect(cleared.value)
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
