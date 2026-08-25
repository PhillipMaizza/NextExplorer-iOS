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
        await store.receive(\.sessionRestoreResponse)
        await store.receive(\.sessionValidationResponse) {
            $0.destination = .authenticated(AuthenticatedFeature.State(serverURL: self.serverURL, username: "phillip"))
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
        await store.receive(\.sessionRestoreResponse)
        await store.receive(\.sessionValidationResponse)
        #expect(store.state.destination == .unauthenticated(.init()))
        #expect(clearSessionCalled.value)
    }

    @Test("edge case: no stored session stays on the unauthenticated flow")
    func noStoredSessionStaysUnauthenticated() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.authClient.restoreSession = { nil }
        }

        await store.send(.onAppear)
        // Initial state is already `.unauthenticated(.init())`, so this is a no-op
        // reassignment — no trailing closure since there's no observable state change.
        await store.receive(\.sessionRestoreResponse)
        #expect(store.state.destination == .unauthenticated(.init()))
    }

    @Test("happy path: authenticating from the login flow switches to the authenticated destination")
    func authenticatingSwitchesDestination() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        let user = User(id: "1", username: "phillip", email: nil, roles: [])

        await store.send(.destination(.unauthenticated(.delegate(.authenticated(user, serverURL))))) {
            $0.destination = .authenticated(AuthenticatedFeature.State(serverURL: self.serverURL, username: "phillip"))
        }
    }

    @Test("happy path: signing out switches back to the unauthenticated flow")
    func signOutSwitchesDestination() async {
        let store = TestStore(
            initialState: AppFeature.State(
                destination: .authenticated(AuthenticatedFeature.State(serverURL: serverURL, username: "phillip"))
            )
        ) {
            AppFeature()
        }

        await store.send(.destination(.authenticated(.delegate(.loggedOut)))) {
            $0.destination = .unauthenticated(.init())
        }
    }
}
