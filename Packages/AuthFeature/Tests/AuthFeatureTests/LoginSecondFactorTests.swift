import AuthClient
@testable import AuthFeature
import ComposableArchitecture
import CoreModels
import Foundation
import Localization
import Testing

private enum Fixtures {
    static let receiveTimeout: Duration = .seconds(10)
    static let host = "nextexplorer.example.com"
    static let identifier = "asmith"
    static let password = "hunter2"
    static let now = Date(timeIntervalSince1970: 1_700_000_000)
}

@MainActor
@Suite("LoginFormFeature second factor", .serialized)
struct LoginSecondFactorTests {
    private let user = User(id: "1", username: "asmith", email: nil, roles: [])

    private func store(
        state: LoginFormFeature.State,
        clock: any Clock<Duration> = ImmediateClock(),
        configure: (inout DependencyValues) -> Void
    ) -> TestStore<LoginFormFeature.State, LoginFormFeature.Action> {
        let store = TestStore(initialState: state) {
            LoginFormFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.loginLogDate = { Fixtures.now }
            configure(&$0)
        }
        store.timeout = Fixtures.receiveTimeout
        store.exhaustivity = .off(showSkippedAssertions: false)
        return store
    }

    private var credentialsState: LoginFormFeature.State {
        LoginFormFeature.State(
            currentPage: .credentials,
            host: Fixtures.host,
            identifier: Fixtures.identifier,
            password: Fixtures.password,
            authStatus: AuthStatus(localEnabled: true, oidcEnabled: false)
        )
    }

    private var secondFactorState: LoginFormFeature.State {
        var state = credentialsState
        state.currentPage = .secondFactor
        return state
    }

    // MARK: - Asking for the code

    @Test("regression NXTIOS-0095: a right password on a 2FA account opens the code page instead of saying the credentials are wrong")
    func secondFactorRequiredOpensCodePage() async {
        let store = store(state: credentialsState) {
            $0.authClient.login = { _, _, _ in throw AuthClientError.secondFactorRequired }
        }

        await store.send(.continueButtonTapped)
        await store.receive(\.secondFactorRequested)

        #expect(store.state.currentPage == .secondFactor)
        #expect(store.state.submitPhase == .idle)
        #expect(store.state.errorMessage == nil)
        #expect(store.state.invalidFieldsScope == nil)
        #expect(store.state.code.isEmpty)
    }

    @Test("the second factor request is logged, and is not a problem")
    func secondFactorRequestIsLoggedWithoutProblem() async {
        let store = store(state: credentialsState) {
            $0.authClient.login = { _, _, _ in throw AuthClientError.secondFactorRequired }
        }

        await store.send(.continueButtonTapped)
        await store.receive(\.secondFactorRequested)

        let texts = store.state.diagnostics.entries.map(\.text)
        #expect(texts.contains("sign in: password accepted, server asks for a second factor code"))
        #expect(!store.state.diagnostics.hasProblem)
    }

    // MARK: - Sending the code

    @Test("happy path: the trimmed code is sent and the user is handed to the app")
    func codeSignsIn() async {
        var state = secondFactorState
        state.code = "  123456 "
        let store = store(state: state) { [user] in
            $0.authClient.loginTOTP = { url, code in
                #expect(url.absoluteString == "https://\(Fixtures.host)")
                #expect(code == "123456")
                return user
            }
        }

        await store.send(.codeSubmitButtonTapped)
        await store.receive(\.submitSucceeded)
        await store.receive(\.delegate)

        #expect(store.state.submitPhase == .success)
    }

    @Test("a recovery code is sent as typed")
    func recoveryCodeIsSentAsTyped() async {
        var state = secondFactorState
        state.codeMode = .recovery
        state.code = "2HSMP-G9ZSJ"
        let store = store(state: state) { [user] in
            $0.authClient.loginTOTP = { _, code in
                #expect(code == "2HSMP-G9ZSJ")
                return user
            }
        }

        await store.send(.codeSubmitButtonTapped)
        await store.receive(\.submitSucceeded)
        await store.receive(\.delegate)
    }

