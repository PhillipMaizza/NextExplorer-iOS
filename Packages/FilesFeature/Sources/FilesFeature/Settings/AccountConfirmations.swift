import ComposableArchitecture
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
                guard isEnabled, Self.isHostedByWindow else { return nil }
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
                NavigationStack {
                    ChangePasswordView(store: passwordStore)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(L10n.Common.close) { store.send(.changePassword(.dismiss)) }
                            }
                        }
                }
                .frame(minWidth: Metrics.sheetMinWidth, minHeight: Metrics.sheetMinHeight)
            }
            .dsSheet(isPresented: Binding(get: { isEnabled && store.isConfirmingSignOut }, set: { _ in })) {
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
            .dsSheet(isPresented: Binding(get: { isEnabled && store.accountPendingRemoval != nil }, set: { _ in })) {
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
    }
}
