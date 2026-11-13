import AuthClient
@testable import AuthFeature
import ComposableArchitecture
import CoreModels
import Foundation
import Localization
import Testing
import TestUtils

@MainActor
@Suite("LoginFormFeature sign in")
struct LoginFormSignInTests {
    private typealias Support = LoginFormTestSupport
    private typealias Store = LoginFormTestSupport.Store

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
                host: LoginFormConstants.ssoHost,
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
        try await store.receive(.delegate(.authenticated(ssoUser, Support.url(LoginFormConstants.ssoURLString))))

        #expect(requested.value == [LoginFormConstants.ssoURLString])
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
                host: LoginFormConstants.ssoHost,
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
            LoginCase(
                identifier: "  phillip@example.com  ",
                password: TestAccount.password,
                sentIdentifier: LoginFormConstants.phillipEmail,
                sentPassword: TestAccount.password
            ),
            LoginCase(
                identifier: TestAccount.username,
                password: TestAccount.password,
                sentIdentifier: TestAccount.username,
                sentPassword: TestAccount.password
            ),
            // The reducer has no client side password check: the server decides what a valid password is.
            LoginCase(
                identifier: LoginFormConstants.phillipEmail,
                password: TestValue.blank,
                sentIdentifier: LoginFormConstants.phillipEmail,
                sentPassword: TestValue.blank
            ),
        ]
    )
    func localLoginSendsTheCredentials(_ testCase: LoginCase) async throws {
        let clock = TestClock()
        let calls = LockIsolated<[LoginCall]>([])
        let store = Support.makeStore(
            Support.credentialsState(identifier: testCase.identifier, password: testCase.password),
            clock: clock
        ) {
            $0.authClient.login = { url, identifier, password in
                calls.withValue { $0.append(LoginCall(
                    url: url.absoluteString,
                    identifier: identifier,
                    password: password
                )) }
                return Support.user
            }
        }

        await store.send(.continueButtonTapped) { $0.submitPhase = .submitting }
        try await Support.finishSuccessfulSubmit(store, clock: clock, user: Support.user)

        #expect(calls.value == [LoginCall(
            url: Support.serverURL,
            identifier: testCase.sentIdentifier,
            password: testCase.sentPassword
        )])
    }

    struct IgnoredContinueCase: Sendable {
        let host: String
        let authStatus: AuthStatus?
    }

    @Test(
        "Continue does nothing unless password sign in was confirmed for a valid address",
        arguments: [
            IgnoredContinueCase(host: TestHost.nextExplorer, authStatus: nil),
            IgnoredContinueCase(
                host: TestHost.nextExplorer,
                authStatus: AuthStatus(localEnabled: false, oidcEnabled: true)
            ),
            IgnoredContinueCase(
                host: AuthFeatureTestValue.invalidHost,
                authStatus: AuthStatus(localEnabled: true, oidcEnabled: false)
            ),
        ]
    )
    func continueIsIgnoredWithoutConfirmedPasswordSignIn(_ testCase: IgnoredContinueCase) async {
        let calls = LockIsolated(0)
        let state = LoginFormFeature.State(
            host: testCase.host,
            identifier: TestAccount.username,
            password: "x",
            authStatus: testCase.authStatus
        )
        let store = Support.makeStore(state, clock: TestClock()) {
            $0.authClient.login = { _, _, _ in
                calls.withValue { $0 += 1 }
                return Support.user
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
            LoginFailureCase(
                error: .invalidCredentials,
                message: L10n.Login.errorInvalidCredentials,
                scope: .identifierAndPassword
            ),
            // A rate limit or a server fault says nothing about which field was wrong.
            LoginFailureCase(error: .rateLimited, message: L10n.Login.errorRateLimited, scope: nil),
            LoginFailureCase(error: .server(statusCode: 503), message: L10n.Login.errorServer(503), scope: nil),
        ]
    )
    func loginFailureShowsMessage(_ testCase: LoginFailureCase) async {
        let clock = TestClock()
        let store = Support.makeStore(
            Support.credentialsState(identifier: LoginFormConstants.phillipEmail),
            clock: clock
        ) {
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

    @Test(
        "regression: sessionCookieMissing does not auto dismiss, because it is a real failure and not a typo to retry"
    )
    func sessionCookieMissingDoesNotAutoDismiss() async {
        let clock = TestClock()
        let store = Support.makeStore(
            Support.credentialsState(identifier: LoginFormConstants.phillipEmail),
            clock: clock
        ) {
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
        let store = Support.makeStore(
            Support.credentialsState(identifier: LoginFormConstants.phillipEmail),
            clock: clock
        ) {
            $0.authClient.login = { _, _, _ in
                let callIndex = startedCalls.withValue { count -> Int in
                    defer { count += 1 }
                    return count
                }
                try await gate.wait()
                completedCalls.withValue { $0.append(callIndex) }
                return Support.user
            }
        }

        await store.send(.continueButtonTapped) { $0.submitPhase = .submitting }
        // The first call is now parked on the gate.
        await clock.advance(by: .seconds(0.25))

        await store.send(.continueButtonTapped)
        gate.open()
        try await Support.finishSuccessfulSubmit(store, clock: clock, user: Support.user)

        #expect(startedCalls.value == 2)
        #expect(completedCalls.value == [1])
    }
}