    @Test("error path: a wrong code stays on the code page with a readable message")
    func wrongCodeStaysOnCodePage() async {
        var state = secondFactorState
        state.code = "000000"
        let store = store(state: state) {
            $0.authClient.loginTOTP = { _, _ in throw AuthClientError.invalidCode }
        }

        await store.send(.codeSubmitButtonTapped)
        await store.receive(\.submitFailed)

        #expect(store.state.currentPage == .secondFactor)
        #expect(store.state.submitPhase == .failure)
        #expect(store.state.errorMessage == L10n.Login.errorInvalidCode)
        #expect(store.state.invalidFieldsScope == nil)
        #expect(store.state.code.isEmpty, "six boxes of a wrong code are cleared, not left to erase one by one")
        #expect(store.state.diagnostics.hasProblem)
        #expect(store.state.diagnostics.entries.last?.text == "code: code rejected by the server")
    }

    @Test("error path: a sign in the server no longer waits on sends the user back to the password page")
    func expiredSecondStepReturnsToCredentials() async {
        var state = secondFactorState
        state.code = "123456"
        let store = store(state: state) {
            $0.authClient.loginTOTP = { _, _ in throw AuthClientError.secondFactorExpired }
        }

        await store.send(.codeSubmitButtonTapped)
        await store.receive(\.submitFailed)

        #expect(store.state.currentPage == .credentials)
        #expect(store.state.code.isEmpty)
        #expect(store.state.codeMode == .authenticator)
        #expect(store.state.errorMessage == L10n.Login.errorSecondFactorExpired)
        #expect(store.state.password == Fixtures.password)
    }

    @Test("error path: a locked account or rate limit shows the rate limit message")
    func rateLimitedCode() async {
        var state = secondFactorState
        state.code = "123456"
        let store = store(state: state) {
            $0.authClient.loginTOTP = { _, _ in throw AuthClientError.rateLimited }
        }

        await store.send(.codeSubmitButtonTapped)
        await store.receive(\.submitFailed)

        #expect(store.state.currentPage == .secondFactor)
        #expect(store.state.errorMessage == L10n.Login.errorRateLimited)
    }

    @Test("error path: an unreachable server shows the unreachable message and keeps the code")
    func networkFailureOnCode() async {
        var state = secondFactorState
        state.code = "123456"
        let store = store(state: state) {
            $0.authClient.loginTOTP = { _, _ in throw AuthClientError.network("offline") }
        }

        await store.send(.codeSubmitButtonTapped)
        await store.receive(\.submitFailed)

        #expect(store.state.errorMessage == L10n.Login.errorUnreachable)
        #expect(store.state.code == "123456")
    }

    @Test("edge case: an empty or blank code is never sent")
    func blankCodeIsNotSent() async {
        for blank in ["", "   ", "\n"] {
            var state = secondFactorState
            state.code = blank
            let store = store(state: state) {
                $0.authClient.loginTOTP = { _, _ in
                    Issue.record("loginTOTP must not be called for a blank code")
                    throw AuthClientError.invalidCode
                }
            }

            await store.send(.codeSubmitButtonTapped)
            #expect(store.state.submitPhase == .idle)
        }
    }

    @Test("edge case: submitting a code outside the code page does nothing")
    func codeOutsideCodePageIsIgnored() async {
        var state = credentialsState
        state.code = "123456"
        let store = store(state: state) {
            $0.authClient.loginTOTP = { _, _ in
                Issue.record("loginTOTP must not be called from the credentials page")
                throw AuthClientError.invalidCode
            }
        }

        await store.send(.codeSubmitButtonTapped)
        #expect(store.state.submitPhase == .idle)
    }

    @Test("edge case: a second tap while the code is being checked does not send it twice")
    func doubleTapSendsOnce() async {
        var state = secondFactorState
        state.code = "123456"
        let counter = LockIsolated(0)
        let clock = TestClock()
        let store = store(state: state, clock: clock) { [user] in
            $0.authClient.loginTOTP = { _, _ in
                counter.withValue { $0 += 1 }
                return user
            }
        }

        await store.send(.codeSubmitButtonTapped)
        await store.send(.codeSubmitButtonTapped)
        await clock.advance(by: .seconds(1))
        await store.receive(\.submitSucceeded)
        await store.receive(\.delegate)

        #expect(counter.value == 1)
    }

    // MARK: - The field

    @Test("boundary: the authenticator code is capped at six digits")
    func authenticatorCodeIsCapped() async {
        var state = secondFactorState
        // A check already running keeps the sixth digit from submitting, so only the cap is seen.
        state.submitPhase = .submitting
        let store = store(state: state) { _ in }

        await store.send(.codeChanged(String(repeating: "1", count: 500)))

        #expect(store.state.code == "111111")
    }

