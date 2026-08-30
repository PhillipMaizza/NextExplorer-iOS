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

            case let .hostChanged(text):
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
                state.identifier = text
                return .none

            case let .passwordChanged(text):
                state.password = text
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
                guard status.localEnabled else {
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
            .cancel(id: CancelID.submitRevert)
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
    static func isValidEmail(_ text: String) -> Bool {
        text.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }

    /// Strips whitespace, a leading scheme the user may have typed or pasted, and any trailing
    /// slashes before validating the host.
    static func normalizedURL(scheme: URLScheme, host: String) -> URL? {
        var trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://"] where trimmedHost.lowercased().hasPrefix(prefix) {
            trimmedHost.removeFirst(prefix.count)
            break
        }
        while trimmedHost.hasSuffix("/") {
            trimmedHost.removeLast()
        }
        guard !trimmedHost.isEmpty, let components = URLComponents(string: "\(scheme.rawValue)://\(trimmedHost)"),
              components.host != nil else {
            return nil
        }
        return components.url
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
        case .server: L10n.Login.errorDecoding
        case .noAuthMethodsEnabled: L10n.Login.errorNoLocalAuth
        case .rateLimited: L10n.Login.errorRateLimited
        }
    }
}
