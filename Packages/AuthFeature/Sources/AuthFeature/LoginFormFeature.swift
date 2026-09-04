import AuthClient
import ComposableArchitecture
import CoreModels
import Foundation
import Localization

private enum Constants {
    /// A real homelab call can resolve near-instantly on a warm connection — hold the
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
    static let maxEmailLength = 254
    static let maxPasswordLength = 256
}

@Reducer
public struct LoginFormFeature {
    /// Effect identities so a stale in-flight call from a host/scheme the user has since
    /// abandoned can never land its result (or an auto-advance) on the current screen.
    private enum CancelID {
        case connectionTest
        case successAdvance
        case failureRevert
        case errorDismiss
        case submit
        case submitRevert
        case oidc
    }

    public enum URLScheme: String, CaseIterable, Equatable, Hashable, Sendable, Identifiable {
        case https
        case http

        public var id: String { rawValue }
        public var displayName: String { rawValue }
    }

    public enum Page: Equatable, Sendable {
        case server
        case credentials
    }

    public enum ConnectionPhase: Equatable, Sendable {
        case idle
        case testing
        case success
        case failure
    }

    /// The credentials-page submit button's morph state — full pill (`idle`), collapsed
    /// spinner (`submitting`), collapsed checkmark (`success`, held briefly so it reads before
    /// the app zooms in), collapsed X (`failure`, then re-expands to `idle`). Mirrors
    /// `ConnectionPhase`'s role for the server-page button.
    public enum SubmitPhase: Equatable, Sendable {
        case idle
        case submitting
        case success
        case failure
    }

    /// Which credential field(s) should shake/red-border for the current `errorMessage` — a
    /// locally-rejected non-email only implicates the email field, while a server-rejected
    /// email/password implicates both (the server never says which one was actually wrong).
    public enum InvalidFieldScope: Equatable, Sendable {
        case identifier
        case identifierAndPassword
    }

    @ObservableState
    public struct State: Equatable {
        public var currentPage: Page
        public var connectionPhase: ConnectionPhase
        public var scheme: URLScheme
        public var host: String
        /// The host last typed for the *other* scheme — swapped back in on `schemeChanged`
        /// so toggling https/http doesn't lose what was typed on either side.
        var savedOtherSchemeHost: String = ""
        /// Set once the user taps the scheme picker themselves, so typing doesn't then move it
        /// back under them. Cleared when the host is emptied or an explicit `http(s)://` is typed.
        var schemeWasSetByUser: Bool = false
        public var identifier: String
        public var password: String
        public var isPasswordVisible: Bool
        public var submitPhase: SubmitPhase
        /// A single lone in-flight flag for the SSO button while the web sheet + exchange run
        /// (per architecture rule #8, one mutation flag is fine; it is not a load lifecycle).
        public var isAuthenticatingOIDC: Bool
        public var errorMessage: String?
        public var invalidFieldsScope: InvalidFieldScope?
        public var authStatus: AuthStatus?

        public init(
            currentPage: Page = .server,
            connectionPhase: ConnectionPhase = .idle,
            scheme: URLScheme = .https,
            host: String = "",
            identifier: String = "",
            password: String = "",
            isPasswordVisible: Bool = false,
            submitPhase: SubmitPhase = .idle,
            isAuthenticatingOIDC: Bool = false,
            errorMessage: String? = nil,
            invalidFieldsScope: InvalidFieldScope? = nil,
            authStatus: AuthStatus? = nil
        ) {
            self.currentPage = currentPage
            self.connectionPhase = connectionPhase
            self.scheme = scheme
            self.host = host
            self.savedOtherSchemeHost = ""
            self.identifier = identifier
            self.password = password
            self.isPasswordVisible = isPasswordVisible
            self.submitPhase = submitPhase
            self.isAuthenticatingOIDC = isAuthenticatingOIDC
            self.errorMessage = errorMessage
            self.invalidFieldsScope = invalidFieldsScope
            self.authStatus = authStatus
        }

        public var isSubmitting: Bool { submitPhase == .submitting }

        /// Any edit to the server URL, or pressing back, invalidates whatever the last
        /// Test Connection call found — the whole handshake starts over.
        mutating func resetConnection() {
            currentPage = .server
            connectionPhase = .idle
            submitPhase = .idle
            isAuthenticatingOIDC = false
            authStatus = nil
            errorMessage = nil
            invalidFieldsScope = nil
        }
    }

