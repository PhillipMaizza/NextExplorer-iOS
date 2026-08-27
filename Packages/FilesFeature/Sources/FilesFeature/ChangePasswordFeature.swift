import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation

/// The signed in user changing their own local password via `POST /api/auth/password`,
/// mirroring the web client's `SettingsPassword.vue`. Reached from a row next to Sign Out.
///
/// No profile editing here: the backend has no self service profile endpoint
/// (`PATCH /api/users/:id` is admin only), so display name changes go through User Management.
@Reducer
public struct ChangePasswordFeature {
    @ObservableState
    public struct State: Equatable {
        public let serverURL: URL
        public var currentPassword = ""
        public var newPassword = ""
        public var confirmPassword = ""
        public var isSubmitting = false
        public var errorMessage: String?
        public var successMessage: String?

        public init(serverURL: URL) {
            self.serverURL = serverURL
        }

        /// Shown once the field has content. An empty field is "not filled in yet", not wrong.
        var newPasswordError: String? {
            newPassword.isEmpty || CredentialRules.isPasswordLongEnough(newPassword)
                ? nil
                : "Use at least \(CredentialRules.minimumPasswordLength) characters."
        }
        var confirmError: String? {
            confirmPassword.isEmpty || confirmPassword == newPassword ? nil : "Passwords don't match."
        }
        var isSubmitEnabled: Bool {
            !currentPassword.isEmpty
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
    }

    @Dependency(\.filesClient) var filesClient

    private enum CancelID { case submit }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .currentPasswordChanged(value):
                state.currentPassword = value
                state.successMessage = nil
                return .none

            case let .newPasswordChanged(value):
                state.newPassword = value
                state.successMessage = nil
                return .none

            case let .confirmPasswordChanged(value):
                state.confirmPassword = value
                state.successMessage = nil
                return .none

            case .submitTapped:
                guard state.isSubmitEnabled else { return .none }
                state.isSubmitting = true
                state.errorMessage = nil
                state.successMessage = nil
                let serverURL = state.serverURL
                let current = state.currentPassword
                let new = state.newPassword
                let filesClient = self.filesClient
                return .run { send in
                    await send(.response(await apiResult {
                        try await filesClient.changeOwnPassword(serverURL, current, new)
                        return true
                    }))
                }
                .cancellable(id: CancelID.submit, cancelInFlight: true)

            case .response(.success):
                state.isSubmitting = false
                state.currentPassword = ""
                state.newPassword = ""
                state.confirmPassword = ""
                state.successMessage = "Your password has been updated."
                return .none

            case let .response(.failure(error)):
                state.isSubmitting = false
                state.errorMessage = error.userMessage
                return .none
            }
        }
    }
}