    @Test("boundary: a recovery code is capped at 32 characters")
    func recoveryCodeIsCapped() async {
        var state = secondFactorState
        state.codeMode = .recovery
        let store = store(state: state) { _ in }

        await store.send(.codeChanged(String(repeating: "A", count: 500)))

        #expect(store.state.code.count == 32)
    }

    @Test("edge case: the authenticator field keeps digits only, so a pasted code with spaces or a dash still lands")
    func authenticatorCodeKeepsDigitsOnly() async {
        for (typed, kept) in [("12a", "12"), ("12 34", "1234"), ("abc", ""), ("\u{0663}\u{0664}5", "5")] {
            let store = store(state: secondFactorState) { _ in }
            await store.send(.codeChanged(typed))
            #expect(store.state.code == kept, "typed \(typed.debugDescription)")
        }
    }

    @Test("a recovery code keeps its letters and dash")
    func recoveryCodeKeepsLettersAndDash() async {
        var state = secondFactorState
        state.codeMode = .recovery
        let store = store(state: state) { _ in }

        await store.send(.codeChanged("2HSMP-G9ZSJ"))

        #expect(store.state.code == "2HSMP-G9ZSJ")
    }

    @Test("the sixth digit sends the code without a tap")
    func sixthDigitSubmits() async {
        let sent = LockIsolated<[String]>([])
        let store = store(state: secondFactorState) { [user] in
            $0.authClient.loginTOTP = { _, code in
                sent.withValue { $0.append(code) }
                return user
            }
        }

        await store.send(.codeChanged("12345"))
        #expect(sent.value.isEmpty)
        #expect(store.state.submitPhase == .idle)

        await store.send(.codeChanged("123456"))
        await store.receive(\.codeSubmitButtonTapped)
        await store.receive(\.submitSucceeded)
        await store.receive(\.delegate)

        #expect(sent.value == ["123456"])
    }

    @Test("edge case: a recovery code is never sent by typing its last character")
    func recoveryCodeDoesNotAutoSubmit() async {
        var state = secondFactorState
        state.codeMode = .recovery
        let store = store(state: state) {
            $0.authClient.loginTOTP = { _, _ in
                Issue.record("a recovery code is only sent by the Verify button")
                throw AuthClientError.invalidCode
            }
        }

        await store.send(.codeChanged("2HSMP-G9ZSJ"))
        #expect(store.state.submitPhase == .idle)
    }

    @Test("edge case: typing the sixth digit while a check is already running sends nothing more")
    func sixthDigitDuringCheckDoesNotResend() async {
        var state = secondFactorState
        state.submitPhase = .submitting
        let store = store(state: state) {
            $0.authClient.loginTOTP = { _, _ in
                Issue.record("a check is already running")
                throw AuthClientError.invalidCode
            }
        }

        await store.send(.codeChanged("123456"))
    }

    @Test("a wrong recovery code is kept, so a typo can be fixed")
    func wrongRecoveryCodeIsKept() async {
        var state = secondFactorState
        state.codeMode = .recovery
        state.code = "2HSMP-G9ZSX"
        let store = store(state: state) {
            $0.authClient.loginTOTP = { _, _ in throw AuthClientError.invalidCode }
        }

        await store.send(.codeSubmitButtonTapped)
        await store.receive(\.submitFailed)

        #expect(store.state.code == "2HSMP-G9ZSX")
    }

    @Test("the toggle swaps between the authenticator code and a recovery code, clearing what was typed and any error")
    func toggleCodeMode() async {
        var state = secondFactorState
        state.code = "123"
        state.errorMessage = "old"
        let store = store(state: state) { _ in }

        await store.send(.toggleCodeModeTapped)
        #expect(store.state.codeMode == .recovery)
        #expect(store.state.code.isEmpty)
        #expect(store.state.errorMessage == nil)

        await store.send(.toggleCodeModeTapped)
        #expect(store.state.codeMode == .authenticator)
    }

    // MARK: - Leaving the page

    @Test("back from the code page returns to the password page, clears the code and keeps the password")
    func backReturnsToCredentials() async {
        var state = secondFactorState
        state.code = "123"
        state.codeMode = .recovery
        state.errorMessage = "old"
        let store = store(state: state) { _ in }

        await store.send(.secondFactorBackButtonTapped)

        #expect(store.state.currentPage == .credentials)
        #expect(store.state.code.isEmpty)
        #expect(store.state.codeMode == .authenticator)
        #expect(store.state.errorMessage == nil)
        #expect(store.state.submitPhase == .idle)
        #expect(store.state.password == Fixtures.password)
    }

