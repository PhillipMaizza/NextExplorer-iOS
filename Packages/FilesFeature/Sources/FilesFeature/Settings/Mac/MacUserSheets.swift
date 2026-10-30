#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import Localization
    import SwiftUI

    /// Create User as a native sheet: email, optional username, password and the admin switch.
    struct MacCreateUserSheet: View {
        let store: StoreOf<UserManagementFeature>

        var body: some View {
            let sheet = store.createSheet
            MacFormSheet(
                title: L10n.UserManagement.createNavigationTitle,
                confirmTitle: L10n.UserManagement.createSubmit,
                isConfirmEnabled: sheet?.isSubmitEnabled ?? false,
                isWorking: sheet?.isSubmitting ?? false,
                errorMessage: sheet?.errorMessage,
                onCancel: { store.send(.createSheetDismissed) },
                onConfirm: { store.send(.createSubmitTapped) }
            ) {
                MacSettingsRow(L10n.UserManagement.createEmailField) {
                    TextField(L10n.UserManagement.createEmailField, text: field(\.email, UserManagementFeature.Action.createEmailChanged), prompt: Text(L10n.UserManagement.createEmailPlaceholder))
                        .labelsHidden()
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                    MacFieldError(message: sheet?.emailError)
                }
                MacSettingsRow(L10n.UserManagement.createUsernameField) {
                    TextField(L10n.UserManagement.createUsernameField, text: field(\.username, UserManagementFeature.Action.createUsernameChanged), prompt: Text(L10n.UserManagement.createUsernamePlaceholder))
                        .labelsHidden()
                        .autocorrectionDisabled()
                }
                MacSettingsRow(L10n.Common.password) {
                    SecureField(L10n.Common.password, text: field(\.password, UserManagementFeature.Action.createPasswordChanged), prompt: Text(L10n.UserManagement.createPasswordPlaceholder(CredentialRules.minimumPasswordLength)))
                        .labelsHidden()
                    MacFieldError(message: sheet?.passwordError)
                }
                MacSettingsRow(L10n.UserDetail.sectionRoles) {
                    Toggle(L10n.UserManagement.createGrantAdminToggle, isOn: Binding(
                        get: { store.createSheet?.isAdmin ?? false },
                        set: { store.send(.createIsAdminChanged($0)) }
                    ))
                    MacSettingsNote(L10n.UserManagement.createGrantAdminSubtitle)
                }
            }
        }

        private func field(
            _ keyPath: KeyPath<UserManagementFeature.CreateUserState, String>,
            _ action: @escaping @Sendable (String) -> UserManagementFeature.Action
        ) -> Binding<String> {
            Binding(get: { store.createSheet?[keyPath: keyPath] ?? "" }, set: { store.send(action($0)) })
        }
    }

    /// Set or reset a user's local password as a native sheet.
    struct MacSetPasswordSheet: View {
        let store: StoreOf<UserManagementFeature>

        var body: some View {
            let sheet = store.passwordSheet
            let isReset = sheet?.hasExistingPassword ?? false
            MacFormSheet(
                title: isReset ? L10n.UserManagement.setPasswordResetTitle : L10n.UserManagement.setPasswordSetTitle,
                confirmTitle: isReset ? L10n.UserManagement.setPasswordResetTitle : L10n.UserManagement.setPasswordSetTitle,
                isConfirmEnabled: sheet?.isSubmitEnabled ?? false,
                isWorking: sheet?.isSubmitting ?? false,
                errorMessage: sheet?.errorMessage,
                onCancel: { store.send(.passwordSheetDismissed) },
                onConfirm: { store.send(.passwordSubmitTapped) }
            ) {
                if let sheet {
                    MacSettingsNote(isReset
                        ? L10n.UserManagement.setPasswordResetIntro(sheet.userLabel)
                        : L10n.UserManagement.setPasswordSetIntro(sheet.userLabel))
                        .padding(.bottom, .space8)
                }
                MacSettingsRow(L10n.UserManagement.setPasswordNewField) {
                    SecureField(L10n.UserManagement.setPasswordNewField, text: Binding(
                        get: { store.passwordSheet?.password ?? "" },
                        set: { store.send(.passwordFieldChanged($0)) }
                    ), prompt: Text(L10n.UserManagement.setPasswordPlaceholder(CredentialRules.minimumPasswordLength)))
                        .labelsHidden()
                    MacFieldError(message: sheet?.passwordError)
                }
            }
        }
    }

    /// The signed in user's own password change, as a native sheet.
    struct MacChangePasswordSheet: View {
        @Bindable var store: StoreOf<ChangePasswordFeature>
        let onClose: () -> Void

        var body: some View {
            MacFormSheet(
                title: L10n.ChangePassword.navigationTitle,
                confirmTitle: L10n.ChangePassword.submitButton,
                isConfirmEnabled: store.isSubmitEnabled,
                isWorking: store.isSubmitting,
                errorMessage: store.errorMessage,
                cancelTitle: store.didSucceed ? L10n.Common.close : L10n.Common.cancel,
                onCancel: onClose,
                onConfirm: { store.send(.submitTapped) }
            ) {
                MacSettingsNote(L10n.ChangePassword.intro)
                    .padding(.bottom, .space8)
                MacSettingsRow(L10n.ChangePassword.fieldCurrentPassword) {
                    SecureField(L10n.ChangePassword.fieldCurrentPassword, text: $store.currentPassword.sending(\.currentPasswordChanged))
                        .labelsHidden()
                        .textContentType(.password)
                }
                MacSettingsRow(L10n.ChangePassword.fieldNewPasswordLabel) {
                    SecureField(L10n.ChangePassword.fieldNewPasswordLabel, text: $store.newPassword.sending(\.newPasswordChanged), prompt: Text(L10n.ChangePassword.fieldNewPasswordPrompt(CredentialRules.minimumPasswordLength)))
                        .labelsHidden()
                        .textContentType(.newPassword)
                    MacFieldError(message: newPasswordError)
                }
                MacSettingsRow(L10n.ChangePassword.fieldConfirmPasswordLabel) {
                    SecureField(L10n.ChangePassword.fieldConfirmPasswordLabel, text: $store.confirmPassword.sending(\.confirmPasswordChanged), prompt: Text(L10n.ChangePassword.fieldConfirmPassword))
                        .labelsHidden()
                        .textContentType(.newPassword)
                    MacFieldError(message: confirmError)
                }
                if store.didSucceed {
                    Text(L10n.ChangePassword.success).foregroundStyle(Color.positiveText)
                }
            }
        }

        private var newPasswordError: String? {
            guard case let .tooShort(minimum) = store.newPasswordError else { return nil }
            return L10n.ChangePassword.errorMinLength(minimum)
        }

        private var confirmError: String? {
            store.confirmError == .mismatch ? L10n.ChangePassword.errorMismatch : nil
        }
    }

    @MainActor
    private func userSheetsState() -> UserManagementFeature.State {
        UserManagementFeature.State(serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"), currentUserID: "u1")
    }

    #Preview("Create user") {
        var state = userSheetsState()
        state.createSheet = UserManagementFeature.CreateUserState()
        return MacCreateUserSheet(store: Store(initialState: state) { UserManagementFeature() })
    }

    #Preview("Create user error") {
        var state = userSheetsState()
        var sheet = UserManagementFeature.CreateUserState()
        sheet.email = "jane@example.com"
        sheet.errorMessage = "A user with this email already exists."
        state.createSheet = sheet
        return MacCreateUserSheet(store: Store(initialState: state) { UserManagementFeature() })
    }

    #Preview("Set password") {
        var state = userSheetsState()
        state.passwordSheet = UserManagementFeature.PasswordSheetState(userID: "u2", userLabel: "Jane Doe", hasExistingPassword: true)
        return MacSetPasswordSheet(store: Store(initialState: state) { UserManagementFeature() })
    }

    #Preview("Change password") {
        MacChangePasswordSheet(
            store: Store(initialState: ChangePasswordFeature.State(serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"))) {
                ChangePasswordFeature()
            },
            onClose: {}
        )
    }
#endif
