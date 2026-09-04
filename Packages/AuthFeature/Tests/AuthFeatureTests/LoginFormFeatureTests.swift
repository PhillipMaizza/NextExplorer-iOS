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

    @Test("edge case: a pasted path, query and fragment are dropped, keeping only host[:port]")
    func pathQueryFragmentStripped() {
        #expect(
            LoginFormFeature.normalizedURL(scheme: .https, host: "example.com/files/photos?sort=name#top")?
                .absoluteString == "https://example.com"
        )
        #expect(
            LoginFormFeature.normalizedURL(scheme: .http, host: "192.168.1.50:3000/inbox")?
                .absoluteString == "http://192.168.1.50:3000"
        )
    }

    @Test("edge case: a user:pass@ userinfo prefix is stripped, not carried into the request")
    func userinfoStripped() {
        #expect(
            LoginFormFeature.normalizedURL(scheme: .http, host: "admin:hunter2@box.local:3000")?
                .absoluteString == "http://box.local:3000"
        )
    }

    @Test("edge case: an out-of-range or non-numeric port is rejected outright")
    func invalidPortRejected() {
        #expect(LoginFormFeature.normalizedURL(scheme: .http, host: "box.local:99999") == nil)
        #expect(LoginFormFeature.normalizedURL(scheme: .http, host: "box.local:0") == nil)
        #expect(LoginFormFeature.normalizedURL(scheme: .http, host: "box.local:-1") == nil)
        #expect(LoginFormFeature.normalizedURL(scheme: .http, host: "box.local:abc") == nil)
    }

    @Test("edge case: gibberish that isn't a plausible host is rejected before any network call")
    func gibberishHostRejected() {
        for junk in ["!!!!", "..", "foo bar", "http://", "https://", "-lead.example.com", "exam ple.com"] {
            #expect(LoginFormFeature.normalizedURL(scheme: .https, host: junk) == nil, "\(junk) should be invalid")
        }
    }

    @Test("edge case: a bracketed IPv6 literal (with an optional port) is accepted; an unbracketed one is not")
    func ipv6HostHandling() {
        #expect(LoginFormFeature.normalizedURL(scheme: .http, host: "[::1]:3000")?.absoluteString == "http://[::1]:3000")
        #expect(LoginFormFeature.normalizedURL(scheme: .https, host: "[2001:db8::1]")?.absoluteString == "https://[2001:db8::1]")
        // Unbracketed IPv6 is ambiguous with the port separator — rejected rather than guessed.
        #expect(LoginFormFeature.normalizedURL(scheme: .https, host: "fe80::1") == nil)
    }

    @Test("edge case: plain hostnames, LAN single-labels and IPv4 all pass")
    func validHostsPass() {
        #expect(LoginFormFeature.normalizedURL(scheme: .https, host: "nextexplorer.example.com") != nil)
        #expect(LoginFormFeature.normalizedURL(scheme: .http, host: "nas") != nil)
        #expect(LoginFormFeature.normalizedURL(scheme: .http, host: "box.local:8080") != nil)
        #expect(LoginFormFeature.normalizedURL(scheme: .http, host: "192.168.1.50:3000") != nil)
    }

    // MARK: - monkey test (fuzz)

    @Test("monkey test: thousands of garbage server inputs never crash, and any URL that survives is clean")
    func normalizedURLFuzzing() {
        var rng = SplitMix64(seed: 0xC0FFEE_0027)
        for _ in 0..<4000 {
            let junk = FuzzStrings.random(using: &rng, maxLength: 60)
            for scheme in [LoginFormFeature.URLScheme.https, .http] {
                // The only hard requirement: this must not trap on any input.
                guard let url = LoginFormFeature.normalizedURL(scheme: scheme, host: junk) else { continue }
                // Anything that survives is a clean authority-only URL.
                #expect(url.scheme == scheme.rawValue)
                #expect(!(url.host ?? "").isEmpty, "host missing for \(junk.debugDescription)")
                #expect(url.path.isEmpty, "path leaked for \(junk.debugDescription): \(url.path)")
                #expect(url.query == nil, "query leaked for \(junk.debugDescription)")
                #expect(url.fragment == nil, "fragment leaked for \(junk.debugDescription)")
                #expect(url.user == nil && url.password == nil, "userinfo leaked for \(junk.debugDescription)")
                if let port = url.port { #expect((1...65535).contains(port), "bad port \(port) for \(junk.debugDescription)") }
            }
        }
    }

    // MARK: - field length caps

    @Test("edge case: a pathological paste into the fields is truncated, never stored whole")
    func fieldsAreLengthCapped() async {
        let store = TestStore(initialState: LoginFormFeature.State()) { LoginFormFeature() }
        store.exhaustivity = .off

        await store.send(.hostChanged(String(repeating: "a", count: 5000)))
        #expect(store.state.host.count == 2048)

        await store.send(.identifierChanged(String(repeating: "x", count: 5000)))
        #expect(store.state.identifier.count == 254)

        await store.send(.passwordChanged(String(repeating: "p", count: 5000)))
        #expect(store.state.password.count == 256)
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

    @Test("a server with only SSO enabled still advances to the credentials page (SSO button only)")
    func ssoOnlyServerAdvances() async {
        let store = TestStore(initialState: LoginFormFeature.State(host: "sso.example.com")) {
            LoginFormFeature()
        } withDependencies: {
            $0.authClient.fetchStatus = { _ in AuthStatus(localEnabled: false, oidcEnabled: true) }
            $0.continuousClock = ImmediateClock()
        }

        await store.send(.testConnectionButtonTapped) { $0.connectionPhase = .testing }
        await store.receive(\.testConnectionResponse.success) {
            $0.connectionPhase = .success
            $0.authStatus = AuthStatus(localEnabled: false, oidcEnabled: true)
        }
        await store.receive(\.advanceToCredentials) {
            $0.currentPage = .credentials
        }
    }

    @Test("a server with no auth methods at all surfaces a readable message")
    func noAuthMethodsEnabled() async {
        let store = TestStore(initialState: LoginFormFeature.State(host: "nextexplorer.example.com")) {
            LoginFormFeature()
        } withDependencies: {
            $0.authClient.fetchStatus = { _ in AuthStatus(localEnabled: false, oidcEnabled: false) }
            $0.continuousClock = ImmediateClock()
        }

        await store.send(.testConnectionButtonTapped) { $0.connectionPhase = .testing }
        await store.receive(\.testConnectionResponse.success) {
            $0.connectionPhase = .failure
            $0.authStatus = AuthStatus(localEnabled: false, oidcEnabled: false)
            $0.errorMessage = L10n.Login.errorNoAuthMethods
        }
        await store.receive(\.revertToIdle) {
            $0.connectionPhase = .idle
        }
        await store.receive(\.clearErrorMessage) {
            $0.errorMessage = nil
        }
    }

    @Test("SSO happy path: tapping the SSO button runs the web flow and delegates authentication")
    func ssoButtonAuthenticates() async {
        let user = User(id: "sso-1", username: "ssouser", email: "sso@example.com", roles: ["user"])
        let store = TestStore(
            initialState: LoginFormFeature.State(
                currentPage: .credentials,
                connectionPhase: .success,
                host: "sso.example.com",
                authStatus: AuthStatus(localEnabled: false, oidcEnabled: true)
            )
        ) {
            LoginFormFeature()
        } withDependencies: {
            $0.authClient.loginOIDC = { [user] _ in user }
            $0.continuousClock = ImmediateClock()
        }

        await store.send(.ssoButtonTapped) { $0.isAuthenticatingOIDC = true }
        await store.receive(\.oidcResponse) { $0.isAuthenticatingOIDC = false }
        await store.receive(\.delegate)
    }

    @Test("SSO cancel: dismissing the web sheet clears the in-flight flag with no error banner")
    func ssoButtonCancelled() async {
        let store = TestStore(
            initialState: LoginFormFeature.State(
                currentPage: .credentials,
                connectionPhase: .success,
                host: "sso.example.com",
                authStatus: AuthStatus(localEnabled: false, oidcEnabled: true)
            )
        ) {
            LoginFormFeature()
        } withDependencies: {
            $0.authClient.loginOIDC = { _ in throw AuthClientError.oidcCancelled }
            $0.continuousClock = ImmediateClock()
        }

        await store.send(.ssoButtonTapped) { $0.isAuthenticatingOIDC = true }
        await store.receive(\.oidcResponse) { $0.isAuthenticatingOIDC = false }
    }

    @Test("SSO failure: a failed web flow surfaces the SSO error message, then clears it")
    func ssoButtonFailure() async {
        let store = TestStore(
            initialState: LoginFormFeature.State(
                currentPage: .credentials,
                connectionPhase: .success,
                host: "sso.example.com",
                authStatus: AuthStatus(localEnabled: false, oidcEnabled: true)
            )
        ) {
            LoginFormFeature()
        } withDependencies: {
            $0.authClient.loginOIDC = { _ in throw AuthClientError.oidcFailed("boom") }
            $0.continuousClock = ImmediateClock()
        }

        await store.send(.ssoButtonTapped) { $0.isAuthenticatingOIDC = true }
        await store.receive(\.oidcResponse) {
            $0.isAuthenticatingOIDC = false
            $0.errorMessage = L10n.Login.errorSso
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
            $0.continuousClock = ImmediateClock()
        }

        await store.send(.continueButtonTapped) {
            $0.submitPhase = .submitting
        }
        await store.receive(\.submitSucceeded) {
            $0.submitPhase = .success
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
            $0.submitPhase = .submitting
        }
        await store.receive(\.submitFailed) {
            $0.submitPhase = .failure
            $0.errorMessage = L10n.Login.errorInvalidCredentials
            $0.invalidFieldsScope = .identifierAndPassword
        }
        await store.receive(\.revertSubmitToIdle) {
            $0.submitPhase = .idle
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
            $0.submitPhase = .submitting
        }
        await store.receive(\.submitFailed) {
            $0.submitPhase = .failure
            $0.errorMessage = L10n.Login.errorRateLimited
            // A rate limit says nothing about which field was wrong — unlike
            // `.invalidCredentials`, it must not red-border the fields.
            $0.invalidFieldsScope = nil
        }
        await store.receive(\.revertSubmitToIdle) {
            $0.submitPhase = .idle
        }
        await store.receive(\.clearErrorMessage) {
            $0.errorMessage = nil
        }
    }

    @Test("unexpected error: a 5xx server status surfaces a server-problem message with the code, not a decode/address error")
    func serverErrorStatusSurfacesMessage() async {
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
            $0.authClient.login = { _, _, _ in throw AuthClientError.server(statusCode: 503) }
            $0.continuousClock = ImmediateClock()
        }

        await store.send(.continueButtonTapped) {
            $0.submitPhase = .submitting
        }
        await store.receive(\.submitFailed) {
            $0.submitPhase = .failure
            $0.errorMessage = L10n.Login.errorServer(503)
            // A server-side fault says nothing about which credential field was wrong.
            $0.invalidFieldsScope = nil
        }
        await store.receive(\.revertSubmitToIdle) {
            $0.submitPhase = .idle
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
            $0.continuousClock = ImmediateClock()
        }

        await store.send(.continueButtonTapped) {
            $0.submitPhase = .submitting
        }
        await store.receive(\.submitSucceeded) {
            $0.submitPhase = .success
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
            $0.continuousClock = clock
        }

        await store.send(.continueButtonTapped) {
            $0.submitPhase = .submitting
        }
        await clock.advance(by: .seconds(1))

        // Second tap before the first call resolves cancels it in favor of a fresh attempt.
        await store.send(.continueButtonTapped)

        await clock.advance(by: .seconds(10))
        await store.receive(\.submitSucceeded) {
            $0.submitPhase = .success
        }
        await clock.advance(by: .seconds(1))
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
            $0.submitPhase = .submitting
        }
        await clock.advance(by: .seconds(0.25))
        await store.receive(\.submitFailed) {
            $0.submitPhase = .failure
            $0.errorMessage = L10n.Login.errorIncomplete
        }
        // The button still re-expands so the user can retry — only the message is sticky.
        await clock.advance(by: .seconds(1))
        await store.receive(\.revertSubmitToIdle) {
            $0.submitPhase = .idle
        }

        // Well past the usual 4-second auto-dismiss — the message must still be showing.
        await clock.advance(by: .seconds(30))
        #expect(store.state.errorMessage == L10n.Login.errorIncomplete)
    }
}
