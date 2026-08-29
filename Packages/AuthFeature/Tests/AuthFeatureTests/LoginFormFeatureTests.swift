import AuthClient
import ComposableArchitecture
import CoreModels
import Foundation
import Localization
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

    @Test("the scheme picker follows what's typed: digit ⇒ http, hostname ⇒ https, prefix wins")
    func schemeFollowsHost() async {
        let store = TestStore(initialState: LoginFormFeature.State()) { LoginFormFeature() }
        store.exhaustivity = .off

        await store.send(.hostChanged("192.168.1.50:3000")) { $0.scheme = .http }
        // Deleting the IP and typing a hostname flips it back.
        await store.send(.hostChanged("nextexplorer.example.com")) { $0.scheme = .https }
        await store.send(.hostChanged("http://box.local")) { $0.scheme = .http }
        await store.send(.hostChanged("https://box.local")) { $0.scheme = .https }
    }

    @Test("a manual scheme pick sticks while typing, until the field is cleared")
    func manualSchemePickSticks() async {
        let store = TestStore(initialState: LoginFormFeature.State()) { LoginFormFeature() }
        store.exhaustivity = .off

        // User forces http for a LAN hostname.
        await store.send(.schemeChanged(.http)) { $0.scheme = .http; $0.schemeWasSetByUser = true }
        await store.send(.hostChanged("nas")) { $0.host = "nas" }
        #expect(store.state.scheme == .http)
        await store.send(.hostChanged("nas.local"))
        #expect(store.state.scheme == .http)

        // Clearing the field drops the override, inference takes over again.
        await store.send(.hostChanged("")) { $0.schemeWasSetByUser = false }
        await store.send(.hostChanged("example.com")) { $0.scheme = .https }
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
            $0.errorMessage = L10n.Login.errorInvalidServer
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
            $0.errorMessage = L10n.Login.errorNoLocalAuth
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
            $0.errorMessage = L10n.Login.errorUnreachable
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
            $0.errorMessage = L10n.Login.errorUnreachable
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
            $0.errorMessage = L10n.Login.errorInvalidEmail
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
            $0.errorMessage = L10n.Login.errorInvalidCredentials
            $0.invalidFieldsScope = .identifierAndPassword
        }
        await store.receive(\.clearErrorMessage) {
            $0.errorMessage = nil
            $0.invalidFieldsScope = nil
        }
    }

    @Test("unexpected error: rate limiting (429, or a lockout the server reports as 429) surfaces a readable message")
    func rateLimitedLoginSurfacesMessage() async {
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
            $0.authClient.login = { _, _, _ in throw AuthClientError.rateLimited }
            $0.continuousClock = ImmediateClock()
        }

        await store.send(.continueButtonTapped) {
            $0.isSubmitting = true
        }
        await store.receive(\.submitFailed) {
            $0.isSubmitting = false
            $0.errorMessage = L10n.Login.errorRateLimited
            // A rate limit says nothing about which field was wrong — unlike
            // `.invalidCredentials`, it must not red-border the fields.
            $0.invalidFieldsScope = nil
        }
        await store.receive(\.clearErrorMessage) {
            $0.errorMessage = nil
        }
    }

    @Test("edge case: whitespace-only password is rejected by the disabled Continue button, but the reducer itself has no client-side password check — a blank/whitespace password still reaches the server, which is the sole source of truth on password validity")
    func whitespaceOnlyPasswordStillReachesServer() async {
        let store = TestStore(
            initialState: LoginFormFeature.State(
                host: "nextexplorer.example.com",
                identifier: "phillip@example.com",
                password: "   ",
                authStatus: AuthStatus(localEnabled: true, oidcEnabled: false)
            )
        ) {
            LoginFormFeature()
        } withDependencies: {
            $0.authClient.login = { [user] _, _, password in
                #expect(password == "   ")
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

    @Test("edge case: rapid double-submit cancels the first in-flight login instead of firing two network calls")
    func doubleSubmitCancelsFirstInFlightLogin() async {
        let clock = TestClock()
        // Each `authClient.login` invocation records its own call index into `completedCalls`
        // only if it runs to completion — a cancelled invocation never appends. Two flat booleans
        // would be indistinguishable between the first and second call since both share this one
        // mock closure.
        let nextCallIndex = LockIsolated(0)
        let completedCalls = LockIsolated<[Int]>([])
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
            $0.authClient.login = { [user] _, _, _ in
                let callIndex = nextCallIndex.withValue { count -> Int in
                    defer { count += 1 }
                    return count
                }
                try await clock.sleep(for: .seconds(5))
                completedCalls.withValue { $0.append(callIndex) }
                return user
            }
        }

        await store.send(.continueButtonTapped) {
            $0.isSubmitting = true
        }
        await clock.advance(by: .seconds(1))

        // Second tap before the first call resolves cancels it in favor of a fresh attempt.
        await store.send(.continueButtonTapped)

        await clock.advance(by: .seconds(10))
        await store.receive(\.submitSucceeded) {
            $0.isSubmitting = false
        }
        await store.receive(\.delegate)

        // Only the second call (index 1) ever reaches completion — the first was cancelled
        // mid-sleep and never appends.
        #expect(completedCalls.value == [1])
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
            $0.errorMessage = L10n.Login.errorIncomplete
        }

        // Well past the usual 4-second auto-dismiss — the message must still be showing.
        await clock.advance(by: .seconds(30))
        #expect(store.state.errorMessage == L10n.Login.errorIncomplete)
    }
}
