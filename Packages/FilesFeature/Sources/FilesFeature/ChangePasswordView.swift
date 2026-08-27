import ComposableArchitecture
import DesignSystem
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
                    Text("Change the password you use to sign in with your email address. You'll stay signed in on this device.")
                        .type(.body3(.regular), style: .secondary)
                }

                if let error = store.errorMessage {
                    ErrorBanner(text: error)
                }
                if let success = store.successMessage {
                    successBanner(success)
                }

                LabeledField("Current password") {
                    SecureField("Current password", text: $store.currentPassword.sending(\.currentPasswordChanged))
                        .textContentType(.password)
                }
                LabeledField("New password", error: store.newPasswordError) {
                    SecureField("At least 6 characters", text: $store.newPassword.sending(\.newPasswordChanged))
                        .textContentType(.newPassword)
                }
                LabeledField("Confirm new password", error: store.confirmError) {
                    SecureField("Re-enter new password", text: $store.confirmPassword.sending(\.confirmPasswordChanged))
                        .textContentType(.newPassword)
                }

                DSButton("Update Password", style: .primary, isLoading: store.isSubmitting) {
                    store.send(.submitTapped)
                }
                .disabled(!store.isSubmitEnabled)
                .padding(.top, .space4)
            }
            .padding(.horizontal, Metrics.horizontalPadding)
            .padding(.vertical, Metrics.contentSpacing)
        }
        .background(Color.backgroundPrimary)
        .navigationTitle("Change Password")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
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
                state.successMessage = "Your password has been updated."
                return state
            }()) {
                ChangePasswordFeature()
            }
        )
    }
}
