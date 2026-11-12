import AuthClient
@testable import AuthFeature
import ComposableArchitecture
import CoreModels
import Foundation
import Localization
import Testing
import TestUtils

@MainActor
@Suite("LoginFormFeature second factor")
struct LoginSecondFactorTests {
    private typealias Support = LoginFormTestSupport
    private typealias Store = LoginFormTestSupport.Store

    private static let identifier = TestUser.asmith
    private static let password = TestAccount.password

    private let user = User(id: "1", username: TestUser.asmith, email: nil, roles: [])

    private func secondFactorState(
        code: String = "",
        mode: LoginFormFeature.CodeMode = .authenticator,
        submitPhase: LoginFormFeature.SubmitPhase = .idle
    ) -> LoginFormFeature.State {
        LoginFormFeature.State(
            currentPage: .secondFactor,
            host: Support.host,
            identifier: Self.identifier,
            password: Self.password,
            code: code,
            codeMode: mode,
            submitPhase: submitPhase,
            authStatus: Support.passwordOnly
        )
    }

    private func expectNoSecrets(in store: Store, extra: [String] = []) {
        let log = store.state.diagnostics.rendered(header: [])
        for secret in [Self.password, Self.identifier, Support.host] + extra {
            #expect(!log.contains(secret), "the log must not contain \(secret)")
        }
    }

    struct TOTPCall: Equatable, Sendable {
        let url: String
        let code: String
    }

    // MARK: - Asking for the code

