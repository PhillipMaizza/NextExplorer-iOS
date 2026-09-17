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

    private func credentials(serverURL: URL, username: String) -> SessionCredentials {
        SessionCredentials(
            serverBaseURL: serverURL,
            authMode: .local,
            cookieName: "connect.sid",
            cookieValue: "v",
            cookieDomain: serverURL.host ?? "",
            cookiePath: "/",
            cookieIsSecure: true,
            expiresAt: nil,
            username: username
        )
    }

    @Test("signing out the last account: removes it and delegates activeAccountChanged(nil)")
    func signOutLastAccount() async {
        let removedID = LockIsolated<String?>(nil)
        let store = TestStore(
            initialState: AuthenticatedFeature.State(serverURL: serverURL, user: user)
        ) {
            AuthenticatedFeature()
        } withDependencies: {
            $0.authClient.removeAccount = { id in removedID.setValue(id); return nil }
        }

        await store.send(.mainTab(.delegate(.signOutButtonTapped))) {
            $0.mainTab.settings.isSigningOut = true
        }
        await store.receive(\.accountChangeResolved) {
            $0.mainTab.settings.isSigningOut = false
        }
        await store.receive(\.delegate)

        #expect(removedID.value == serverURL.absoluteString + "|phillip")
    }

    @Test("signing out with another account left: switches to the next account")
    func signOutFallsThroughToNextAccount() async {
        let otherServer = URL(string: "https://other.example.com") ?? URL(fileURLWithPath: "/")
        let next = credentials(serverURL: otherServer, username: "jane")
        let store = TestStore(
            initialState: AuthenticatedFeature.State(serverURL: serverURL, user: user)
        ) {
            AuthenticatedFeature()
        } withDependencies: {
            $0.authClient.removeAccount = { _ in next }
        }

        await store.send(.mainTab(.delegate(.signOutButtonTapped))) {
            $0.mainTab.settings.isSigningOut = true
        }
        await store.receive(\.accountChangeResolved) {
            $0.mainTab.settings.isSigningOut = false
        }
        await store.receive(\.delegate.activeAccountChanged)
    }

    @Test("switch account: performs the switch and delegates the new active account")
    func switchAccount() async {
        let otherServer = URL(string: "https://other.example.com") ?? URL(fileURLWithPath: "/")
        let switched = credentials(serverURL: otherServer, username: "jane")
        let requestedID = LockIsolated<String?>(nil)
        let store = TestStore(
            initialState: AuthenticatedFeature.State(serverURL: serverURL, user: user)
        ) {
            AuthenticatedFeature()
        } withDependencies: {
            $0.authClient.switchAccount = { id in requestedID.setValue(id); return switched }
        }

        await store.send(.mainTab(.delegate(.switchAccount(switched.accountID))))
        await store.receive(\.accountChangeResolved)
        await store.receive(\.delegate.activeAccountChanged)

        #expect(requestedID.value == switched.accountID)
    }

    @Test("add account request bubbles straight up to the parent")
    func addAccountRequestBubbles() async {
        let store = TestStore(
            initialState: AuthenticatedFeature.State(serverURL: serverURL, user: user)
        ) {
            AuthenticatedFeature()
        }

        await store.send(.mainTab(.delegate(.addAccountRequested)))
        await store.receive(\.delegate.addAccountRequested)
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
