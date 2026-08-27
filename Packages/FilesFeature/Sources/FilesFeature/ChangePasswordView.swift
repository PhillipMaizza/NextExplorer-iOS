import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Metrics {
    static let contentSpacing: CGFloat = .space16
    static let horizontalPadding: CGFloat = .space16
    static let cardCornerRadius: CGFloat = .radiusMedium
    static let cardPadding: CGFloat = .space12
    static let rowIconSize: CGFloat = .iconSmall
}

/// Self service password change, pushed from the Settings sign out row. Mirrors the web
/// client's `SettingsPassword.vue`.
struct ChangePasswordView: View {
    @Bindable var store: StoreOf<ChangePasswordFeature>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
                HStack(alignment: .top, spacing: .space8) {
                    IconKit.key
                        .resizable().scaledToFit()
                        .foregroundStyle(Color.secondaryDS)
                        .frame(width: Metrics.rowIconSize, height: Metrics.rowIconSize)
                        .padding(.top, .space2)
                    Text(L10n.ChangePassword.intro)
                        .type(.body3(.regular), style: .secondary)
                }

                if let error = store.errorMessage {
                    ErrorBanner(text: error)
                }
                if store.didSucceed {
                    successBanner(L10n.ChangePassword.success)
                }

                LabeledField(L10n.ChangePassword.fieldCurrentPassword) {
                    SecureField(L10n.ChangePassword.fieldCurrentPassword, text: $store.currentPassword.sending(\.currentPasswordChanged))
                        .textContentType(.password)
                }
                LabeledField(L10n.ChangePassword.fieldNewPasswordLabel, error: newPasswordErrorText) {
                    SecureField(L10n.ChangePassword.fieldNewPasswordPrompt(CredentialRules.minimumPasswordLength), text: $store.newPassword.sending(\.newPasswordChanged))
                        .textContentType(.newPassword)
                }
                LabeledField(L10n.ChangePassword.fieldConfirmPasswordLabel, error: confirmErrorText) {
                    SecureField(L10n.ChangePassword.fieldConfirmPassword, text: $store.confirmPassword.sending(\.confirmPasswordChanged))
                        .textContentType(.newPassword)
                }

                DSButton(L10n.ChangePassword.submitButton, style: .primary, isLoading: store.isSubmitting) {
                    store.send(.submitTapped)
                }
                .disabled(!store.isSubmitEnabled)
                .padding(.top, .space4)
            }
            .padding(.horizontal, Metrics.horizontalPadding)
            .padding(.vertical, Metrics.contentSpacing)
        }
        .background(Color.backgroundPrimary)
        .navigationTitle(L10n.ChangePassword.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
    }

    private var newPasswordErrorText: String? {
        guard let error = store.newPasswordError else { return nil }
        switch error {
        case let .tooShort(minimum): return L10n.ChangePassword.errorMinLength(minimum)
        }
    }

    private var confirmErrorText: String? {
        guard let error = store.confirmError else { return nil }
        switch error {
        case .mismatch: return L10n.ChangePassword.errorMismatch
        }
    }

    private func successBanner(_ text: String) -> some View {
        Text(text)
            .type(.body3(.regular), style: .success)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Metrics.cardPadding)
            .background(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius).fill(Color.positive.opacity(0.12)))
    }
}

#Preview("Empty") {
    NavigationStack {
        ChangePasswordView(
            store: Store(initialState: ChangePasswordFeature.State(
                serverURL: URL(string: "https://nextexplorer.example.com")!
            )) {
                ChangePasswordFeature()
            }
        )
    }
}

#Preview("Error") {
    NavigationStack {
        ChangePasswordView(
            store: Store(initialState: {
                var state = ChangePasswordFeature.State(serverURL: URL(string: "https://x.example.com")!)
                state.currentPassword = "wrong"
                state.newPassword = "abcdef"
                state.confirmPassword = "abcdef"
                state.errorMessage = "Current password is incorrect."
                return state
            }()) {
                ChangePasswordFeature()
            }
        )
    }
}

#Preview("Success") {
    NavigationStack {
        ChangePasswordView(
            store: Store(initialState: {
                var state = ChangePasswordFeature.State(serverURL: URL(string: "https://x.example.com")!)
                state.didSucceed = true
                return state
            }()) {
                ChangePasswordFeature()
            }
        )
    }
}
