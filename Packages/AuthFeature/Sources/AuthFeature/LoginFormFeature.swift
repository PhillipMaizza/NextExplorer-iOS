import AuthClient
import ClientCertificateFeature
import ComposableArchitecture
import CoreModels
import Foundation
import Localization
import NetworkClient

private enum Constants {
    /// A real homelab call can resolve near-instantly on a warm connection: hold the
    /// spinner up briefly so the loading animation is actually visible.
    static let minimumSpinnerDuration: Duration = .seconds(0.25)
    /// How long the green checkmark stays on screen before auto-advancing to credentials.
    static let successDisplayDuration: Duration = .seconds(0.5)
    /// How long the red X stays on screen before the button re-expands so the user can retry.
    static let failureDisplayDuration: Duration = .seconds(1)
    /// How long an error message stays on screen before it clears itself.
    static let errorDismissDuration: Duration = .seconds(4)
    /// Upper bounds on what the fields accept, so a pathological paste (a whole document
    /// dropped into a field) can't reach a network call or a regex. The host cap is generous
    /// enough to survive a pasted `https://…:port/path` that `normalizedURL` then trims down;
    /// the final host is bounded to 253 (DNS max) by `normalizedURL` itself. Email follows
    /// RFC 5321's 254; the password cap is a sane ceiling well above any real passphrase.
    static let maxHostInputLength = 2048
    static let maxIdentifierLength = 254
    static let maxPasswordLength = 256
    /// A recovery code is ten characters with a dash; the cap only stops a pathological paste.
    static let maxRecoveryCodeLength = 32
}

@Reducer
public struct LoginFormFeature {
    /// Effect identities so a stale in-flight call from a host/scheme the user has since
    /// abandoned can never land its result (or an auto-advance) on the current screen.
    private enum CancelID {
        case connectionTest
        case certificateLookup
        case successAdvance
        case failureRevert
        case errorDismiss
        case submit
        case submitRevert
        case oidc
        case oidcSuccessAdvance
    }

    public enum URLScheme: String, CaseIterable, Equatable, Hashable, Sendable, Identifiable {
        case https
        case http

        public var id: String {
            rawValue
        }

        public var displayName: String {
            rawValue
        }
    }

    public enum Page: Equatable, Sendable {
        case server
        case credentials
        case secondFactor
    }

    public enum ConnectionPhase: Equatable, Sendable {
        case idle
        case testing
        case success
        case failure
    }

    /// The credentials-page submit button's morph state: full pill (`idle`), collapsed
    /// spinner (`submitting`), collapsed checkmark (`success`, held briefly so it reads before
    /// the app zooms in), collapsed X (`failure`, then re-expands to `idle`). Mirrors
    /// `ConnectionPhase`'s role for the server-page button.
    /// What the second factor page asks for: the six digits from an authenticator app, or one of
    /// the recovery codes the account was given when it turned the second factor on.
    public enum CodeMode: Equatable, Sendable {
        case authenticator
        case recovery
    }

    public enum SubmitPhase: Equatable, Sendable {
        case idle
        case submitting
        case success
        case failure
    }

    /// The SSO button's lifecycle: `idle`, `authenticating` while the web sheet + code exchange
    /// run, then a brief `success` beat that seeds the accent flood into the app. Mirrors
    /// `submitPhase` so the SSO path gets the same login to app choreography the password path
    /// has, instead of snapping straight in.
    public enum OIDCPhase: Equatable, Sendable {
        case idle
        case authenticating
        case success
    }

    /// The server whose TLS layer refused the app over its client certificate, and whether one was
    /// presented and refused (Manage) or none was installed (Add).
    public struct CertificatePrompt: Equatable, Sendable {
        public var origin: ClientCertificateOrigin
        public var isRejected: Bool

        public init(origin: ClientCertificateOrigin, isRejected: Bool) {
            self.origin = origin
            self.isRejected = isRejected
        }
    }

    /// Which credential field(s) should shake/red-border for the current `errorMessage`: a
    /// server-rejected email or username and password implicates both (the server never says
    /// which one was actually wrong).
    public enum InvalidFieldScope: Equatable, Sendable {
        case identifierAndPassword
    }

