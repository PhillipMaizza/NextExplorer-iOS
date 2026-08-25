import AuthClient
import ComposableArchitecture
import CoreModels
import Foundation
import Testing
@testable import AuthFeature

@MainActor
@Suite("LoginFormFeature")
struct LoginFormFeatureTests {
    private let user = User(id: "1", username: "phillip", email: nil, roles: [])

    // MARK: - URL normalization (edge cases)

    @Test("edge case: trailing slashes are stripped")
    func trailingSlashesStripped() {
        let url = LoginFormFeature.normalizedURL(scheme: .https, host: "nextexplorer.example.com///")
        #expect(url?.absoluteString == "https://nextexplorer.example.com")
    }

    @Test("edge case: surrounding whitespace is trimmed")
    func whitespaceTrimmed() {
        let url = LoginFormFeature.normalizedURL(scheme: .http, host: "  192.168.1.50:3000  ")
        #expect(url?.absoluteString == "http://192.168.1.50:3000")
    }

    @Test("edge case: a pasted scheme is stripped in favor of the picker's scheme")
    func pastedSchemeStripped() {
        let url = LoginFormFeature.normalizedURL(scheme: .http, host: "https://nextexplorer.example.com")
        #expect(url?.absoluteString == "http://nextexplorer.example.com")
    }

    @Test("edge case: empty host is invalid")
    func emptyHostIsInvalid() {
        #expect(LoginFormFeature.normalizedURL(scheme: .https, host: "   ") == nil)
    }

    // MARK: - testConnectionButtonTapped

    @Test("happy path: a successful test shows the checkmark, then advances to the credentials page")
    func testConnectionUnlocksLocalFields() async {
        let store = TestStore(initialState: LoginFormFeature.State(host: "nextexplorer.example.com")) {
            LoginFormFeature()
        } withDependencies: {
            $0.authClient.fetchStatus = { _ in AuthStatus(localEnabled: true, oidcEnabled: false) }
            $0.continuousClock = ImmediateClock()
        }

        await store.send(.testConnectionButtonTapped) { $0.connectionPhase = .testing }
        await store.receive(\.testConnectionResponse.success) {
            $0.connectionPhase = .success
            $0.authStatus = AuthStatus(localEnabled: true, oidcEnabled: false)
        }
        await store.receive(\.advanceToCredentials) {
            $0.currentPage = .credentials
        }
    }

    @Test("edge case: changing the host after a successful test re-locks the form")
    func changingHostClearsAuthStatus() async {
        let store = TestStore(
            initialState: LoginFormFeature.State(
                currentPage: .credentials,
                connectionPhase: .success,
                host: "nextexplorer.example.com",
                authStatus: AuthStatus(localEnabled: true, oidcEnabled: false)
            )
        ) {
            LoginFormFeature()
        }

        await store.send(.hostChanged("nextexplorer.example.com/changed")) {
            $0.host = "nextexplorer.example.com/changed"
            $0.currentPage = .server
            $0.connectionPhase = .idle
            $0.authStatus = nil
        }
    }

    @Test("regression: changing the host cancels an in-flight test so a stale response can't land later")
    func hostChangeCancelsInFlightTestConnection() async {
        let clock = TestClock()
        let store = TestStore(initialState: LoginFormFeature.State(host: "old.example.com")) {
            LoginFormFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.authClient.fetchStatus = { _ in AuthStatus(localEnabled: true, oidcEnabled: false) }
        }

        await store.send(.testConnectionButtonTapped) { $0.connectionPhase = .testing }

        // The user abandons this attempt before the (still in-flight) call resolves.
        await store.send(.hostChanged("new.example.com")) {
            $0.host = "new.example.com"
            $0.connectionPhase = .idle
        }

        // Letting time pass must NOT deliver a stale `testConnectionResponse` or
        // auto-advance to credentials — the effect was cancelled, not just ignored.
        await clock.advance(by: .seconds(5))
        await store.finish()
    }

    @Test("edge case: pressing back re-locks the form without touching the typed host")
    func backButtonResetsConnection() async {
        let store = TestStore(
            initialState: LoginFormFeature.State(
                currentPage: .credentials,
                connectionPhase: .success,
                host: "nextexplorer.example.com",
                authStatus: AuthStatus(localEnabled: true, oidcEnabled: false)
            )
        ) {
            LoginFormFeature()
        }

        await store.send(.backButtonTapped) {
            $0.currentPage = .server
            $0.connectionPhase = .idle
            $0.authStatus = nil
        }
    }

