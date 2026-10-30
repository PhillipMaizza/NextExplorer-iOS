import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// The account sign out confirmations (and, on the Mac, Change Password as a sheet). Settings
/// hosts them on iOS; the Mac hosts them at the window level so its sidebar account popover can
/// raise them from any section. No op setters:
/// each sheet is dismiss disabled and only closes through `DSAlertSheet`'s own buttons, which
/// drive the reducer directly. Sign out tears down the whole authenticated scope on confirm, so
/// a SwiftUI initiated dismiss would land in a dead store.
private enum Metrics {
    static let sheetMinWidth: CGFloat = 440
    static let sheetMinHeight: CGFloat = 520
}

struct AccountConfirmations: ViewModifier {
    let store: StoreOf<SettingsFeature>
    var isEnabled = true

    #if os(macOS)
        /// The main window and the Settings window both host these; the one that was active when
        /// the prompt was raised shows it, so it never appears twice or behind the wrong window.
        @State private var isPromptOwner = false
    #endif

    private var isPromptPending: Bool {
        store.isConfirmingSignOut || store.accountPendingRemoval != nil || store.changePassword != nil
    }

    private var shouldShowPrompts: Bool {
        #if os(macOS)
            isEnabled && isPromptOwner
        #else
            isEnabled
        #endif
    }

    static var isHostedByWindow: Bool {
        #if os(macOS)
            true
        #else
            false
        #endif
    }

    /// Only the Mac window host presents Change Password; iOS pushes it inside Settings.
    private var changePasswordSheet: Binding<StoreOf<ChangePasswordFeature>?> {
        Binding(
            get: {
                guard shouldShowPrompts, Self.isHostedByWindow else { return nil }
                return store.scope(state: \.changePassword, action: \.changePassword.presented)
            },
            set: { newValue in
                if newValue == nil, store.changePassword != nil {
                    store.send(.changePassword(.dismiss))
                }
            }
        )
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: changePasswordSheet) { passwordStore in
                #if os(macOS)
                    MacChangePasswordSheet(store: passwordStore) { store.send(.changePassword(.dismiss)) }
                #else
                    NavigationStack {
                        ChangePasswordView(store: passwordStore)
                    }
                    .frame(minWidth: Metrics.sheetMinWidth, minHeight: Metrics.sheetMinHeight)
                #endif
            }
            .dsAlert(isPresented: Binding(get: { shouldShowPrompts && store.isConfirmingSignOut }, set: { _ in })) {
                DSAlertSheet(
                    icon: IconKit.signOut,
                    title: L10n.Settings.signOutAlertTitle,
                    message: L10n.Settings.signOutMessage,
                    confirmTitle: L10n.Common.logOut,
                    dismissTitle: L10n.Common.cancel,
                    role: .destructive,
                    isConfirmLoading: store.isSigningOut,
                    closeAccessibilityLabel: L10n.Common.close,
                    onConfirm: { store.send(.confirmSignOutTapped) },
                    onDismiss: { store.send(.cancelSignOutTapped) }
                )
            }
            .dsAlert(isPresented: Binding(get: { shouldShowPrompts && store.accountPendingRemoval != nil }, set: { _ in })) {
                DSAlertSheet(
                    icon: IconKit.signOut,
                    title: L10n.Settings.accountSignOutTitle,
                    message: L10n.Settings.accountSignOutMessage(store.accountPendingRemoval?.displayName ?? ""),
                    confirmTitle: L10n.Common.logOut,
                    dismissTitle: L10n.Common.cancel,
                    role: .destructive,
                    closeAccessibilityLabel: L10n.Common.close,
                    onConfirm: { store.send(.removeAccountConfirmed) },
                    onDismiss: { store.send(.removeAccountCancelled) }
                )
            }
        #if os(macOS)
            .onWindowPromptChange(of: isPromptPending) { _, isOwner in
                isPromptOwner = isOwner
            }
        #endif
    }
}

@MainActor
private func confirmationsPreview(_ mutate: (inout SettingsFeature.State) -> Void) -> some View {
    var state = SettingsFeature.State(
        serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
        user: User(id: "preview-user", username: "jdoe", email: "jane.doe@example.com", displayName: "Jane Doe")
    )
    mutate(&state)
    return Color.clear
        .previewCanvas(.sheet)
        .modifier(AccountConfirmations(store: Store(initialState: state) { SettingsFeature() } withDependencies: { $0.filesClient = .previewValue }))
}

#Preview("Sign out") {
    confirmationsPreview { $0.isConfirmingSignOut = true }
}

#Preview("Change password") {
    confirmationsPreview { $0.changePassword = ChangePasswordFeature.State(serverURL: $0.serverURL) }
}