    public enum Action: Equatable, Sendable {
        case schemeChanged(URLScheme)
        case hostChanged(String)
        case identifierChanged(String)
        case passwordChanged(String)
        case togglePasswordVisibility
        case testConnectionButtonTapped
        case testConnectionResponse(Result<AuthStatus, AuthClientError>)
        case advanceToCredentials
        case revertToIdle
        case revertSubmitToIdle
        case clearErrorMessage
        case backButtonTapped
        case continueButtonTapped
        case submitSucceeded(User, URL)
        case submitFailed(AuthClientError)
        case ssoButtonTapped
        case oidcResponse(Result<User, AuthClientError>, URL)
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case authenticated(User, URL)
        }
    }

    @Dependency(\.authClient) var authClient
    @Dependency(\.continuousClock) var clock

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .schemeChanged(scheme):
                let previousHost = state.host
                state.host = state.savedOtherSchemeHost
                state.savedOtherSchemeHost = previousHost
                state.scheme = scheme
                state.schemeWasSetByUser = true
                state.resetConnection()
                return Self.cancelInFlightWork()

            case let .hostChanged(rawText):
                let text = String(rawText.prefix(Constants.maxHostInputLength))
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
                    // case the user fixes with the picker — and then it sticks.
                    state.scheme = first.isNumber ? .http : .https
                }
                state.resetConnection()
                return Self.cancelInFlightWork()

            case let .identifierChanged(text):
                state.identifier = String(text.prefix(Constants.maxEmailLength))
                return .none

            case let .passwordChanged(text):
                state.password = String(text.prefix(Constants.maxPasswordLength))
                return .none

            case .togglePasswordVisibility:
                state.isPasswordVisible.toggle()
                return .none

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
                let authClient = self.authClient
                let clock = self.clock
                return .merge(
                    .cancel(id: CancelID.successAdvance),
                    .run { send in
                        async let statusResult = Self.fetchStatusResult(authClient, url)
                        try? await clock.sleep(for: Constants.minimumSpinnerDuration)
                        await send(.testConnectionResponse(await statusResult))
                    }
                    .cancellable(id: CancelID.connectionTest, cancelInFlight: true)
                )

            case let .testConnectionResponse(.success(status)):
                state.authStatus = status
                let clock = self.clock
                guard status.localEnabled || status.oidcEnabled else {
                    state.connectionPhase = .failure
                    state.errorMessage = Self.message(for: .noAuthMethodsEnabled)
                    return .merge(Self.scheduleRevertToIdle(clock), Self.scheduleErrorDismiss(clock))
                }
                state.connectionPhase = .success
                return .run { send in
                    try await clock.sleep(for: Constants.successDisplayDuration)
                    await send(.advanceToCredentials)
                }
                .cancellable(id: CancelID.successAdvance, cancelInFlight: true)

            case let .testConnectionResponse(.failure(error)):
                state.connectionPhase = .failure
                state.authStatus = nil
                state.errorMessage = Self.message(for: error)
                return .merge(Self.scheduleRevertToIdle(self.clock), Self.scheduleErrorDismiss(self.clock))

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
                guard state.authStatus?.localEnabled == true,
                      let url = Self.normalizedURL(scheme: state.scheme, host: state.host) else {
                    return .none
                }
                let identifier = state.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
                guard Self.isValidEmail(identifier) else {
                    state.errorMessage = L10n.Login.errorInvalidEmail
                    state.invalidFieldsScope = .identifier
                    return Self.scheduleErrorDismiss(self.clock)
                }
                state.submitPhase = .submitting
                state.errorMessage = nil
                state.invalidFieldsScope = nil
                let password = state.password
                let authClient = self.authClient
                let clock = self.clock
                return .run { send in
                    async let result = Self.loginResult(authClient, url, identifier, password)
                    // Hold the spinner up briefly so it reads even when the call resolves fast.
                    try? await clock.sleep(for: Constants.minimumSpinnerDuration)
                    switch await result {
                    case let .success(user): await send(.submitSucceeded(user, url))
                    case let .failure(error): await send(.submitFailed(error))
                    }
                }
                .cancellable(id: CancelID.submit, cancelInFlight: true)

            case let .submitSucceeded(user, url):
                state.submitPhase = .success
                let clock = self.clock
                // Hold the checkmark a beat before handing off, so the button's success state
                // registers ahead of the zoom into the app.
                return .run { send in
                    try await clock.sleep(for: Constants.successDisplayDuration)
                    await send(.delegate(.authenticated(user, url)))
                }
                .cancellable(id: CancelID.successAdvance, cancelInFlight: true)

            case let .submitFailed(error):
                state.submitPhase = .failure
                state.errorMessage = Self.message(for: error)
                state.invalidFieldsScope = (error == .invalidCredentials) ? .identifierAndPassword : nil
                // `.sessionCookieMissing` means the sign-in itself completed but the app
                // couldn't pick up a session from it — not a typo the user can just retry past.
                // It stays on screen until the next submit attempt or navigation reset clears
                // it, instead of silently vanishing after a few seconds.
                guard error != .sessionCookieMissing else {
                    return Self.scheduleSubmitRevert(self.clock)
                }
                return .merge(Self.scheduleSubmitRevert(self.clock), Self.scheduleErrorDismiss(self.clock))

            case .ssoButtonTapped:
                guard state.authStatus?.oidcEnabled == true,
                      !state.isAuthenticatingOIDC,
                      let url = Self.normalizedURL(scheme: state.scheme, host: state.host) else {
                    return .none
                }
                state.isAuthenticatingOIDC = true
                state.errorMessage = nil
                state.invalidFieldsScope = nil
                let authClient = self.authClient
                return .run { send in
                    await send(.oidcResponse(await Self.loginOIDCResult(authClient, url), url))
                }
                .cancellable(id: CancelID.oidc, cancelInFlight: true)

            case let .oidcResponse(.success(user), url):
                state.isAuthenticatingOIDC = false
                return .send(.delegate(.authenticated(user, url)))

            case let .oidcResponse(.failure(error), _):
                state.isAuthenticatingOIDC = false
                // A user dismissing the web sheet is a cancellation, not a failure: leave the
                // screen as it was with no error banner.
                guard error != .oidcCancelled else { return .none }
                state.errorMessage = Self.message(for: error)
                return Self.scheduleErrorDismiss(self.clock)

            case .delegate:
                return .none
            }
        }
    }

    /// Cancels every in-flight network/timer effect this feature can have running.
    /// Called whenever the user abandons the current handshake (edits the host/scheme,
    /// or backs out) so a stale response can never land on a screen the user has since
    /// moved on from — e.g. an old Test Connection call auto-advancing to credentials
    /// after the user has already typed a different host.
    static func cancelInFlightWork() -> Effect<Action> {
        .merge(
            .cancel(id: CancelID.connectionTest),
            .cancel(id: CancelID.successAdvance),
            .cancel(id: CancelID.failureRevert),
            .cancel(id: CancelID.errorDismiss),
            .cancel(id: CancelID.submit),
            .cancel(id: CancelID.submitRevert),
            .cancel(id: CancelID.oidc)
        )
    }

    /// After a failed Test Connection, the button briefly shows a red X, then re-expands to
    /// the idle "Test connection" label so the user can retry — `errorMessage` stays set and
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

    /// Basic shape check (`x@y.z`) — the server is the real source of truth on whether the
    /// address exists, this only catches "clearly not an email" before spending a network call.
    /// Shares the one regex in `CredentialRules` so login and user management stay in lockstep.
    static func isValidEmail(_ text: String) -> Bool {
        CredentialRules.isEmailShaped(text)
    }

    /// Reduces whatever the user typed or pasted to a bare `host[:port]` and rejects anything
    /// that isn't a plausible server address before a network call is ever spent. Strips (in
    /// order): surrounding whitespace, a leading `http(s)://`, any `/path`, `?query` or
    /// `#fragment`, and a `user:pass@` userinfo prefix. What remains must be a valid host
    /// (hostname, IPv4, or bracketed IPv6) with, at most, one numeric port in `1...65535`.
    /// A pasted `https://user@box.local:3000/files?x=1` becomes `http(s)://box.local:3000`.
    static func normalizedURL(scheme: URLScheme, host: String) -> URL? {
        var text = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...Constants.maxHostInputLength).contains(text.count) else { return nil }

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
        // bare host may carry at most one colon, the port separator — anything else (an
        // unbracketed IPv6, a stray colon) is rejected rather than guessed at.
        var hostPart = text
        var portPart: Substring?
        if text.hasPrefix("[") {
            guard let close = text.firstIndex(of: "]") else { return nil }
            hostPart = String(text[text.index(after: text.startIndex)..<close])
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
            guard let port = Int(portPart), (1...65535).contains(port) else { return nil }
        }
        guard isValidHost(hostPart) else { return nil }

        var components = URLComponents()
        components.scheme = scheme.rawValue
        // Foundation does not auto-bracket an IPv6 literal, and an unbracketed one yields a
        // malformed URL — so re-wrap it before handing the host back to URLComponents.
        components.host = hostPart.contains(":") ? "[\(hostPart)]" : hostPart
        components.port = portPart.flatMap { Int($0) }
        guard let url = components.url else { return nil }
        return url
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
            return .success(try await authClient.fetchStatus(url))
        } catch {
            return .failure(mapError(error))
        }
    }

    static func loginResult(_ authClient: AuthClient, _ url: URL, _ identifier: String, _ password: String) async -> Result<User, AuthClientError> {
        do {
            return .success(try await authClient.login(url, identifier, password))
        } catch {
            return .failure(mapError(error))
        }
    }

    static func loginOIDCResult(_ authClient: AuthClient, _ url: URL) async -> Result<User, AuthClientError> {
        do {
            return .success(try await authClient.loginOIDC(url))
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
        case .oidcCancelled: L10n.Login.errorSso
        case .oidcFailed: L10n.Login.errorSso
        }
    }
}
