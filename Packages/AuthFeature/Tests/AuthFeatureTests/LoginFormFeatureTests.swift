import AuthClient
@testable import AuthFeature
import ComposableArchitecture
import CoreModels
import Foundation
import Localization
import Testing
import TestUtils

@MainActor
@Suite("LoginFormFeature")
struct LoginFormFeatureTests {
    private typealias Support = LoginFormTestSupport
    private typealias Store = LoginFormTestSupport.Store

    private let user = User(id: "1", username: "phillip", email: nil, roles: [])

    /// A form that was tested, signed in on the second factor page and then failed, with every field
    /// a reset has to clear set to something.
    private var dirtyState: LoginFormFeature.State {
        LoginFormFeature.State(
            currentPage: .secondFactor,
            connectionPhase: .success,
            host: Support.host,
            code: "123456",
            codeMode: .recovery,
            submitPhase: .failure,
            oidcPhase: .success,
            errorMessage: "old",
            invalidFieldsScope: .identifierAndPassword,
            authStatus: Support.passwordOnly
        )
    }

    /// Waits out the failure beat and the error dismissal of a failed connection test.
    private func expireConnectionError(_ store: Store, clock: TestClock<Duration>) async {
        await clock.advance(by: .seconds(1))
        await store.receive(\.revertToIdle) { $0.connectionPhase = .idle }
        await clock.advance(by: .seconds(3))
        await store.receive(\.clearErrorMessage) { $0.errorMessage = nil }
    }

    // MARK: - URL normalization

    struct AcceptedAddress: Sendable {
        let scheme: LoginFormFeature.URLScheme
        let typed: String
        let expected: String
    }

    @Test(
        "A typed address is reduced to scheme, host and port only",
        arguments: [
            AcceptedAddress(scheme: .https, typed: "nextexplorer.example.com", expected: "https://nextexplorer.example.com"),
            AcceptedAddress(scheme: .https, typed: "nextexplorer.example.com///", expected: "https://nextexplorer.example.com"),
            AcceptedAddress(scheme: .http, typed: "  192.168.1.50:3000  ", expected: "http://192.168.1.50:3000"),
            AcceptedAddress(scheme: .http, typed: "https://nextexplorer.example.com", expected: "http://nextexplorer.example.com"),
            AcceptedAddress(scheme: .https, typed: "example.com/files/photos?sort=name#top", expected: "https://example.com"),
            AcceptedAddress(scheme: .http, typed: "192.168.1.50:3000/inbox", expected: "http://192.168.1.50:3000"),
            AcceptedAddress(scheme: .http, typed: "admin:hunter2@box.local:3000", expected: "http://box.local:3000"),
            AcceptedAddress(scheme: .http, typed: "[::1]:3000", expected: "http://[::1]:3000"),
            AcceptedAddress(scheme: .https, typed: "[2001:db8::1]", expected: "https://[2001:db8::1]"),
            AcceptedAddress(scheme: .http, typed: "nas", expected: "http://nas"),
            AcceptedAddress(scheme: .http, typed: "box.local:8080", expected: "http://box.local:8080"),
        ]
    )
    func normalizedURLAcceptsAndReduces(_ address: AcceptedAddress) {
        #expect(LoginFormFeature.normalizedURL(scheme: address.scheme, host: address.typed)?.absoluteString == address.expected)
    }

    @Test(
        "An address that is not a plausible server is rejected before any network call",
        arguments: [
            "   ", "box.local:99999", "box.local:0", "box.local:-1", "box.local:abc", "!!!!", "..", "foo bar",
            "http://", "https://", "-lead.example.com", "exam ple.com", "fe80::1",
        ]
    )
    func normalizedURLRejects(_ typed: String) {
        #expect(LoginFormFeature.normalizedURL(scheme: .https, host: typed) == nil)
    }

