import ComposableArchitecture
import CoreModels
import FilesClient
import FolderPickerFeature
import Foundation

private enum Constants {
    /// The length of an authenticator app code, which the boxes and the auto confirm follow.
    static let codeLength = 6
    static let asciiDigits: Set<Character> = Set("0123456789")
}

/// The signed in account turning a second factor on or off, mirroring the web client's two factor
/// settings. Turning it on draws a secret (`POST /api/auth/totp/start`), shows it as a QR code and a
/// key, and only switches on once a code from the authenticator app proves it holds the same
/// secret (`POST /api/auth/totp/confirm`), which also hands over the first recovery codes.
/// Afterwards new recovery codes and turning it off both ask for the account password.
@Reducer
public struct TwoFactorFeature {
    /// Where the screen is. One phase rather than a handful of flags, so it can't be two things.
    public enum Phase: Equatable, Sendable {
        case loading
        case failed(String)
        case off
        case on(recoveryCodesLeft: Int)
        /// The secret is on screen and the next step is a code from the authenticator app.
        case enrolling(TwoFactorSetup)
        /// Shown once, right after turning it on or drawing new codes.
        case showingRecoveryCodes([String])
    }

    public enum PasswordAction: Equatable, Sendable {
        case newRecoveryCodes
        case turnOff
    }

    public struct PasswordPrompt: Equatable, Sendable {
        public var action: PasswordAction
        public var password = ""

        public init(action: PasswordAction) {
            self.action = action
        }
    }

    @ObservableState
    public struct State: Equatable {
        public let serverURL: URL
        public var phase: Phase = .loading
        public var code = ""
        /// One request in flight at a time: the screen has a single action under way.
        public var isWorking = false
        public var errorMessage: String?
        public var passwordPrompt: PasswordPrompt?

        public init(serverURL: URL, phase: Phase = .loading) {
            self.serverURL = serverURL
            self.phase = phase
        }

        public static var codeLength: Int {
            Constants.codeLength
        }

        var isPasswordPromptConfirmEnabled: Bool {
            guard let prompt = passwordPrompt else { return false }
            return !prompt.password.isEmpty && !isWorking
        }
    }

    public enum Action: Equatable, Sendable {
        case task
        case retryTapped
        case statusResponse(Result<TwoFactorStatus, FilesClientError>)
        case turnOnTapped
        case setupResponse(Result<TwoFactorSetup, FilesClientError>)
        case codeChanged(String)
        case confirmTapped
        case confirmResponse(Result<[String], FilesClientError>)
        case cancelSetupTapped
        case recoveryCodesDoneTapped
        case newRecoveryCodesTapped
        case turnOffTapped
        case passwordChanged(String)
        case passwordPromptCancelled
        case passwordPromptConfirmed
        case recoveryCodesResponse(Result<[String], FilesClientError>)
        case disableResponse(Result<Bool, FilesClientError>)
    }

    @Dependency(\.filesClient) var filesClient

    private enum CancelID {
        case load
        case action
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task, .retryTapped:
                state.phase = .loading
                state.errorMessage = nil
                return loadStatus(serverURL: state.serverURL)

            case let .statusResponse(.success(status)):
                state.phase = status.isEnabled ? .on(recoveryCodesLeft: status.recoveryCodesLeft) : .off
                return .none

            case let .statusResponse(.failure(error)):
                state.phase = .failed(error.userMessage)
                return .none

            case .turnOnTapped:
                guard state.phase == .off, !state.isWorking else { return .none }
                state.isWorking = true
                state.errorMessage = nil
                let serverURL = state.serverURL
                let filesClient = filesClient
                return .run { send in
                    try await send(.setupResponse(apiResult { try await filesClient.beginTwoFactorSetup(serverURL) }))
                }
                .cancellable(id: CancelID.action, cancelInFlight: true)

            case let .setupResponse(.success(setup)):
                state.isWorking = false
                state.code = ""
                state.phase = .enrolling(setup)
                return .none

            case let .setupResponse(.failure(error)):
                state.isWorking = false
                state.errorMessage = error.userMessage
                return .none

