import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Metrics {
    static let sheetContentSpacing: CGFloat = .space24
    static let sheetHorizontalPadding: CGFloat = .space24
    static let sheetMaxHeightFraction: CGFloat = 0.9
}

// MARK: Create User sheet

struct CreateUserSheet: View {
    @Bindable var store: StoreOf<UserManagementFeature>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DSDynamicHeightSheet(maxHeightFraction: Metrics.sheetMaxHeightFraction) {
            VStack(alignment: .leading, spacing: Metrics.sheetContentSpacing) {
                DSSheetHeader(
                    icon: IconKit.people,
                    title: L10n.UserManagement.createNavigationTitle,
                    closeAccessibilityLabel: L10n.Common.close,
                    onClose: { dismiss() }
                )

                if let sheet = store.createSheet {
                    if let error = sheet.errorMessage {
                        DSErrorCard(error)
                    }
                    LabeledField(L10n.UserManagement.createEmailField, error: sheet.emailError, uppercased: false) {
                        DSTextField(
                            L10n.UserManagement.createEmailPlaceholder,
                            text: fieldBinding(\.email, UserManagementFeature.Action.createEmailChanged)
                        )
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    }
                    LabeledField(
                        L10n.UserManagement.createUsernameField,
                        error: sheet.usernameError,
                        uppercased: false
                    ) {
                        DSTextField(
                            L10n.UserManagement.createUsernamePlaceholder,
                            text: fieldBinding(\.username, UserManagementFeature.Action.createUsernameChanged)
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    }
                    LabeledField(L10n.Common.password, error: sheet.passwordError, uppercased: false) {
                        DSSecureField(
                            L10n.UserManagement.createPasswordPlaceholder(CredentialRules.minimumPasswordLength),
                            text: fieldBinding(\.password, UserManagementFeature.Action.createPasswordChanged)
                        )
                    }
                    DSToggleRow(
                        title: L10n.UserManagement.createGrantAdminToggle,
                        subtitle: L10n.UserManagement.createGrantAdminSubtitle,
                        icon: IconKit.shield,
                        isOn: Binding(
                            get: { store.createSheet?.isAdmin ?? false },
                            set: { store.send(.createIsAdminChanged($0)) }
                        )
                    )
                }
            }
            .padding(.horizontal, Metrics.sheetHorizontalPadding)
            .padding(.vertical, Metrics.sheetContentSpacing)
        } footer: {
            DSSheetFooter {
                DSButton(
                    L10n.UserManagement.createSubmit,
                    style: .primary,
                    isLoading: store.createSheet?.isSubmitting ?? false
                ) {
                    store.send(.createSubmitTapped)
                }
                .disabled(!(store.createSheet?.isSubmitEnabled ?? false))
            }
        }
    }

    private func fieldBinding(
        _ keyPath: KeyPath<UserManagementFeature.CreateUserState, String>,
        _ action: @escaping (String) -> UserManagementFeature.Action
    ) -> Binding<String> {
        Binding(
            get: { store.createSheet?[keyPath: keyPath] ?? "" },
            set: { store.send(action($0)) }
        )
    }
}

// MARK: Set password sheet

struct SetPasswordSheet: View {
    @Bindable var store: StoreOf<UserManagementFeature>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DSDynamicHeightSheet(maxHeightFraction: Metrics.sheetMaxHeightFraction) {
            VStack(alignment: .leading, spacing: Metrics.sheetContentSpacing) {
                DSSheetHeader(
                    icon: IconKit.key,
                    title: L10n.UserManagement.setPasswordNavigationTitle,
                    closeAccessibilityLabel: L10n.Common.close,
                    onClose: { dismiss() }
                )

                if let sheet = store.passwordSheet {
                    if let error = sheet.errorMessage {
                        DSErrorCard(error)
                    }
                    Text(sheet.hasExistingPassword
                        ? L10n.UserManagement.setPasswordResetIntro(sheet.userLabel)
                        : L10n.UserManagement.setPasswordSetIntro(sheet.userLabel))
                        .type(.body3(.regular), style: .secondary)

                    LabeledField(
                        L10n.UserManagement.setPasswordNewField,
                        error: sheet.passwordError,
                        uppercased: false
                    ) {
                        DSSecureField(
                            L10n.UserManagement.setPasswordPlaceholder(CredentialRules.minimumPasswordLength),
                            text: Binding(
                                get: { store.passwordSheet?.password ?? "" },
                                set: { store.send(.passwordFieldChanged($0)) }
                            )
                        )
                    }
                }
            }
            .padding(.horizontal, Metrics.sheetHorizontalPadding)
            .padding(.vertical, Metrics.sheetContentSpacing)
        } footer: {
            DSSheetFooter {
                DSButton(
                    (store.passwordSheet?.hasExistingPassword ?? false)
                        ? L10n.UserManagement.setPasswordResetTitle
                        : L10n.UserManagement.setPasswordSetTitle,
                    style: .primary,
                    isLoading: store.passwordSheet?.isSubmitting ?? false
                ) {
                    store.send(.passwordSubmitTapped)
                }
                .disabled(!(store.passwordSheet?.isSubmitEnabled ?? false))
            }
        }
    }
}

@MainActor
private func sheetPreview(
    _ sheet: (StoreOf<UserManagementFeature>) -> some View,
    mutate: (inout UserManagementFeature.State) -> Void
) -> some View {
    let content = sheet(Store(initialState: previewListState(mutate)) { UserManagementFeature() })
    return Color.clear.dsSheet(isPresented: .constant(true)) { content }
}

#Preview("Create user") {
    sheetPreview(CreateUserSheet.init) { $0.createSheet = UserManagementFeature.CreateUserState() }
}

#Preview("Create user: username taken") {
    sheetPreview(CreateUserSheet.init) {
        $0.createSheet = UserManagementFeature.CreateUserState(username: "jamie", takenUsernames: ["jamie"])
    }
}

#Preview("Create user: error") {
    sheetPreview(CreateUserSheet.init) {
        var sheet = UserManagementFeature.CreateUserState()
        sheet.email = "jane@"
        sheet.username = "jane"
        sheet.errorMessage = L10n.UserManagement.errorEmailInvalid
        $0.createSheet = sheet
    }
}

#Preview("Set password") {
    sheetPreview(SetPasswordSheet.init) {
        $0.passwordSheet = UserManagementFeature.PasswordSheetState(
            userID: "u2",
            userLabel: "Jane Doe",
            hasExistingPassword: false
        )
    }
}

#Preview("Replace password") {
    sheetPreview(SetPasswordSheet.init) {
        $0.passwordSheet = UserManagementFeature.PasswordSheetState(
            userID: "u2",
            userLabel: "Jane Doe",
            hasExistingPassword: true,
            password: "short"
        )
    }
}
