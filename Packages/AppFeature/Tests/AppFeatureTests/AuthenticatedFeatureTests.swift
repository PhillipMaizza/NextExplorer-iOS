@testable import AppFeature
import AuthClient
import ComposableArchitecture
import CoreModels
import Foundation
import Testing

@MainActor
@Suite("AuthenticatedFeature")
struct AuthenticatedFeatureTests {
    private let serverURL = URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/")
    private let user = User(id: "1", username: "phillip", email: nil, roles: [])

    @Test("happy path: signing out flips isSigningOut, logs out on the server, clears the local session, then delegates loggedOut")
    func signOutHappyPath() async {
        let logoutCalled = LockIsolated(false)
        let clearSessionCalled = LockIsolated(false)
        let store = TestStore(
            initialState: AuthenticatedFeature.State(serverURL: serverURL, user: user)
        ) {
            AuthenticatedFeature()
        } withDependencies: {
            $0.authClient.logout = { _ in logoutCalled.setValue(true) }
            $0.authClient.clearSession = { clearSessionCalled.setValue(true) }
        }

        await store.send(.mainTab(.delegate(.signOutButtonTapped))) {
            $0.mainTab.settings.isSigningOut = true
        }
        await store.receive(\.signOutResponse) {
            $0.mainTab.settings.isSigningOut = false
        }
        await store.receive(\.delegate)

        #expect(logoutCalled.value)
        #expect(clearSessionCalled.value)
    }

    @Test("unexpected error: a failed server-side logout call still clears the local session and delegates loggedOut")
    func signOutStillCompletesWhenServerLogoutFails() async {
        // The server round-trip is best-effort (`try?` in the reducer) — a device that's already
        // offline, or a server that's already down, must not trap the user on the authenticated
        // screen with no way to sign out locally.
        let clearSessionCalled = LockIsolated(false)
        let store = TestStore(
            initialState: AuthenticatedFeature.State(serverURL: serverURL, user: user)
        ) {
            AuthenticatedFeature()
        } withDependencies: {
            $0.authClient.logout = { _ in throw AuthClientError.network("offline") }
            $0.authClient.clearSession = { clearSessionCalled.setValue(true) }
        }

        await store.send(.mainTab(.delegate(.signOutButtonTapped))) {
            $0.mainTab.settings.isSigningOut = true
        }
        await store.receive(\.signOutResponse) {
            $0.mainTab.settings.isSigningOut = false
        }
        await store.receive(\.delegate)

        #expect(clearSessionCalled.value)
    }

    @Test("edge case: unrelated mainTab actions pass through without touching sign-out state")
    func unrelatedMainTabActionIsNoOp() async {
        let store = TestStore(
            initialState: AuthenticatedFeature.State(serverURL: serverURL, user: user)
        ) {
            AuthenticatedFeature()
        }

        await store.send(.mainTab(.tabSelected(.favorites))) {
            $0.mainTab.selectedTab = .favorites
        }
    }
}