    @Test("monkey test: thousands of garbage server inputs never crash, and any URL that survives is clean")
    func normalizedURLFuzzing() {
        var rng = SplitMix64(seed: 0xC0FFEE_0027)
        for _ in 0 ..< 4000 {
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
                if let port = url.port {
                    #expect((1 ... 65535).contains(port), "bad port \(port) for \(junk.debugDescription)")
                }
            }
        }
    }

    // MARK: - Field length caps

    @Test("A pathological paste into the fields is truncated, never stored whole")
    func fieldsAreLengthCapped() async {
        let store = Support.makeStore(LoginFormFeature.State(), clock: TestClock())

        await store.send(.hostChanged(String(repeating: "a", count: 5000))) {
            $0.host = String(repeating: "a", count: 2048)
        }
        await store.send(.identifierChanged(String(repeating: "x", count: 5000))) {
            $0.identifier = String(repeating: "x", count: 254)
        }
        await store.send(.passwordChanged(String(repeating: "p", count: 5000))) {
            $0.password = String(repeating: "p", count: 256)
        }
    }

    // MARK: - Testing the connection

    struct ConnectCase: Sendable {
        let host: String
        let status: AuthStatus
        let requestedURL: String
    }

    @Test(
        "A server with a sign in method shows the checkmark, then advances to the credentials page",
        arguments: [
            ConnectCase(host: "nextexplorer.example.com", status: AuthStatus(localEnabled: true, oidcEnabled: false), requestedURL: "https://nextexplorer.example.com"),
            ConnectCase(host: "sso.example.com", status: AuthStatus(localEnabled: false, oidcEnabled: true), requestedURL: "https://sso.example.com"),
            ConnectCase(host: "both.example.com", status: AuthStatus(localEnabled: true, oidcEnabled: true), requestedURL: "https://both.example.com"),
        ]
    )
    func connectionAdvancesToCredentials(_ testCase: ConnectCase) async {
        let clock = TestClock()
        let requested = LockIsolated<[String]>([])
        let store = Support.makeStore(LoginFormFeature.State(host: testCase.host), clock: clock) { [status = testCase.status] in
            $0.authClient.fetchStatus = { url in
                requested.withValue { $0.append(url.absoluteString) }
                return status
            }
        }

        await store.send(.testConnectionButtonTapped) { $0.connectionPhase = .testing }
        await clock.advance(by: .seconds(0.25))
        await store.receive(\.testConnectionResponse.success) {
            $0.connectionPhase = .success
            $0.authStatus = testCase.status
        }
        await clock.advance(by: .seconds(0.5))
        await store.receive(\.advanceToCredentials) { $0.currentPage = .credentials }

        #expect(requested.value == [testCase.requestedURL])
    }

    @Test("An empty host never calls the network, shows the invalid address message, then clears it")
    func emptyHostNeverCallsNetwork() async {
        let clock = TestClock()
        let calls = LockIsolated(0)
        let store = Support.makeStore(LoginFormFeature.State(), clock: clock) {
            $0.authClient.fetchStatus = { _ in
                calls.withValue { $0 += 1 }
                return AuthStatus(localEnabled: false, oidcEnabled: false)
            }
        }

        await store.send(.testConnectionButtonTapped) {
            $0.connectionPhase = .failure
            $0.errorMessage = L10n.Login.errorInvalidServer
        }
        await expireConnectionError(store, clock: clock)

        #expect(calls.value == 0)
    }

    @Test("A server with no sign in method at all shows a readable message, then clears it")
    func noAuthMethodsEnabled() async {
        let clock = TestClock()
        let noMethods = AuthStatus(localEnabled: false, oidcEnabled: false)
        let store = Support.makeStore(LoginFormFeature.State(host: Support.host), clock: clock) {
            $0.authClient.fetchStatus = { _ in noMethods }
        }

        await store.send(.testConnectionButtonTapped) { $0.connectionPhase = .testing }
        await clock.advance(by: .seconds(0.25))
        await store.receive(\.testConnectionResponse.success) {
            $0.connectionPhase = .failure
            $0.authStatus = noMethods
            $0.errorMessage = L10n.Login.errorNoAuthMethods
        }
        await expireConnectionError(store, clock: clock)
    }

    @Test("A failed connection test shows the unreachable message and clears it exactly 4 seconds after it appeared")
    func connectionErrorDismissesAfterFourSeconds() async {
        let clock = TestClock()
        let store = Support.makeStore(LoginFormFeature.State(host: Support.host), clock: clock) {
            $0.authClient.fetchStatus = { _ in throw AuthClientError.network("offline") }
        }

        await store.send(.testConnectionButtonTapped) { $0.connectionPhase = .testing }
        await clock.advance(by: .seconds(0.25))
        await store.receive(\.testConnectionResponse.failure) {
            $0.connectionPhase = .failure
            $0.errorMessage = L10n.Login.errorUnreachable
        }
        await clock.advance(by: .seconds(1))
        await store.receive(\.revertToIdle) { $0.connectionPhase = .idle }

        // 3.999 seconds after the message appeared nothing has fired: sending an action while a
        // received action is still unhandled would fail the test.
        await clock.advance(by: .milliseconds(2999))
        await store.send(.togglePasswordVisibility) { $0.isPasswordVisible = true }
        await clock.advance(by: .milliseconds(1))
        await store.receive(\.clearErrorMessage) { $0.errorMessage = nil }
    }

    // MARK: - Typing the address

    struct SchemeCase: Sendable {
        let initial: LoginFormFeature.URLScheme
        let typed: String
        let expected: LoginFormFeature.URLScheme
    }

    @Test(
        "The scheme picker follows what is typed: a digit means http, a hostname means https, a typed prefix wins",
        arguments: [
            SchemeCase(initial: .https, typed: "192.168.1.50:3000", expected: .http),
            SchemeCase(initial: .http, typed: "nextexplorer.example.com", expected: .https),
            SchemeCase(initial: .https, typed: "http://box.local", expected: .http),
            SchemeCase(initial: .http, typed: "https://box.local", expected: .https),
            SchemeCase(initial: .https, typed: "  HTTP://box.local", expected: .http),
        ]
    )
    func schemeFollowsHost(_ testCase: SchemeCase) async {
        let store = Support.makeStore(LoginFormFeature.State(scheme: testCase.initial), clock: TestClock())

        await store.send(.hostChanged(testCase.typed)) {
            $0.host = testCase.typed
            $0.scheme = testCase.expected
        }
    }

    @Test("A manual scheme pick sticks while typing, until the field is cleared")
    func manualSchemePickSticks() async {
        let store = Support.makeStore(LoginFormFeature.State(), clock: TestClock())

        // The user forces http for a LAN hostname.
        await store.send(.schemeChanged(.http)) {
            $0.scheme = .http
            $0.schemeWasSetByUser = true
        }
        await store.send(.hostChanged("nas")) { $0.host = "nas" }
        await store.send(.hostChanged("nas.local")) { $0.host = "nas.local" }

        // Clearing the field drops the override, so inference takes over again.
        await store.send(.hostChanged("")) {
            $0.host = ""
            $0.schemeWasSetByUser = false
        }
        await store.send(.hostChanged("example.com")) {
            $0.host = "example.com"
            $0.scheme = .https
        }
    }

    @Test("regression: picking https after typing an IP keeps the address")
    func switchingSchemeKeepsHost() async {
        let store = Support.makeStore(LoginFormFeature.State(), clock: TestClock())

        await store.send(.hostChanged("192.168.1.187:3662")) {
            $0.host = "192.168.1.187:3662"
            $0.scheme = .http
        }
        await store.send(.schemeChanged(.https)) {
            $0.scheme = .https
            $0.schemeWasSetByUser = true
        }
        await store.send(.hostChanged("192.168.1.187:36621")) { $0.host = "192.168.1.187:36621" }
    }

    @Test("regression: a typed scheme prefix gives way to the picker")
    func switchingSchemeDropsTypedPrefix() async {
        let store = Support.makeStore(LoginFormFeature.State(), clock: TestClock())

        await store.send(.hostChanged("http://box.local:8080")) {
            $0.host = "http://box.local:8080"
            $0.scheme = .http
        }
        await store.send(.schemeChanged(.https)) {
            $0.host = "box.local:8080"
            $0.scheme = .https
            $0.schemeWasSetByUser = true
        }
    }

    struct ResetCase: Sendable {
        let action: LoginFormFeature.Action
        let expectedHost: String
    }

    @Test(
        "Editing the address or pressing back starts the handshake over",
        arguments: [
            ResetCase(action: .hostChanged("nextexplorer.example.com/changed"), expectedHost: "nextexplorer.example.com/changed"),
            ResetCase(action: .backButtonTapped, expectedHost: "nextexplorer.example.com"),
        ]
    )
    func addressEditOrBackResetsTheForm(_ testCase: ResetCase) async {
        let store = Support.makeStore(dirtyState, clock: TestClock())

        await store.send(testCase.action) {
            $0.host = testCase.expectedHost
            $0.currentPage = .server
            $0.connectionPhase = .idle
            $0.code = ""
            $0.codeMode = .authenticator
            $0.submitPhase = .idle
            $0.oidcPhase = .idle
            $0.errorMessage = nil
            $0.invalidFieldsScope = nil
            $0.authStatus = nil
        }
    }

    @Test("regression: the field reporting the same address again does not cancel a connection test")
    func unchangedHostKeepsTestRunning() async {
        let clock = TestClock()
        let gate = AsyncGate()
        let store = Support.makeStore(LoginFormFeature.State(host: Support.host), clock: clock) {
            $0.authClient.fetchStatus = { _ in
                try await gate.wait()
                return Support.passwordOnly
            }
        }

        await store.send(.testConnectionButtonTapped) { $0.connectionPhase = .testing }
        await store.send(.hostChanged(Support.host))

        gate.open()
        await clock.advance(by: .seconds(0.25))
        await store.receive(\.testConnectionResponse.success) {
            $0.connectionPhase = .success
            $0.authStatus = Support.passwordOnly
        }
        await clock.advance(by: .seconds(0.5))
        await store.receive(\.advanceToCredentials) { $0.currentPage = .credentials }
    }

    @Test("regression: changing the host cancels an in-flight test so a stale response cannot land later")
    func hostChangeCancelsInFlightTestConnection() async {
        let clock = TestClock()
        let store = Support.makeStore(LoginFormFeature.State(host: "old.example.com"), clock: clock) {
            $0.authClient.fetchStatus = { _ in Support.passwordOnly }
        }

        await store.send(.testConnectionButtonTapped) { $0.connectionPhase = .testing }
        await store.send(.hostChanged("new.example.com")) {
            $0.host = "new.example.com"
            $0.connectionPhase = .idle
        }

        // The effect was cancelled, not just ignored: a late response or auto advance would be an
        // unhandled received action and fail the finish.
        await clock.advance(by: .seconds(5))
        await store.finish()
    }

    // MARK: - Single sign on

    @Test("Tapping the SSO button runs the web flow, shows the success beat and delegates authentication")
    func ssoButtonAuthenticates() async throws {
        let ssoUser = User(id: "sso-1", username: "ssouser", email: "sso@example.com", roles: ["user"])
        let clock = TestClock()
        let requested = LockIsolated<[String]>([])
        let store = Support.makeStore(
            LoginFormFeature.State(
                currentPage: .credentials,
                connectionPhase: .success,
                host: "sso.example.com",
                authStatus: AuthStatus(localEnabled: false, oidcEnabled: true)
            ),
            clock: clock
        ) {
            $0.authClient.loginOIDC = { url in
                requested.withValue { $0.append(url.absoluteString) }
                return ssoUser
            }
        }

        await store.send(.ssoButtonTapped) { $0.oidcPhase = .authenticating }
        await store.receive(\.oidcResponse) { $0.oidcPhase = .success }
        await clock.advance(by: .seconds(0.5))
        await store.receive(.delegate(.authenticated(ssoUser, try Support.url("https://sso.example.com"))))

        #expect(requested.value == ["https://sso.example.com"])
    }

    struct SSOFailureCase: Sendable {
        let error: AuthClientError
        let message: String?
    }

    @Test(
        "A dismissed web sheet leaves no error banner, a failed web flow shows the SSO error and then clears it",
        arguments: [
            SSOFailureCase(error: .oidcCancelled, message: nil),
            SSOFailureCase(error: .oidcFailed("boom"), message: L10n.Login.errorSso),
        ]
    )
    func ssoButtonFailure(_ testCase: SSOFailureCase) async {
        let clock = TestClock()
        let store = Support.makeStore(
            LoginFormFeature.State(
                currentPage: .credentials,
                connectionPhase: .success,
                host: "sso.example.com",
                authStatus: AuthStatus(localEnabled: false, oidcEnabled: true)
            ),
            clock: clock
        ) {
            $0.authClient.loginOIDC = { [error = testCase.error] _ in throw error }
        }

        await store.send(.ssoButtonTapped) { $0.oidcPhase = .authenticating }
        await store.receive(\.oidcResponse) {
            $0.oidcPhase = .idle
            $0.errorMessage = testCase.message
        }
        if testCase.message != nil {
            await clock.advance(by: .seconds(4))
            await store.receive(\.clearErrorMessage) { $0.errorMessage = nil }
        }
        await store.finish()
    }

    // MARK: - Password sign in

    struct LoginCase: Sendable {
        let identifier: String
        let password: String
        let sentIdentifier: String
        let sentPassword: String
    }

    struct LoginCall: Equatable, Sendable {
        let url: String
        let identifier: String
        let password: String
    }

    @Test(
        "Continue trims the identifier and sends the password untouched, then delegates authentication",
        arguments: [
            LoginCase(identifier: "  phillip@example.com  ", password: "hunter2", sentIdentifier: "phillip@example.com", sentPassword: "hunter2"),
            LoginCase(identifier: "phillip", password: "hunter2", sentIdentifier: "phillip", sentPassword: "hunter2"),
            // The reducer has no client side password check: the server decides what a valid password is.
            LoginCase(identifier: "phillip@example.com", password: "   ", sentIdentifier: "phillip@example.com", sentPassword: "   "),
        ]
    )
    func localLoginSendsTheCredentials(_ testCase: LoginCase) async throws {
        let clock = TestClock()
        let calls = LockIsolated<[LoginCall]>([])
        let store = Support.makeStore(
            Support.credentialsState(identifier: testCase.identifier, password: testCase.password),
            clock: clock
        ) { [user] in
            $0.authClient.login = { url, identifier, password in
                calls.withValue { $0.append(LoginCall(url: url.absoluteString, identifier: identifier, password: password)) }
                return user
            }
        }

        await store.send(.continueButtonTapped) { $0.submitPhase = .submitting }
        try await Support.finishSuccessfulSubmit(store, clock: clock, user: user)

        #expect(calls.value == [LoginCall(url: Support.serverURL, identifier: testCase.sentIdentifier, password: testCase.sentPassword)])
    }

    struct IgnoredContinueCase: Sendable {
        let host: String
        let authStatus: AuthStatus?
    }

    @Test(
        "Continue does nothing unless password sign in was confirmed for a valid address",
        arguments: [
            IgnoredContinueCase(host: "nextexplorer.example.com", authStatus: nil),
            IgnoredContinueCase(host: "nextexplorer.example.com", authStatus: AuthStatus(localEnabled: false, oidcEnabled: true)),
            IgnoredContinueCase(host: "not a host", authStatus: AuthStatus(localEnabled: true, oidcEnabled: false)),
        ]
    )
    func continueIsIgnoredWithoutConfirmedPasswordSignIn(_ testCase: IgnoredContinueCase) async {
        let calls = LockIsolated(0)
        let state = LoginFormFeature.State(host: testCase.host, identifier: "phillip", password: "x", authStatus: testCase.authStatus)
        let store = Support.makeStore(state, clock: TestClock()) { [user] in
            $0.authClient.login = { _, _, _ in
                calls.withValue { $0 += 1 }
                return user
            }
        }

        await store.send(.continueButtonTapped)

        #expect(calls.value == 0)
        #expect(store.state.diagnostics.entries.isEmpty)
    }

    struct LoginFailureCase: Sendable {
        let error: AuthClientError
        let message: String
        let scope: LoginFormFeature.InvalidFieldScope?
    }

    @Test(
        "A refused sign in shows its message, red borders only when the credentials are wrong, then clears itself",
        arguments: [
            LoginFailureCase(error: .invalidCredentials, message: L10n.Login.errorInvalidCredentials, scope: .identifierAndPassword),
            // A rate limit or a server fault says nothing about which field was wrong.
            LoginFailureCase(error: .rateLimited, message: L10n.Login.errorRateLimited, scope: nil),
            LoginFailureCase(error: .server(statusCode: 503), message: L10n.Login.errorServer(503), scope: nil),
        ]
    )
    func loginFailureShowsMessage(_ testCase: LoginFailureCase) async {
        let clock = TestClock()
        let store = Support.makeStore(Support.credentialsState(identifier: "phillip@example.com"), clock: clock) {
            $0.authClient.login = { [error = testCase.error] _, _, _ in throw error }
        }

        await store.send(.continueButtonTapped) { $0.submitPhase = .submitting }
        await clock.advance(by: .seconds(0.25))
        await store.receive(\.submitFailed) {
            $0.submitPhase = .failure
            $0.errorMessage = testCase.message
            $0.invalidFieldsScope = testCase.scope
        }
        await Support.expireSubmitError(store, clock: clock)
    }

    @Test("regression: sessionCookieMissing does not auto dismiss, because it is a real failure and not a typo to retry")
    func sessionCookieMissingDoesNotAutoDismiss() async {
        let clock = TestClock()
        let store = Support.makeStore(Support.credentialsState(identifier: "phillip@example.com"), clock: clock) {
            $0.authClient.login = { _, _, _ in throw AuthClientError.sessionCookieMissing }
        }

        await store.send(.continueButtonTapped) { $0.submitPhase = .submitting }
        await clock.advance(by: .seconds(0.25))
        await store.receive(\.submitFailed) {
            $0.submitPhase = .failure
            $0.errorMessage = L10n.Login.errorIncomplete
        }
        // The button still re-expands so the user can retry: only the message is sticky.
        await clock.advance(by: .seconds(1))
        await store.receive(\.revertSubmitToIdle) { $0.submitPhase = .idle }

        // Well past the usual 4 second dismissal nothing fires: a clear would be an unhandled action.
        await clock.advance(by: .seconds(30))
        await store.finish()
    }

    @Test("A second Continue while the first sign in is in flight cancels it, so only the second call completes")
    func doubleSubmitCancelsFirstInFlightLogin() async throws {
        let clock = TestClock()
        let gate = AsyncGate()
        let startedCalls = LockIsolated(0)
        let completedCalls = LockIsolated<[Int]>([])
        let store = Support.makeStore(Support.credentialsState(identifier: "phillip@example.com"), clock: clock) { [user] in
            $0.authClient.login = { _, _, _ in
                let callIndex = startedCalls.withValue { count -> Int in
                    defer { count += 1 }
                    return count
                }
                try await gate.wait()
                completedCalls.withValue { $0.append(callIndex) }
                return user
            }
        }

        await store.send(.continueButtonTapped) { $0.submitPhase = .submitting }
        // The first call is now parked on the gate.
        await clock.advance(by: .seconds(0.25))

        await store.send(.continueButtonTapped)
        gate.open()
        try await Support.finishSuccessfulSubmit(store, clock: clock, user: user)

        #expect(startedCalls.value == 2)
        #expect(completedCalls.value == [1])
    }
}