    @Test("regression NXTIOS-0095: a right password on a 2FA account opens the code page and logs it without a problem")
    func secondFactorRequiredOpensCodePage() async {
        let clock = TestClock()
        let calls = LockIsolated<[String]>([])
        let store = Support.makeStore(Support.credentialsState(), clock: clock) {
            $0.authClient.login = { url, identifier, password in
                calls.withValue { $0.append("\(url.absoluteString)|\(identifier)|\(password)") }
                throw AuthClientError.secondFactorRequired
            }
        }

        await store.send(.continueButtonTapped) { $0.submitPhase = .submitting }
        await clock.advance(by: .seconds(0.25))
        await store.receive(\.secondFactorRequested) {
            $0.submitPhase = .idle
            $0.currentPage = .secondFactor
        }

        #expect(calls.value == ["https://nextexplorer.example.com|asmith|hunter2"])
        #expect(store.state.diagnostics.entries == [
            Support.entry("sign in: sending, name username shaped, 6 characters, password set"),
            Support.entry("sign in: password accepted, server asks for a second factor code"),
        ])
        #expect(!store.state.diagnostics.hasProblem)
    }

    // MARK: - Sending the code

    struct CodeSignInCase: Sendable {
        let mode: LoginFormFeature.CodeMode
        let typed: String
        let sentCode: String
        let sendingLog: String
    }

    @Test(
        "The trimmed code is sent as typed and the user is handed to the app",
        arguments: [
            CodeSignInCase(mode: .authenticator, typed: "  123456 ", sentCode: TestAccount.totpCode, sendingLog: "code: sending, 6 digits"),
            CodeSignInCase(mode: .recovery, typed: TestAccount.recoveryCode, sentCode: TestAccount.recoveryCode, sendingLog: "code: sending, other, 11 characters"),
            CodeSignInCase(mode: .recovery, typed: " 2HSMP-G9ZSJ ", sentCode: TestAccount.recoveryCode, sendingLog: "code: sending, other, 11 characters"),
        ]
    )
    func codeSignsIn(_ testCase: CodeSignInCase) async throws {
        let clock = TestClock()
        let calls = LockIsolated<[TOTPCall]>([])
        let store = Support.makeStore(secondFactorState(code: testCase.typed, mode: testCase.mode), clock: clock) { [user] in
            $0.authClient.loginTOTP = { url, code in
                calls.withValue { $0.append(TOTPCall(url: url.absoluteString, code: code)) }
                return user
            }
        }

        await store.send(.codeSubmitButtonTapped) { $0.submitPhase = .submitting }
        try await Support.finishSuccessfulSubmit(store, clock: clock, user: user)

        #expect(calls.value == [TOTPCall(url: Support.serverURL, code: testCase.sentCode)])
        #expect(store.state.diagnostics.entries == [
            Support.entry(testCase.sendingLog),
            Support.entry("sign in: signed in"),
        ])
    }

    struct CodeFailureCase: Sendable {
        let mode: LoginFormFeature.CodeMode
        let code: String
        let error: AuthClientError
        let message: String
        let page: LoginFormFeature.Page
        let expectedCode: String
        let expectedMode: LoginFormFeature.CodeMode
        let sendingLog: String
        let resultLog: String
    }

    @Test(
        "A refused code shows a readable message, keeps or clears what was typed, and the log says why",
        arguments: [
            // Six boxes of a wrong code are cleared, not left to erase one by one.
            CodeFailureCase(
                mode: .authenticator, code: "000000", error: .invalidCode, message: L10n.Login.errorInvalidCode,
                page: .secondFactor, expectedCode: "", expectedMode: .authenticator,
                sendingLog: "code: sending, 6 digits", resultLog: "code: code rejected by the server"
            ),
            // A wrong recovery code is kept, so a typo can be fixed.
            CodeFailureCase(
                mode: .recovery, code: "2HSMP-G9ZSX", error: .invalidCode, message: L10n.Login.errorInvalidCode,
                page: .secondFactor, expectedCode: "2HSMP-G9ZSX", expectedMode: .recovery,
                sendingLog: "code: sending, other, 11 characters", resultLog: "code: code rejected by the server"
            ),
            // A sign in the server no longer waits on sends the user back to the password page.
            CodeFailureCase(
                mode: .authenticator, code: "123456", error: .secondFactorExpired, message: L10n.Login.errorSecondFactorExpired,
                page: .credentials, expectedCode: "", expectedMode: .authenticator,
                sendingLog: "code: sending, 6 digits", resultLog: "code: server no longer has a sign in waiting for a code"
            ),
            CodeFailureCase(
                mode: .recovery, code: "2HSMP-G9ZSX", error: .secondFactorExpired, message: L10n.Login.errorSecondFactorExpired,
                page: .credentials, expectedCode: "", expectedMode: .authenticator,
                sendingLog: "code: sending, other, 11 characters", resultLog: "code: server no longer has a sign in waiting for a code"
            ),
            CodeFailureCase(
                mode: .authenticator, code: "123456", error: .rateLimited, message: L10n.Login.errorRateLimited,
                page: .secondFactor, expectedCode: TestAccount.totpCode, expectedMode: .authenticator,
                sendingLog: "code: sending, 6 digits", resultLog: "code: server answered 429, too many attempts or account locked"
            ),
            CodeFailureCase(
                mode: .authenticator, code: "123456", error: .network("offline"), message: L10n.Login.errorUnreachable,
                page: .secondFactor, expectedCode: TestAccount.totpCode, expectedMode: .authenticator,
                sendingLog: "code: sending, 6 digits", resultLog: "code: network error: offline"
            ),
        ]
    )
    func codeFailure(_ testCase: CodeFailureCase) async {
        let clock = TestClock()
        let store = Support.makeStore(secondFactorState(code: testCase.code, mode: testCase.mode), clock: clock) {
            $0.authClient.loginTOTP = { [error = testCase.error] _, _ in throw error }
        }

        await store.send(.codeSubmitButtonTapped) { $0.submitPhase = .submitting }
        await clock.advance(by: .seconds(0.25))
        await store.receive(\.submitFailed) {
            $0.submitPhase = .failure
            $0.errorMessage = testCase.message
            $0.currentPage = testCase.page
            $0.code = testCase.expectedCode
            $0.codeMode = testCase.expectedMode
        }
        await Support.expireSubmitError(store, clock: clock)

        #expect(store.state.diagnostics.entries == [
            Support.entry(testCase.sendingLog),
            Support.entry(testCase.resultLog, isProblem: true),
        ])
        #expect(store.state.password == Self.password)
    }

    struct BlockedSubmitCase: Sendable {
        let page: LoginFormFeature.Page
        let code: String
    }

    @Test(
        "A blank code, or a code submitted outside the code page, is never sent",
        arguments: [
            BlockedSubmitCase(page: .secondFactor, code: ""),
            BlockedSubmitCase(page: .secondFactor, code: TestValue.blank),
            BlockedSubmitCase(page: .secondFactor, code: "\n"),
            BlockedSubmitCase(page: .credentials, code: TestAccount.totpCode),
        ]
    )
    func blockedSubmitIsIgnored(_ testCase: BlockedSubmitCase) async {
        var state = secondFactorState(code: testCase.code)
        state.currentPage = testCase.page
        let calls = LockIsolated(0)
        let store = Support.makeStore(state, clock: TestClock()) { [user] in
            $0.authClient.loginTOTP = { _, _ in
                calls.withValue { $0 += 1 }
                return user
            }
        }

        await store.send(.codeSubmitButtonTapped)

        #expect(calls.value == 0)
        #expect(store.state.diagnostics.entries.isEmpty)
    }

    @Test("A second tap while the code is being checked does not send it twice")
    func doubleTapSendsOnce() async throws {
        let clock = TestClock()
        let calls = LockIsolated<[TOTPCall]>([])
        let store = Support.makeStore(secondFactorState(code: TestAccount.totpCode), clock: clock) { [user] in
            $0.authClient.loginTOTP = { url, code in
                calls.withValue { $0.append(TOTPCall(url: url.absoluteString, code: code)) }
                return user
            }
        }

        await store.send(.codeSubmitButtonTapped) { $0.submitPhase = .submitting }
        await store.send(.codeSubmitButtonTapped)
        try await Support.finishSuccessfulSubmit(store, clock: clock, user: user)

        #expect(calls.value == [TOTPCall(url: Support.serverURL, code: TestAccount.totpCode)])
    }

    // MARK: - The field

    struct CodeInput: Sendable {
        let mode: LoginFormFeature.CodeMode
        let typed: String
        let expected: String
    }

    @Test(
        "The authenticator field keeps ASCII digits only, capped at six, and a recovery code keeps its letters and dash, capped at 32",
        arguments: [
            CodeInput(mode: .authenticator, typed: "12a", expected: "12"),
            CodeInput(mode: .authenticator, typed: "12 34", expected: "1234"),
            CodeInput(mode: .authenticator, typed: "123-45", expected: "12345"),
            CodeInput(mode: .authenticator, typed: "abc", expected: ""),
            CodeInput(mode: .authenticator, typed: "\u{0663}\u{0664}5", expected: "5"),
            CodeInput(mode: .authenticator, typed: String(repeating: "1", count: 500), expected: "111111"),
            CodeInput(mode: .recovery, typed: TestAccount.recoveryCode, expected: TestAccount.recoveryCode),
            CodeInput(mode: .recovery, typed: String(repeating: "A", count: 500), expected: String(repeating: "A", count: 32)),
        ]
    )
    func codeFieldFiltersAndCaps(_ input: CodeInput) async {
        // A check already running keeps a sixth digit from submitting, so only the filter and cap are seen.
        // The field starts with a code already in it, so an input that filters down to nothing still changes it.
        let store = Support.makeStore(secondFactorState(code: "9", mode: input.mode, submitPhase: .submitting), clock: TestClock())

        await store.send(.codeChanged(input.typed)) { $0.code = input.expected }
    }

    @Test("The sixth digit sends the code without a tap")
    func sixthDigitSubmits() async throws {
        let clock = TestClock()
        let calls = LockIsolated<[TOTPCall]>([])
        let store = Support.makeStore(secondFactorState(), clock: clock) { [user] in
            $0.authClient.loginTOTP = { url, code in
                calls.withValue { $0.append(TOTPCall(url: url.absoluteString, code: code)) }
                return user
            }
        }

        await store.send(.codeChanged("12345")) { $0.code = "12345" }
        #expect(calls.value.isEmpty)

        await store.send(.codeChanged(TestAccount.totpCode)) { $0.code = TestAccount.totpCode }
        await store.receive(.codeSubmitButtonTapped) { $0.submitPhase = .submitting }
        try await Support.finishSuccessfulSubmit(store, clock: clock, user: user)

        #expect(calls.value == [TOTPCall(url: Support.serverURL, code: TestAccount.totpCode)])
    }

    struct NoAutoSubmitCase: Sendable {
        let mode: LoginFormFeature.CodeMode
        let phase: LoginFormFeature.SubmitPhase
        let typed: String
    }

    @Test(
        "Typing never sends a recovery code, and never sends a second check while one is running",
        arguments: [
            NoAutoSubmitCase(mode: .recovery, phase: .idle, typed: TestAccount.recoveryCode),
            NoAutoSubmitCase(mode: .authenticator, phase: .submitting, typed: TestAccount.totpCode),
        ]
    )
    func typingDoesNotSend(_ testCase: NoAutoSubmitCase) async {
        let calls = LockIsolated(0)
        let store = Support.makeStore(secondFactorState(mode: testCase.mode, submitPhase: testCase.phase), clock: TestClock()) { [user] in
            $0.authClient.loginTOTP = { _, _ in
                calls.withValue { $0 += 1 }
                return user
            }
        }

        await store.send(.codeChanged(testCase.typed)) { $0.code = testCase.typed }

        #expect(calls.value == 0)
    }

    @Test("The toggle swaps between the authenticator code and a recovery code, clearing what was typed and any error")
    func toggleCodeMode() async {
        var state = secondFactorState(code: "123")
        state.errorMessage = TestValue.outdated
        let store = Support.makeStore(state, clock: TestClock())

        await store.send(.toggleCodeModeTapped) {
            $0.codeMode = .recovery
            $0.code = ""
            $0.errorMessage = nil
        }
        await store.send(.toggleCodeModeTapped) { $0.codeMode = .authenticator }
    }

    @Test("Toggling the mode cancels the pending dismissal of the error it cleared")
    func toggleCancelsErrorDismissal() async {
        let clock = TestClock()
        let store = Support.makeStore(secondFactorState(code: TestAccount.invalidTotpCode), clock: clock) {
            $0.authClient.loginTOTP = { _, _ in throw AuthClientError.invalidCode }
        }

        await store.send(.codeSubmitButtonTapped) { $0.submitPhase = .submitting }
        await clock.advance(by: .seconds(0.25))
        await store.receive(\.submitFailed) {
            $0.submitPhase = .failure
            $0.errorMessage = L10n.Login.errorInvalidCode
            $0.code = ""
        }
        await store.send(.toggleCodeModeTapped) {
            $0.codeMode = .recovery
            $0.errorMessage = nil
        }
        await clock.advance(by: .seconds(1))
        await store.receive(\.revertSubmitToIdle) { $0.submitPhase = .idle }

        // The dismissal would be an unhandled received action and fail the finish.
        await clock.advance(by: .seconds(10))
        await store.finish()
    }

    // MARK: - Leaving the page

    @Test("Back from the code page returns to the password page, clears the code and keeps the password")
    func backReturnsToCredentials() async {
        var state = secondFactorState(code: "123", mode: .recovery, submitPhase: .failure)
        state.errorMessage = TestValue.outdated
        state.invalidFieldsScope = .identifierAndPassword
        let store = Support.makeStore(state, clock: TestClock())

        await store.send(.secondFactorBackButtonTapped) {
            $0.currentPage = .credentials
            $0.code = ""
            $0.codeMode = .authenticator
            $0.submitPhase = .idle
            $0.errorMessage = nil
            $0.invalidFieldsScope = nil
        }
    }

    @Test("cancellation: a code check still running when the user goes back never lands on the screen")
    func backCancelsInFlightCheck() async {
        let clock = TestClock()
        let store = Support.makeStore(secondFactorState(code: TestAccount.totpCode), clock: clock) { [user] in
            $0.authClient.loginTOTP = { _, _ in user }
        }

        await store.send(.codeSubmitButtonTapped) { $0.submitPhase = .submitting }
        await store.send(.secondFactorBackButtonTapped) {
            $0.currentPage = .credentials
            $0.code = ""
            $0.submitPhase = .idle
        }

        // A late result would be an unhandled received action and fail the finish.
        await clock.advance(by: .seconds(10))
        await store.finish()
    }

    // MARK: - The sign in log

    @Test("the log of a whole 2FA sign in holds no password, name, code or address")
    func logNeverHoldsWhatWasTyped() async {
        let clock = TestClock()
        let store = Support.makeStore(secondFactorState(code: TestAccount.recoveryCode, mode: .recovery), clock: clock) {
            $0.authClient.loginTOTP = { _, _ in throw AuthClientError.network("Could not connect to \(Support.host)") }
        }

        await store.send(.codeSubmitButtonTapped) { $0.submitPhase = .submitting }
        await clock.advance(by: .seconds(0.25))
        await store.receive(\.submitFailed) {
            $0.submitPhase = .failure
            $0.errorMessage = L10n.Login.errorUnreachable
        }
        await Support.expireSubmitError(store, clock: clock)

        #expect(store.state.diagnostics.entries == [
            Support.entry("code: sending, other, 11 characters"),
            Support.entry("code: network error: Could not connect to <server>", isProblem: true),
        ])
        expectNoSecrets(in: store, extra: ["2HSMP"])
    }

    @Test("a password sign in logs the shape of the name and whether a password was set, never their text, stamped with the injected date")
    func signInLogsShapes() async {
        let clock = TestClock()
        let store = Support.makeStore(Support.credentialsState(), clock: clock) {
            $0.authClient.login = { _, _, _ in throw AuthClientError.invalidCredentials }
        }

        await store.send(.continueButtonTapped) { $0.submitPhase = .submitting }
        await clock.advance(by: .seconds(0.25))
        await store.receive(\.submitFailed) {
            $0.submitPhase = .failure
            $0.errorMessage = L10n.Login.errorInvalidCredentials
            $0.invalidFieldsScope = .identifierAndPassword
        }
        await Support.expireSubmitError(store, clock: clock)

        #expect(store.state.diagnostics.entries == [
            Support.entry("sign in: sending, name username shaped, 6 characters, password set"),
            Support.entry("sign in: rejected: server answered 401, no account matches that name and password", isProblem: true),
        ])
        expectNoSecrets(in: store)
    }

    @Test("a failed connection test is logged as a problem")
    func connectionFailureIsLogged() async {
        let clock = TestClock()
        let store = Support.makeStore(LoginFormFeature.State(host: Support.host), clock: clock) {
            $0.authClient.fetchStatus = { _ in throw AuthClientError.server(statusCode: 502) }
        }

        await store.send(.testConnectionButtonTapped) { $0.connectionPhase = .testing }
        await clock.advance(by: .seconds(0.25))
        await store.receive(\.testConnectionResponse.failure) {
            $0.connectionPhase = .failure
            $0.errorMessage = L10n.Login.errorServer(502)
        }
        await clock.advance(by: .seconds(1))
        await store.receive(\.revertToIdle) { $0.connectionPhase = .idle }
        await clock.advance(by: .seconds(3))
        await store.receive(\.clearErrorMessage) { $0.errorMessage = nil }

        #expect(store.state.diagnostics.entries == [
            Support.entry("connecting: https, default port"),
            Support.entry("server status: server answered 502", isProblem: true),
        ])
    }

    @Test("a successful connection test logs what the server offers and is not a problem")
    func connectionSuccessIsLogged() async {
        let clock = TestClock()
        let store = Support.makeStore(LoginFormFeature.State(host: Support.host), clock: clock) {
            $0.authClient.fetchStatus = { _ in Support.passwordOnly }
        }

        await store.send(.testConnectionButtonTapped) { $0.connectionPhase = .testing }
        await clock.advance(by: .seconds(0.25))
        await store.receive(\.testConnectionResponse.success) {
            $0.connectionPhase = .success
            $0.authStatus = Support.passwordOnly
        }
        await clock.advance(by: .seconds(0.5))
        await store.receive(\.advanceToCredentials) { $0.currentPage = .credentials }

        #expect(store.state.diagnostics.entries == [
            Support.entry("connecting: https, default port"),
            Support.entry("server status: password sign in on, single sign on off, redirected to https false"),
        ])
    }
}