            case let .codeChanged(text):
                state.code = String(text.filter { Constants.asciiDigits.contains($0) }.prefix(Constants.codeLength))
                guard state.code.count == Constants.codeLength, !state.isWorking, case .enrolling = state.phase else {
                    return .none
                }
                return .send(.confirmTapped)

            case .confirmTapped:
                guard case .enrolling = state.phase,
                      state.code.count == Constants.codeLength,
                      !state.isWorking
                else {
                    return .none
                }
                state.isWorking = true
                state.errorMessage = nil
                let serverURL = state.serverURL
                let code = state.code
                let filesClient = filesClient
                return .run { send in
                    try await send(.confirmResponse(apiResult { try await filesClient.confirmTwoFactorSetup(
                        serverURL,
                        code
                    ) }))
                }
                .cancellable(id: CancelID.action, cancelInFlight: true)

            case let .confirmResponse(.success(codes)):
                state.isWorking = false
                state.code = ""
                state.phase = .showingRecoveryCodes(codes)
                return .none

            case let .confirmResponse(.failure(error)):
                state.isWorking = false
                state.errorMessage = error.userMessage
                // Six boxes of a wrong code would have to be erased one by one. A refusal clears
                // them; a dropped connection keeps what was typed.
                if case .serverMessage(401, _) = error {
                    state.code = ""
                }
                return .none

            case .cancelSetupTapped:
                state.phase = .off
                state.code = ""
                state.errorMessage = nil
                state.isWorking = false
                return .cancel(id: CancelID.action)

            case .recoveryCodesDoneTapped:
                guard case let .showingRecoveryCodes(codes) = state.phase else { return .none }
                state.phase = .on(recoveryCodesLeft: codes.count)
                return .none

            case .newRecoveryCodesTapped:
                guard case .on = state.phase, !state.isWorking else { return .none }
                state.errorMessage = nil
                state.passwordPrompt = PasswordPrompt(action: .newRecoveryCodes)
                return .none

            case .turnOffTapped:
                guard case .on = state.phase, !state.isWorking else { return .none }
                state.errorMessage = nil
                state.passwordPrompt = PasswordPrompt(action: .turnOff)
                return .none

            case let .passwordChanged(password):
                state.passwordPrompt?.password = password
                return .none

            case .passwordPromptCancelled:
                state.passwordPrompt = nil
                state.errorMessage = nil
                state.isWorking = false
                return .cancel(id: CancelID.action)

            case .passwordPromptConfirmed:
                guard let prompt = state.passwordPrompt, state.isPasswordPromptConfirmEnabled else { return .none }
                state.isWorking = true
                state.errorMessage = nil
                let serverURL = state.serverURL
                let password = prompt.password
                let filesClient = filesClient
                switch prompt.action {
                case .newRecoveryCodes:
                    return .run { send in
                        try await send(.recoveryCodesResponse(apiResult { try await filesClient.replaceRecoveryCodes(
                            serverURL,
                            password
                        ) }))
                    }
                    .cancellable(id: CancelID.action, cancelInFlight: true)
                case .turnOff:
                    return .run { send in
                        try await send(.disableResponse(apiResult {
                            try await filesClient.disableTwoFactor(serverURL, password)
                            return true
                        }))
                    }
                    .cancellable(id: CancelID.action, cancelInFlight: true)
                }

            case let .recoveryCodesResponse(.success(codes)):
                state.isWorking = false
                state.passwordPrompt = nil
                state.phase = .showingRecoveryCodes(codes)
                return .none

            case let .recoveryCodesResponse(.failure(error)):
                state.isWorking = false
                state.errorMessage = error.userMessage
                return .none

            case .disableResponse(.success):
                state.isWorking = false
                state.passwordPrompt = nil
                state.phase = .off
                return .none

            case let .disableResponse(.failure(error)):
                state.isWorking = false
                state.errorMessage = error.userMessage
                return .none
            }
        }
    }

    private func loadStatus(serverURL: URL) -> Effect<Action> {
        let filesClient = filesClient
        return .run { send in
            try await send(.statusResponse(apiResult { try await filesClient.fetchTwoFactorStatus(serverURL) }))
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }
}