    @Test("edge case: empty host never calls the network")
    func emptyHostNeverCallsNetwork() async {
        let store = TestStore(initialState: LoginFormFeature.State()) {
            LoginFormFeature()
        } withDependencies: {
            $0.authClient.fetchStatus = { _ in
                Issue.record("fetchStatus should not be called with no host")
                return AuthStatus(localEnabled: false, oidcEnabled: false)
            }
            $0.continuousClock = ImmediateClock()
        }

        await store.send(.testConnectionButtonTapped) {
            $0.connectionPhase = .failure
            $0.errorMessage = "Enter a valid server address."
        }
        await store.receive(\.revertToIdle) {
            $0.connectionPhase = .idle
        }
        await store.receive(\.clearErrorMessage) {
            $0.errorMessage = nil
        }
    }

    @Test("unexpected error: a server with only SSO enabled surfaces a readable message (this app only supports username/password)")
    func noLocalAuthMethodEnabled() async {
        let store = TestStore(initialState: LoginFormFeature.State(host: "nextexplorer.example.com")) {
            LoginFormFeature()
        } withDependencies: {
            $0.authClient.fetchStatus = { _ in AuthStatus(localEnabled: false, oidcEnabled: true) }
            $0.continuousClock = ImmediateClock()
        }

        await store.send(.testConnectionButtonTapped) { $0.connectionPhase = .testing }
        await store.receive(\.testConnectionResponse.success) {
            $0.connectionPhase = .failure
            $0.authStatus = AuthStatus(localEnabled: false, oidcEnabled: true)
            $0.errorMessage = "This server doesn't have username/password sign-in enabled."
        }
        await store.receive(\.revertToIdle) {
            $0.connectionPhase = .idle
        }
        await store.receive(\.clearErrorMessage) {
            $0.errorMessage = nil
        }
    }

    @Test("unexpected error: transport failure during test connection is wrapped, not propagated raw")
    func transportFailureDuringTestConnection() async {
        let store = TestStore(initialState: LoginFormFeature.State(host: "nextexplorer.example.com")) {
            LoginFormFeature()
        } withDependencies: {
            $0.authClient.fetchStatus = { _ in throw AuthClientError.network("offline") }
            $0.continuousClock = ImmediateClock()
        }

        await store.send(.testConnectionButtonTapped) { $0.connectionPhase = .testing }
        await store.receive(\.testConnectionResponse.failure) {
            $0.connectionPhase = .failure
            $0.errorMessage = "Could not reach that server. Check the address and try again."
        }
        await store.receive(\.revertToIdle) {
            $0.connectionPhase = .idle
        }
        await store.receive(\.clearErrorMessage) {
            $0.errorMessage = nil
        }
    }

    @Test("regression: a Test Connection error message clears itself after 4 seconds, not sooner")
    func errorMessageAutoDismissesAfterFourSeconds() async {
        let clock = TestClock()
        let store = TestStore(initialState: LoginFormFeature.State(host: "nextexplorer.example.com")) {
            LoginFormFeature()
        } withDependencies: {
            $0.authClient.fetchStatus = { _ in throw AuthClientError.network("offline") }
            $0.continuousClock = clock
        }

        await store.send(.testConnectionButtonTapped) { $0.connectionPhase = .testing }
        await clock.advance(by: .seconds(0.3))
        await store.receive(\.testConnectionResponse.failure) {
            $0.connectionPhase = .failure
            $0.errorMessage = "Could not reach that server. Check the address and try again."
        }
        await clock.advance(by: .seconds(1))
        await store.receive(\.revertToIdle) {
            $0.connectionPhase = .idle
        }

        // Just under 4 seconds since the error was set: still showing.
        await clock.advance(by: .seconds(2.5))
        #expect(store.state.errorMessage != nil)

        // At 4 seconds: cleared.
        await clock.advance(by: .seconds(0.5))
        await store.receive(\.clearErrorMessage) {
            $0.errorMessage = nil
        }
    }

    // MARK: - continueButtonTapped (local login)