    @ObservableState
    public struct State: Equatable {
        public var currentPage: Page
        public var connectionPhase: ConnectionPhase
        public var scheme: URLScheme
        public var host: String
        /// Set once the user taps the scheme picker themselves, so typing doesn't then move it
        /// back under them. Cleared when the host is emptied or an explicit `http(s)://` is typed.
        var schemeWasSetByUser: Bool = false
        public var identifier: String
        public var password: String
        /// The authenticator code or recovery code typed on the second factor page.
        public var code: String
        public var codeMode: CodeMode
        @ObservationStateIgnored var diagnostics = LoginDiagnostics()
        public var isPasswordVisible: Bool
        public var submitPhase: SubmitPhase
        /// The SSO button's lifecycle (idle / authenticating / success). A phase, not a bool
        /// cluster, because it now carries a success beat that drives the accent flood.
        public var oidcPhase: OIDCPhase
        public var errorMessage: String?
        public var invalidFieldsScope: InvalidFieldScope?
        public var authStatus: AuthStatus?
        /// Set when the server's TLS layer turned the app away over its client certificate, so
        /// the server page offers the certificate sheet until the address changes. Outlives the
        /// self clearing `errorMessage` on purpose: the user needs time to go find the file.
        public var certificatePrompt: CertificatePrompt?
        /// The client certificate the app presents to the server being tested, shown with a Change
        /// link so a wrong file can be swapped without waiting for an error.
        public var certificateInUse: ClientCertificateSummary?
        @Presents public var clientCertificate: ClientCertificateFeature.State?

        public init(
            currentPage: Page = .server,
            connectionPhase: ConnectionPhase = .idle,
            scheme: URLScheme = .https,
            host: String = "",
            identifier: String = "",
            password: String = "",
            code: String = "",
            codeMode: CodeMode = .authenticator,
            isPasswordVisible: Bool = false,
            submitPhase: SubmitPhase = .idle,
            oidcPhase: OIDCPhase = .idle,
            errorMessage: String? = nil,
            invalidFieldsScope: InvalidFieldScope? = nil,
            authStatus: AuthStatus? = nil,
            certificatePrompt: CertificatePrompt? = nil,
            certificateInUse: ClientCertificateSummary? = nil,
            clientCertificate: ClientCertificateFeature.State? = nil
        ) {
            self.currentPage = currentPage
            self.connectionPhase = connectionPhase
            self.scheme = scheme
            self.host = host
            self.identifier = identifier
            self.password = password
            self.code = code
            self.codeMode = codeMode
            self.isPasswordVisible = isPasswordVisible
            self.submitPhase = submitPhase
            self.oidcPhase = oidcPhase
            self.errorMessage = errorMessage
            self.invalidFieldsScope = invalidFieldsScope
            self.authStatus = authStatus
            self.certificatePrompt = certificatePrompt
            self.certificateInUse = certificateInUse
            self.clientCertificate = clientCertificate
        }

        public var isSubmitting: Bool {
            submitPhase == .submitting
        }

        /// The server's host, only so a network error in the sign in log can have it blanked out.
        var serverHost: String? {
            LoginFormFeature.normalizedURL(scheme: scheme, host: host)?.host(percentEncoded: false)
        }

        mutating func logError(_ step: String, _ error: AuthClientError, at timestamp: Date) {
            diagnostics.record(
                "\(step): \(LoginDiagnostics.describe(error, host: serverHost))",
                isProblem: LoginDiagnostics.isProblem(error),
                at: timestamp
            )
        }

        /// Any edit to the server URL, or pressing back, invalidates whatever the last
        /// Test Connection call found: the whole handshake starts over.
        mutating func resetConnection() {
            currentPage = .server
            connectionPhase = .idle
            code = ""
            codeMode = .authenticator
            submitPhase = .idle
            oidcPhase = .idle
            authStatus = nil
            errorMessage = nil
            invalidFieldsScope = nil
            certificatePrompt = nil
            certificateInUse = nil
        }
    }