    @Test("cancellation: a code check still running when the user goes back never lands on the screen")
    func backCancelsInFlightCheck() async {
        var state = secondFactorState
        state.code = "123456"
        let clock = TestClock()
        let store = store(state: state, clock: clock) { [user] in
            $0.authClient.loginTOTP = { _, _ in user }
        }

        await store.send(.codeSubmitButtonTapped)
        await store.send(.secondFactorBackButtonTapped)
        await clock.advance(by: .seconds(10))

        #expect(store.state.currentPage == .credentials)
        #expect(store.state.submitPhase == .idle)
        await store.finish()
    }

    @Test("editing the server address starts over and clears the code")
    func hostEditClearsCode() async {
        var state = secondFactorState
        state.code = "123456"
        let store = store(state: state) { _ in }

        await store.send(.hostChanged("other.example.com"))

        #expect(store.state.currentPage == .server)
        #expect(store.state.code.isEmpty)
    }

    // MARK: - The sign in log

    @Test("the log of a whole 2FA sign in holds no password, name, code or address")
    func logNeverHoldsWhatWasTyped() async {
        var state = secondFactorState
        state.code = "2HSMP-G9ZSJ"
        let store = store(state: state) {
            $0.authClient.loginTOTP = { _, _ in throw AuthClientError.network("Could not connect to \(Fixtures.host)") }
        }

        await store.send(.codeSubmitButtonTapped)
        await store.receive(\.submitFailed)

        let log = store.state.diagnostics.rendered(header: [])
        #expect(log.contains("code: sending, other, 11 characters"))
        for secret in [Fixtures.password, Fixtures.identifier, Fixtures.host, "2HSMP"] {
            #expect(!log.contains(secret), "the log must not contain \(secret)")
        }
    }

    @Test("a password sign in logs the shape of the name and whether a password was set, never their text")
    func signInLogsShapes() async {
        let store = store(state: credentialsState) {
            $0.authClient.login = { _, _, _ in throw AuthClientError.invalidCredentials }
        }

        await store.send(.continueButtonTapped)
        await store.receive(\.submitFailed)

        let texts = store.state.diagnostics.entries.map(\.text)
        #expect(texts.contains("sign in: sending, name username shaped, 6 characters, password set"))
        #expect(texts.contains("sign in: rejected: server answered 401, no account matches that name and password"))
        #expect(store.state.diagnostics.hasProblem)
    }

    @Test("a failed connection test is logged as a problem")
    func connectionFailureIsLogged() async {
        let store = store(state: LoginFormFeature.State(host: Fixtures.host)) {
            $0.authClient.fetchStatus = { _ in throw AuthClientError.server(statusCode: 502) }
        }

        await store.send(.testConnectionButtonTapped)
        await store.receive(\.testConnectionResponse)

        let texts = store.state.diagnostics.entries.map(\.text)
        #expect(texts.contains("connecting: https, default port"))
        #expect(texts.contains("server status: server answered 502"))
        #expect(store.state.diagnostics.hasProblem)
    }

    @Test("a successful connection test logs what the server offers and is not a problem")
    func connectionSuccessIsLogged() async {
        let store = store(state: LoginFormFeature.State(host: Fixtures.host)) {
            $0.authClient.fetchStatus = { _ in AuthStatus(localEnabled: true, oidcEnabled: false) }
        }

        await store.send(.testConnectionButtonTapped)
        await store.receive(\.testConnectionResponse)

        let texts = store.state.diagnostics.entries.map(\.text)
        #expect(texts.contains("server status: password sign in on, single sign on off, redirected to https false"))
        #expect(!store.state.diagnostics.hasProblem)
    }

    @Test("every entry is stamped with the injected date")
    func entriesUseInjectedDate() async {
        let store = store(state: credentialsState) {
            $0.authClient.login = { _, _, _ in throw AuthClientError.invalidCredentials }
        }

        await store.send(.continueButtonTapped)
        await store.receive(\.submitFailed)

        #expect(store.state.diagnostics.entries.allSatisfy { $0.timestamp == Fixtures.now })
    }
}