    @Test("happy path: local login succeeds after a successful test, trimming the identifier")
    func localLoginHappyPath() async {
        let store = TestStore(
            initialState: LoginFormFeature.State(
                host: "nextexplorer.example.com",
                identifier: "  phillip@example.com  ",
                password: "hunter2",
                authStatus: AuthStatus(localEnabled: true, oidcEnabled: false)
            )
        ) {
            LoginFormFeature()
        } withDependencies: {
            $0.authClient.login = { [user] _, identifier, _ in
                #expect(identifier == "phillip@example.com")
                return user
            }
        }

        await store.send(.continueButtonTapped) {
            $0.isSubmitting = true
        }
        await store.receive(\.submitSucceeded) {
            $0.isSubmitting = false
        }
        await store.receive(\.delegate)
    }

    @Test("edge case: Continue is a no-op if local auth was never confirmed via Test Connection")
    func continueNoOpWithoutConfirmedStatus() async {
        let store = TestStore(
            initialState: LoginFormFeature.State(host: "nextexplorer.example.com", identifier: "phillip", password: "x")
        ) {
            LoginFormFeature()
        } withDependencies: {
            $0.authClient.login = { _, _, _ in
                Issue.record("login should not be called without a confirmed authStatus")
                throw AuthClientError.invalidCredentials
            }
        }

        await store.send(.continueButtonTapped)
    }

    @Test("edge case: a non-email identifier is rejected locally, without calling the network")
    func nonEmailIdentifierRejectedLocally() async {
        let store = TestStore(
            initialState: LoginFormFeature.State(
                host: "nextexplorer.example.com",
                identifier: "phillip",
                password: "hunter2",
                authStatus: AuthStatus(localEnabled: true, oidcEnabled: false)
            )
        ) {
            LoginFormFeature()
        } withDependencies: {
            $0.authClient.login = { _, _, _ in
                Issue.record("login should not be called for a non-email identifier")
                throw AuthClientError.invalidCredentials
            }
            $0.continuousClock = ImmediateClock()
        }

        await store.send(.continueButtonTapped) {
            $0.errorMessage = "Enter a valid email address."
            $0.invalidFieldsScope = .identifier
        }
        await store.receive(\.clearErrorMessage) {
            $0.errorMessage = nil
            $0.invalidFieldsScope = nil
        }
    }

    @Test("unexpected error: invalid credentials surfaces a readable message")
    func invalidCredentialsSurfacesMessage() async {
        let store = TestStore(
            initialState: LoginFormFeature.State(
                host: "nextexplorer.example.com",
                identifier: "phillip@example.com",
                password: "wrong",
                authStatus: AuthStatus(localEnabled: true, oidcEnabled: false)
            )
        ) {
            LoginFormFeature()
        } withDependencies: {
            $0.authClient.login = { _, _, _ in throw AuthClientError.invalidCredentials }
            $0.continuousClock = ImmediateClock()
        }

        await store.send(.continueButtonTapped) {
            $0.isSubmitting = true
        }
        await store.receive(\.submitFailed) {
            $0.isSubmitting = false
            $0.errorMessage = "Incorrect username or password."
            $0.invalidFieldsScope = .identifierAndPassword
        }
        await store.receive(\.clearErrorMessage) {
            $0.errorMessage = nil
            $0.invalidFieldsScope = nil
        }
    }

    @Test("regression: sessionCookieMissing does not auto-dismiss — it signals a real failure, not a typo to retry")
    func sessionCookieMissingDoesNotAutoDismiss() async {
        let clock = TestClock()
        let store = TestStore(
            initialState: LoginFormFeature.State(
                host: "nextexplorer.example.com",
                identifier: "phillip@example.com",
                password: "hunter2",
                authStatus: AuthStatus(localEnabled: true, oidcEnabled: false)
            )
        ) {
            LoginFormFeature()
        } withDependencies: {
            $0.authClient.login = { _, _, _ in throw AuthClientError.sessionCookieMissing }
            $0.continuousClock = clock
        }

        await store.send(.continueButtonTapped) {
            $0.isSubmitting = true
        }
        await store.receive(\.submitFailed) {
            $0.isSubmitting = false
            $0.errorMessage = "Sign-in didn't complete. Please try again."
        }

        // Well past the usual 4-second auto-dismiss — the message must still be showing.
        await clock.advance(by: .seconds(30))
        #expect(store.state.errorMessage == "Sign-in didn't complete. Please try again.")
    }
}
