import AuthClient
@testable import AuthFeature
import ComposableArchitecture
import CoreModels
import Foundation
import Testing
import TestUtils

@MainActor
@Suite("Lock screen", .isolatedDependencies)
struct LockFeatureTests {
    private typealias Store = TestStore<LockFeature.State, LockFeature.Action>

    private let serverURL = URL(string: TestHost.nextExplorerURLString) ?? URL(fileURLWithPath: "/")
    private let user = LoginFormTestSupport.user

    private func lockState(_ authMode: AuthMode, email: String? = nil) -> LockFeature.State {
        LockFeature.State(account: AccountSummary(
            id: SessionCredentials.accountID(serverURL: serverURL, username: TestAccount.username),
            username: TestAccount.username,
            serverURL: serverURL,
            isActive: true,
            email: email,
            authMode: authMode,
            requireSignIn: RequireSignIn(),
            isLocked: true
        ))
    }

    private func makeStore(
        _ state: LockFeature.State,
        configure: (inout DependencyValues) -> Void = { _ in }
    ) -> Store {
        TestStore(initialState: state) {
            LockFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.loginLogDate = { MockDate.date }
            configure(&$0)
        }
    }

    @Test("Sign in with SSO runs a private browser session against the locked server and hands the user up")
    func ssoUnlocks() async {
        let sessions = LockIsolated<[OIDCBrowserSession]>([])
        let store = makeStore(lockState(.oidc)) { [user] in
            $0.authClient.loginOIDC = { _, session in
                sessions.withValue { $0.append(session) }
                return user
            }
        }

        await store.send(.ssoButtonTapped) { $0.ssoPhase = .signingIn }
        await store.receive(\.ssoResponse) { $0.ssoPhase = .idle }
        await store.receive(\.delegate.signedIn)

        #expect(sessions.value == [.ephemeral])
    }

    @Test("Closing the SSO sheet shows nothing, a failed SSO shows the error")
    func ssoFailures() async {
        let store = makeStore(lockState(.oidc)) {
            $0.authClient.loginOIDC = { _, _ in throw AuthClientError.oidcCancelled }
        }

        await store.send(.ssoButtonTapped) { $0.ssoPhase = .signingIn }
        await store.receive(\.ssoResponse) { $0.ssoPhase = .idle }

        store.dependencies.authClient.loginOIDC = { _, _ in throw AuthClientError.oidcFailed(TestSession.cookieValue) }
        await store.send(.ssoButtonTapped) { $0.ssoPhase = .signingIn }
        await store.receive(\.ssoResponse) {
            $0.ssoPhase = .idle
            $0.problem = .signInFailed(.oidcFailed(TestSession.cookieValue))
        }
    }

    @Test("Sign in prefills the email over the username, since a username can name several accounts")
    func signInPrefillsEmail() async {
        let store = makeStore(lockState(.local, email: TestAccount.email)) {
            $0.authClient.fetchStatus = { _ in
                try await suspendUntilCancelled()
                return LoginFormTestSupport.passwordOnly
            }
        }
        let url = serverURL

        await store.send(.signInButtonTapped) {
            var login = LoginFormFeature.State(
                scheme: .https,
                host: TestHost.nextExplorer,
                identifier: TestAccount.email
            )
            login.browserSession = .ephemeral
            $0.signIn = login
        }
        await store.receive(\.signIn.presented.testConnectionButtonTapped) {
            $0.signIn?.connectionPhase = .testing
            $0.signIn?.diagnostics.record(
                "connecting: \(LoginDiagnostics.describe(server: url))",
                at: MockDate.date
            )
        }
        await store.send(.signIn(.dismiss)) { $0.signIn = nil }
        await store.send(.signInSheetDismissed)
    }

    @Test("Sign in opens the login form on the locked server and account, in a private browser session")
    func signInPrefills() async {
        let store = makeStore(lockState(.local)) {
            $0.authClient.fetchStatus = { _ in
                try await suspendUntilCancelled()
                return LoginFormTestSupport.passwordOnly
            }
        }
        let url = serverURL

        await store.send(.signInButtonTapped) {
            var login = LoginFormFeature.State(
                scheme: .https,
                host: TestHost.nextExplorer,
                identifier: TestAccount.username
            )
            login.browserSession = .ephemeral
            $0.signIn = login
        }
        await store.receive(\.signIn.presented.testConnectionButtonTapped) {
            $0.signIn?.connectionPhase = .testing
            $0.signIn?.diagnostics.record(
                "connecting: \(LoginDiagnostics.describe(server: url))",
                at: MockDate.date
            )
        }
        await store.send(.signIn(.dismiss)) { $0.signIn = nil }
        await store.send(.signInSheetDismissed)
    }

    @Test("A password sign in waits for the sheet to close before it hands the user up")
    func signInWaitsForDismiss() async {
        var state = lockState(.local)
        state.signIn = LoginFormFeature.State(host: TestHost.nextExplorer)
        let store = makeStore(state)

        await store.send(.signIn(.presented(.delegate(.authenticated(user, serverURL))))) { [user, serverURL] in
            $0.pendingSignIn = LockFeature.SignedIn(user: user, serverURL: serverURL)
            $0.signIn = nil
        }
        await store.send(.signInSheetDismissed) { $0.pendingSignIn = nil }
        await store.receive(\.delegate.signedIn)
    }

    @Test("Sign out asks first, then hands the request up, and a failure shows the problem")
    func signOut() async {
        let store = makeStore(lockState(.local))

        await store.send(.signOutButtonTapped) { $0.signOut = .confirming }
        await store.send(.signOutCancelled) { $0.signOut = .idle }
        await store.send(.signOutButtonTapped) { $0.signOut = .confirming }
        await store.send(.signOutConfirmed) { $0.signOut = .running }
        await store.receive(\.delegate.signOutRequested)
        await store.send(.signOutFailed) {
            $0.signOut = .idle
            $0.problem = .signOutFailed
        }
    }

    @Test("Another account refused at the lock says so")
    func otherAccount() async {
        let store = makeStore(lockState(.oidc))

        await store.send(.otherAccountRefused) { $0.problem = .otherAccount }
    }
}