    public enum Action: Equatable, Sendable {
        case schemeChanged(URLScheme)
        case hostChanged(String)
        case identifierChanged(String)
        case passwordChanged(String)
        case codeChanged(String)
        case toggleCodeModeTapped
        case togglePasswordVisibility
        case testConnectionButtonTapped
        case testConnectionResponse(Result<AuthStatus, AuthClientError>)
        case advanceToCredentials
        case revertToIdle
        case revertSubmitToIdle
        case clearErrorMessage
        case backButtonTapped
        case continueButtonTapped
        case secondFactorRequested
        case secondFactorBackButtonTapped
        case codeSubmitButtonTapped
        case submitSucceeded(User, URL)
        case submitFailed(AuthClientError)
        case ssoButtonTapped
        case oidcResponse(Result<User, AuthClientError>, URL)
        case clientCertificateButtonTapped
        case changeClientCertificateTapped
        case certificateInUseLoaded(ClientCertificateSummary)
        case clientCertificate(PresentationAction<ClientCertificateFeature.Action>)
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case authenticated(User, URL)
        }
    }

    @Dependency(\.authClient) var authClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.loginLogDate) var logDate
    @Dependency(\.clientCertificateClient) var clientCertificateClient

    public init() {}

    /// The length of an authenticator app code, which the six boxes and the auto submit follow.
    static let authenticatorCodeLength = 6
    private static let asciiDigits: Set<Character> = Set("0123456789")

    private var now: Date {
        logDate()
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .schemeChanged(scheme):
                // The address stays as typed: an IP infers http, and someone whose server wants
                // https on that IP (an mTLS proxy) taps https and keeps going. A typed prefix
                // would contradict the picker, so it goes.
                state.host = Self.strippingSchemePrefix(state.host)
                state.scheme = scheme
                state.schemeWasSetByUser = true
                state.resetConnection()
                return Self.cancelInFlightWork()

            case let .hostChanged(rawText):
                let text = String(rawText.prefix(Constants.maxHostInputLength))
                // The Mac text field reports its text again when the window's state changes, with
                // nothing edited. Treating that as a new address would cancel a connection test in
                // flight and drop the certificate offer.
                guard text != state.host else { return .none }
                state.host = text
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if trimmed.isEmpty {
                    state.schemeWasSetByUser = false
                } else if trimmed.hasPrefix("http://") {
                    state.scheme = .http
                    state.schemeWasSetByUser = false
                } else if trimmed.hasPrefix("https://") {
                    state.scheme = .https
                    state.schemeWasSetByUser = false
                } else if !state.schemeWasSetByUser, let first = trimmed.first {
                    // A leading digit is an IP (a homelab box, so http); a hostname is a
                    // public server (so https). A LAN hostname that needs http is the one
                    // case the user fixes with the picker: and then it sticks.
                    state.scheme = first.isNumber ? .http : .https
                }
                state.resetConnection()
                return Self.cancelInFlightWork()

            case let .identifierChanged(text):
                state.identifier = String(text.prefix(Constants.maxIdentifierLength))
                return .none

            case let .passwordChanged(text):
                state.password = String(text.prefix(Constants.maxPasswordLength))
                return .none

            case let .codeChanged(text):
                switch state.codeMode {
                case .recovery:
                    state.code = String(text.prefix(Constants.maxRecoveryCodeLength))
                    return .none
                case .authenticator:
                    // Pasting "123 456" or "123-456" still lands as six digits.
                    state.code = String(text.filter { Self.asciiDigits.contains($0) }.prefix(Self.authenticatorCodeLength))
                    guard state.code.count == Self.authenticatorCodeLength, state.submitPhase == .idle else { return .none }
                    return .send(.codeSubmitButtonTapped)
                }

            case .toggleCodeModeTapped:
                state.codeMode = state.codeMode == .authenticator ? .recovery : .authenticator
                state.code = ""
                state.errorMessage = nil
                return .cancel(id: CancelID.errorDismiss)

            case .togglePasswordVisibility:
                state.isPasswordVisible.toggle()
                return .none

            case .secondFactorBackButtonTapped:
                state.currentPage = .credentials
                state.code = ""
                state.codeMode = .authenticator
                state.submitPhase = .idle
                state.errorMessage = nil
                state.invalidFieldsScope = nil
                return .merge(.cancel(id: CancelID.submit), .cancel(id: CancelID.submitRevert), .cancel(id: CancelID.errorDismiss))

            case .backButtonTapped:
                state.resetConnection()
                return Self.cancelInFlightWork()

            case .testConnectionButtonTapped:
                guard let url = Self.normalizedURL(scheme: state.scheme, host: state.host) else {
                    state.connectionPhase = .failure
                    state.errorMessage = L10n.Login.errorInvalidServer
                    return .merge(Self.scheduleRevertToIdle(self.clock), Self.scheduleErrorDismiss(self.clock))
                }
                state.connectionPhase = .testing
                state.errorMessage = nil
                state.diagnostics.record("connecting: \(LoginDiagnostics.describe(server: url))", at: now)
                let authClient = authClient
                let clock = clock
                return .merge(
                    .cancel(id: CancelID.successAdvance),
                    .run { send in
                        async let statusResult = Self.fetchStatusResult(authClient, url)
                        try? await clock.sleep(for: Constants.minimumSpinnerDuration)
                        await send(.testConnectionResponse(statusResult))
                    }
                    .cancellable(id: CancelID.connectionTest, cancelInFlight: true)
                )

            case let .testConnectionResponse(.success(status)):
                state.authStatus = status
                state.diagnostics.record(
                    "server status: password sign in \(status.isLocalEnabled ? "on" : "off"), single sign on \(status.isOIDCEnabled ? "on" : "off"), redirected to https \(status.redirectsToHTTPS)",
                    at: now
                )
                state.certificatePrompt = nil
                // The server sent http to https: sign in there directly, or the password is lost
                // in the redirect (and would travel unencrypted first).
                if status.redirectsToHTTPS {
                    state.scheme = .https
                    if let host = Self.hostText(state.host, port: status.redirectedPort) {
                        state.host = host
                    }
                }
                let clock = clock
                guard status.isLocalEnabled || status.isOIDCEnabled else {
                    state.connectionPhase = .failure
                    state.errorMessage = Self.message(for: .noAuthMethodsEnabled)
                    return .merge(Self.scheduleRevertToIdle(clock), Self.scheduleErrorDismiss(clock))
                }
                state.connectionPhase = .success
                return .merge(
                    .run { send in
                        try await clock.sleep(for: Constants.successDisplayDuration)
                        await send(.advanceToCredentials)
                    }
                    .cancellable(id: CancelID.successAdvance, cancelInFlight: true),
                    lookUpCertificateInUse(state)
                )

            case let .testConnectionResponse(.failure(error)):
                state.connectionPhase = .failure
                state.authStatus = nil
                state.logError("server status", error, at: now)
                state.errorMessage = Self.message(for: error)
                state.certificatePrompt = Self.certificatePrompt(for: error, scheme: state.scheme, host: state.host)
                return .merge(Self.scheduleRevertToIdle(clock), Self.scheduleErrorDismiss(clock), lookUpCertificateInUse(state))

            case .revertToIdle:
                state.connectionPhase = .idle
                return .none

            case .revertSubmitToIdle:
                state.submitPhase = .idle
                return .none

            case .clearErrorMessage:
                state.errorMessage = nil
                state.invalidFieldsScope = nil
                return .none

            case .advanceToCredentials:
                state.currentPage = .credentials
                return .none

            case .continueButtonTapped:
                guard state.authStatus?.isLocalEnabled == true,
                      let url = Self.normalizedURL(scheme: state.scheme, host: state.host)
                else {
                    return .none
                }
                let identifier = state.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
                state.submitPhase = .submitting
                state.errorMessage = nil
                state.invalidFieldsScope = nil
                let password = state.password
                state.diagnostics.record(
                    "sign in: sending, name \(LoginDiagnostics.describe(identifier: state.identifier)), password \(LoginDiagnostics.describe(password: password))",
                    at: now
                )
                let authClient = authClient
                let clock = clock
                return .run { send in
                    async let result = Self.loginResult(authClient, url, identifier, password)
                    // Hold the spinner up briefly so it reads even when the call resolves fast.
                    try? await clock.sleep(for: Constants.minimumSpinnerDuration)
                    switch await result {
                    case let .success(user): await send(.submitSucceeded(user, url))
                    case .failure(.secondFactorRequired): await send(.secondFactorRequested)
                    case let .failure(error): await send(.submitFailed(error))
                    }
                }
                .cancellable(id: CancelID.submit, cancelInFlight: true)

            case .secondFactorRequested:
                state.logError("sign in", .secondFactorRequired, at: now)
                state.submitPhase = .idle
                state.code = ""
                state.codeMode = .authenticator
                state.currentPage = .secondFactor
                return .none

            case .codeSubmitButtonTapped:
                let code = state.code.trimmingCharacters(in: .whitespacesAndNewlines)
                guard state.currentPage == .secondFactor,
                      state.submitPhase == .idle,
                      !code.isEmpty,
                      let url = Self.normalizedURL(scheme: state.scheme, host: state.host)
                else {
                    return .none
                }
                state.submitPhase = .submitting
                state.errorMessage = nil
                state.invalidFieldsScope = nil
                state.diagnostics.record("code: sending, \(LoginDiagnostics.describe(code: code))", at: now)
                let authClient = authClient
                let clock = clock
                return .run { send in
                    async let result = Self.loginTOTPResult(authClient, url, code)
                    try? await clock.sleep(for: Constants.minimumSpinnerDuration)
                    switch await result {
                    case let .success(user): await send(.submitSucceeded(user, url))
                    case let .failure(error): await send(.submitFailed(error))
                    }
                }
                .cancellable(id: CancelID.submit, cancelInFlight: true)

            case let .submitSucceeded(user, url):
                state.diagnostics.record("sign in: signed in", at: now)
                state.submitPhase = .success
                let clock = clock
                // Hold the checkmark a beat before handing off, so the button's success state
                // registers ahead of the zoom into the app.
                return .run { send in
                    try await clock.sleep(for: Constants.successDisplayDuration)
                    await send(.delegate(.authenticated(user, url)))
                }
                .cancellable(id: CancelID.successAdvance, cancelInFlight: true)

            case let .submitFailed(error):
                state.logError(state.currentPage == .secondFactor ? "code" : "sign in", error, at: now)
                state.submitPhase = .failure
                if error == .secondFactorExpired {
                    state.currentPage = .credentials
                    state.code = ""
                    state.codeMode = .authenticator
                }
                // Six boxes full of a wrong code would have to be erased one by one.
                if error == .invalidCode, state.codeMode == .authenticator {
                    state.code = ""
                }
                state.errorMessage = Self.message(for: error)
                state.invalidFieldsScope = (error == .invalidCredentials) ? .identifierAndPassword : nil
                // `.sessionCookieMissing` means the sign-in itself completed but the app
                // couldn't pick up a session from it: not a typo the user can just retry past.
                // It stays on screen until the next submit attempt or navigation reset clears
                // it, instead of silently vanishing after a few seconds.
                guard error != .sessionCookieMissing else {
                    return Self.scheduleSubmitRevert(clock)
                }
                return .merge(Self.scheduleSubmitRevert(clock), Self.scheduleErrorDismiss(clock))

            case .ssoButtonTapped:
                guard state.authStatus?.isOIDCEnabled == true,
                      state.oidcPhase == .idle,
                      let url = Self.normalizedURL(scheme: state.scheme, host: state.host)
                else {
                    return .none
                }
                state.oidcPhase = .authenticating
                state.diagnostics.record("single sign on: started", at: now)
                state.errorMessage = nil
                state.invalidFieldsScope = nil
                let authClient = authClient
                return .run { send in
                    await send(.oidcResponse(Self.loginOIDCResult(authClient, url), url))
                }
                .cancellable(id: CancelID.oidc, cancelInFlight: true)

            case let .oidcResponse(.success(user), url):
                // Mirror `submitSucceeded`: hold a brief success beat so the accent flood can
                // grow out of the SSO button before the app zooms in, instead of snapping.
                state.oidcPhase = .success
                let clock = clock
                return .run { send in
                    try await clock.sleep(for: Constants.successDisplayDuration)
                    await send(.delegate(.authenticated(user, url)))
                }
                .cancellable(id: CancelID.oidcSuccessAdvance, cancelInFlight: true)

            case let .oidcResponse(.failure(error), _):
                state.oidcPhase = .idle
                // A user dismissing the web sheet is a cancellation, not a failure: leave the
                // screen as it was with no error banner.
                state.logError("single sign on", error, at: now)
                guard error != .oidcCancelled else { return .none }
                state.errorMessage = Self.message(for: error)
                return Self.scheduleErrorDismiss(clock)

            case .clientCertificateButtonTapped:
                guard let prompt = state.certificatePrompt else { return .none }
                state.clientCertificate = ClientCertificateFeature.State(origin: prompt.origin)
                return .none

            case let .clientCertificate(.presented(.delegate(.installed(summary)))):
                state.clientCertificate = nil
                state.certificatePrompt = nil
                state.certificateInUse = summary
                return .send(.testConnectionButtonTapped)

            case .clientCertificate(.presented(.delegate(.removed))):
                state.certificateInUse = nil
                return .none

            case .changeClientCertificateTapped:
                guard
                    let url = Self.normalizedURL(scheme: state.scheme, host: state.host),
                    let origin = ClientCertificateOrigin(url: url)
                else { return .none }
                state.clientCertificate = ClientCertificateFeature.State(
                    origin: origin,
                    status: state.certificateInUse.map(ClientCertificateFeature.Status.installed) ?? .loading
                )
                return .none

            case let .certificateInUseLoaded(summary):
                state.certificateInUse = summary
                return .none

            case .clientCertificate:
                return .none

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$clientCertificate, action: \.clientCertificate) {
            ClientCertificateFeature()
        }
    }

    /// Finds the certificate presented to the server being tested. Sends only when there is one,
    /// so a server without mTLS adds nothing to the flow.
    private func lookUpCertificateInUse(_ state: State) -> Effect<Action> {
        guard
            let url = Self.normalizedURL(scheme: state.scheme, host: state.host),
            let origin = ClientCertificateOrigin(url: url)
        else { return .none }
        return .run { [client = clientCertificateClient] send in
            if let summary = await client.summary(origin) {
                await send(.certificateInUseLoaded(summary))
            }
        }
        .cancellable(id: CancelID.certificateLookup, cancelInFlight: true)
    }

    /// The origin the certificate sheet is for, when `error` is a handshake refused over the
    /// client certificate. The same normalization as the connection test, so the certificate is
    /// stored under exactly the host and port the app connects to.
    static func certificatePrompt(for error: AuthClientError, scheme: URLScheme, host: String) -> CertificatePrompt? {
        let isRejected: Bool
        switch error {
        case .clientCertificateRequired: isRejected = false
        case .clientCertificateRejected: isRejected = true
        default: return nil
        }
        guard
            let url = normalizedURL(scheme: scheme, host: host),
            let origin = ClientCertificateOrigin(url: url)
        else {
            return nil
        }
        return CertificatePrompt(origin: origin, isRejected: isRejected)
    }

    /// Cancels every in-flight network/timer effect this feature can have running.
    /// Called whenever the user abandons the current handshake (edits the host/scheme,
    /// or backs out) so a stale response can never land on a screen the user has since
    /// moved on from: e.g. an old Test Connection call auto-advancing to credentials
    /// after the user has already typed a different host.
    static func cancelInFlightWork() -> Effect<Action> {
        .merge(
            .cancel(id: CancelID.connectionTest),
            .cancel(id: CancelID.successAdvance),
            .cancel(id: CancelID.failureRevert),
            .cancel(id: CancelID.errorDismiss),
            .cancel(id: CancelID.submit),
            .cancel(id: CancelID.submitRevert),
            .cancel(id: CancelID.oidc),
            .cancel(id: CancelID.certificateLookup)
        )
    }

    /// After a failed Test Connection, the button briefly shows a red X, then re-expands to
    /// the idle "Test connection" label so the user can retry: `errorMessage` stays set and
    /// visible independent of this, so the failure reason doesn't disappear along with it.
    static func scheduleRevertToIdle(_ clock: any Clock<Duration>) -> Effect<Action> {
        .run { send in
            try await clock.sleep(for: Constants.failureDisplayDuration)
            await send(.revertToIdle)
        }
        .cancellable(id: CancelID.failureRevert, cancelInFlight: true)
    }

    /// The credentials-page counterpart to `scheduleRevertToIdle`: after a failed login the
    /// submit button holds a red X, then re-expands to the idle label so the user can retry.
    static func scheduleSubmitRevert(_ clock: any Clock<Duration>) -> Effect<Action> {
        .run { send in
            try await clock.sleep(for: Constants.failureDisplayDuration)
            await send(.revertSubmitToIdle)
        }
        .cancellable(id: CancelID.submitRevert, cancelInFlight: true)
    }

    /// Auto-dismisses whatever error message is currently showing after a few seconds, so the
    /// user isn't left staring at a stale failure reason indefinitely.
    static func scheduleErrorDismiss(_ clock: any Clock<Duration>) -> Effect<Action> {
        .run { send in
            try await clock.sleep(for: Constants.errorDismissDuration)
            await send(.clearErrorMessage)
        }
        .cancellable(id: CancelID.errorDismiss, cancelInFlight: true)
    }

    /// Drops a typed `http://` or `https://` so the scheme picker alone decides the scheme.
    static func strippingSchemePrefix(_ host: String) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        for prefix in ["https://", "http://"] where trimmed.lowercased().hasPrefix(prefix) {
            return String(trimmed.dropFirst(prefix.count))
        }
        return host
    }

    /// Reduces whatever the user typed or pasted to a bare `host[:port]` and rejects anything
    /// that isn't a plausible server address before a network call is ever spent. Strips (in
    /// order): surrounding whitespace, a leading `http(s)://`, any `/path`, `?query` or
    /// `#fragment`, and a `user:pass@` userinfo prefix. What remains must be a valid host
    /// (hostname, IPv4, or bracketed IPv6) with, at most, one numeric port in `1...65535`.
    /// A pasted `https://user@box.local:3000/files?x=1` becomes `http(s)://box.local:3000`.
    static func normalizedURL(scheme: URLScheme, host: String) -> URL? {
        var text = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1 ... Constants.maxHostInputLength).contains(text.count) else { return nil }

        for prefix in ["https://", "http://"] where text.lowercased().hasPrefix(prefix) {
            text.removeFirst(prefix.count)
            break
        }
        if let cut = text.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            text = String(text[..<cut])
        }
        if let at = text.lastIndex(of: "@") {
            text = String(text[text.index(after: at)...])
        }
        guard !text.isEmpty else { return nil }

        // Peel off an optional `:port`. A bracketed IPv6 literal keeps its inner colons; a
        // bare host may carry at most one colon, the port separator: anything else (an
        // unbracketed IPv6, a stray colon) is rejected rather than guessed at.
        var hostPart = text
        var portPart: Substring?
        if text.hasPrefix("[") {
            guard let close = text.firstIndex(of: "]") else { return nil }
            hostPart = String(text[text.index(after: text.startIndex) ..< close])
            let rest = text[text.index(after: close)...]
            if rest.isEmpty {
                portPart = nil
            } else if rest.hasPrefix(":") {
                portPart = rest.dropFirst()
            } else {
                return nil
            }
        } else if let colon = text.firstIndex(of: ":") {
            let after = text[text.index(after: colon)...]
            guard !after.contains(":") else { return nil }
            hostPart = String(text[..<colon])
            portPart = after
        }

        if let portPart {
            guard let port = Int(portPart), (1 ... 65535).contains(port) else { return nil }
        }
        guard isValidHost(hostPart) else { return nil }

        var components = URLComponents()
        components.scheme = scheme.rawValue
        // Foundation does not auto-bracket an IPv6 literal, and an unbracketed one yields a
        // malformed URL: so re-wrap it before handing the host back to URLComponents.
        components.host = hostPart.contains(":") ? "[\(hostPart)]" : hostPart
        components.port = portPart.flatMap { Int($0) }
        guard let url = components.url else { return nil }
        return url
    }

    /// `host` with its port replaced by `port` (dropped when `nil`), so the address saved after an
    /// http to https redirect points where the server answered. `nil` when `host` isn't a valid
    /// server address.
    static func hostText(_ host: String, port: Int?) -> String? {
        guard let url = normalizedURL(scheme: .https, host: host),
              let name = url.host(percentEncoded: false), !name.isEmpty
        else { return nil }
        let bare = name.contains(":") ? "[\(name.trimmingCharacters(in: CharacterSet(charactersIn: "[]")))]" : name
        guard let port else { return bare }
        return "\(bare):\(port)"
    }

    /// A hostname, IPv4 address, or (bracket-stripped) IPv6 literal. Rejects spaces, punctuation
    /// and other junk that `URLComponents` would otherwise silently percent-encode into a host
    /// that can never resolve.
    static func isValidHost(_ host: String) -> Bool {
        guard !host.isEmpty else { return false }
        if host.contains(":") {
            // Only reached for a bracket-stripped IPv6 literal.
            return host.range(of: #"^[0-9A-Fa-f:.]+$"#, options: .regularExpression) != nil
                && host.filter { $0 == ":" }.count >= 2
        }
        // Dot-separated labels of [A-Za-z0-9_-], no leading/trailing hyphen per label, ≤253 total.
        return host.range(
            of: #"^(?=.{1,253}$)([A-Za-z0-9_](?:[A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)(\.[A-Za-z0-9_](?:[A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)*$"#,
            options: .regularExpression
        ) != nil
    }

    static func fetchStatusResult(_ authClient: AuthClient, _ url: URL) async -> Result<AuthStatus, AuthClientError> {
        do {
            return try await .success(authClient.fetchStatus(url))
        } catch {
            return .failure(mapError(error))
        }
    }

    static func loginResult(_ authClient: AuthClient, _ url: URL, _ identifier: String, _ password: String) async -> Result<User, AuthClientError> {
        do {
            return try await .success(authClient.login(url, identifier, password))
        } catch {
            return .failure(mapError(error))
        }
    }

    static func loginTOTPResult(_ authClient: AuthClient, _ url: URL, _ code: String) async -> Result<User, AuthClientError> {
        do {
            return try await .success(authClient.loginTOTP(url, code))
        } catch {
            return .failure(mapError(error))
        }
    }

    static func loginOIDCResult(_ authClient: AuthClient, _ url: URL) async -> Result<User, AuthClientError> {
        do {
            return try await .success(authClient.loginOIDC(url))
        } catch {
            return .failure(mapError(error))
        }
    }

    static func mapError(_ error: Error) -> AuthClientError {
        (error as? AuthClientError) ?? .network(String(describing: error))
    }

    static func message(for error: AuthClientError) -> String {
        switch error {
        case .invalidCredentials: L10n.Login.errorInvalidCredentials
        case .sessionExpired: L10n.Login.errorSessionExpired
        case .sessionCookieMissing: L10n.Login.errorIncomplete
        case .network: L10n.Login.errorUnreachable
        case .decoding: L10n.Login.errorUnexpectedResponse
        case .keychain: L10n.Login.errorKeychain
        case let .server(statusCode): L10n.Login.errorServer(statusCode)
        case .noAuthMethodsEnabled: L10n.Login.errorNoAuthMethods
        case .rateLimited: L10n.Login.errorRateLimited
        case .clientCertificateRequired: L10n.Login.errorClientCertificateRequired
        case .clientCertificateRejected: L10n.Login.errorClientCertificateRejected
        case .secondFactorRequired: L10n.Login.errorIncomplete
        case .invalidCode: L10n.Login.errorInvalidCode
        case .secondFactorExpired: L10n.Login.errorSecondFactorExpired
        case .oidcCancelled: L10n.Login.errorSso
        case .oidcFailed: L10n.Login.errorSso
        }
    }
}
