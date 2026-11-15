import ComposableArchitecture
import CoreModels
import FilesClient
import FolderPickerFeature
import Foundation

/// The signed in user changing their own local password via `POST /api/auth/password`,
/// mirroring the web client's `SettingsPassword.vue`. Reached from a row next to Sign Out.
///
/// An account that only ever signed in through single sign on has no password to change, so the
/// same screen runs in `.add` mode: no current password, `POST /api/auth/password/add`.
///
/// No profile editing here: the backend has no self service profile endpoint
/// (`PATCH /api/users/:id` is admin only), so display name changes go through User Management.
@Reducer
public struct ChangePasswordFeature {
    /// Semantic field errors; the view maps them to `L10n`.
    public enum NewPasswordError: Equatable, Sendable {
        case tooShort(minimum: Int)
    }

    public enum ConfirmPasswordError: Equatable, Sendable {
        case mismatch
    }

    public enum Mode: Equatable, Sendable {
        case change
        case add
    }

    @ObservableState
    public struct State: Equatable {
        public let serverURL: URL
        public let mode: Mode
        public var currentPassword = ""
        public var newPassword = ""
        public var confirmPassword = ""
        public var isSubmitting = false
        public var errorMessage: String?
        public var didSucceed = false

        public init(serverURL: URL, mode: Mode = .change) {
            self.serverURL = serverURL
            self.mode = mode
        }

        /// Shown once the field has content. An empty field is "not filled in yet", not wrong.
        var newPasswordError: NewPasswordError? {
            newPassword.isEmpty || CredentialRules.isPasswordLongEnough(newPassword)
                ? nil
                : .tooShort(minimum: CredentialRules.minimumPasswordLength)
        }

        var confirmError: ConfirmPasswordError? {
            confirmPassword.isEmpty || confirmPassword == newPassword ? nil : .mismatch
        }

        var isSubmitEnabled: Bool {
            (mode == .add || !currentPassword.isEmpty)
                && CredentialRules.isPasswordLongEnough(newPassword)
                && newPassword == confirmPassword
                && !isSubmitting
        }
    }

    public enum Action: Equatable, Sendable {
        case currentPasswordChanged(String)
        case newPasswordChanged(String)
        case confirmPasswordChanged(String)
        case submitTapped
        case response(Result<Bool, FilesClientError>)
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            /// The account now has a password, so the Settings row stops offering to add one.
            case passwordAdded
        }
    }

    @Dependency(\.filesClient) var filesClient

    private enum CancelID { case submit }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .currentPasswordChanged(value):
                state.currentPassword = value
                state.didSucceed = false
                return .none

            case let .newPasswordChanged(value):
                state.newPassword = value
                state.didSucceed = false
                return .none

            case let .confirmPasswordChanged(value):
                state.confirmPassword = value
                state.didSucceed = false
                return .none

            case .submitTapped:
                guard state.isSubmitEnabled else { return .none }
                state.isSubmitting = true
                state.errorMessage = nil
                state.didSucceed = false
                let serverURL = state.serverURL
                let current = state.currentPassword
                let new = state.newPassword
                let mode = state.mode
                let filesClient = filesClient
                return .run { send in
                    try await send(.response(apiResult {
                        switch mode {
                        case .change: try await filesClient.changeOwnPassword(serverURL, current, new)
                        case .add: try await filesClient.addOwnPassword(serverURL, new)
                        }
                        return true
                    }))
                }
                .cancellable(id: CancelID.submit, cancelInFlight: true)

            case .response(.success):
                state.isSubmitting = false
                state.currentPassword = ""
                state.newPassword = ""
                state.confirmPassword = ""
                state.didSucceed = true
                return state.mode == .add ? .send(.delegate(.passwordAdded)) : .none

            case let .response(.failure(error)):
                state.isSubmitting = false
                state.errorMessage = error.userMessage
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
