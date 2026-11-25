import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

struct SettingsSecuritySection: View {
    let store: StoreOf<SettingsFeature>

    var body: some View {
        Section {
            if store.shouldShowPasswordRow {
                DSNavigationRow(
                    title: store.passwordStatus == .absent
                        ? L10n.Settings.rowAddPassword
                        : L10n.Settings.rowChangePassword,
                    icon: IconKit.lock
                ) {
                    store.send(.changePasswordButtonTapped)
                }
                .disabled(store.isSigningOut)
            }
            if store.shouldShowTwoFactorRow {
                DSNavigationRow(title: L10n.TwoFactor.navigationTitle, icon: IconKit.shield) {
                    store.send(.twoFactorButtonTapped)
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.Settings.twoFactorRow)
                .disabled(store.isSigningOut)
            }
            NavigationLink {
                RequireSignInView(store: store)
            } label: {
                SettingsValueLabel(
                    title: L10n.Settings.rowRequireSignIn,
                    value: store.requireSignIn?.lockAfter.title ?? L10n.Common.off,
                    icon: IconKit.key
                )
                .fullRowHitArea()
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.Settings.requireSignInRow)
            .disabled(store.isSigningOut)
        } header: {
            SettingsSectionHeader(L10n.Settings.sectionSecurity)
        }
        .listRowBackground(Color.backgroundSecondary)
    }
}

extension StoreOf<SettingsFeature> {
    var requireSignIn: RequireSignIn? {
        state.activeAccount.requireSignIn
    }

    var isRequiringSignIn: Binding<Bool> {
        Binding(
            get: { self.requireSignIn != nil },
            set: { self.send(.requireSignInChanged($0 ? RequireSignIn() : nil)) }
        )
    }

    func requireSignIn<Value>(_ keyPath: WritableKeyPath<RequireSignIn, Value>) -> Binding<Value> {
        Binding(
            get: { (self.requireSignIn ?? RequireSignIn())[keyPath: keyPath] },
            set: { value in
                guard var updated = self.requireSignIn else { return }
                updated[keyPath: keyPath] = value
                self.send(.requireSignInChanged(updated))
            }
        )
    }
}

extension RequireSignIn.LockAfter {
    var title: String {
        switch self {
        case .appStart: L10n.RequireSignIn.appStart
        case .immediately: L10n.RequireSignIn.immediately
        case .thirtySeconds: L10n.RequireSignIn.thirtySeconds
        case .oneMinute: L10n.RequireSignIn.oneMinute
        case .fiveMinutes: L10n.RequireSignIn.fiveMinutes
        }
    }
}

#Preview("Password account") {
    NavigationStack {
        DSGroupedList {
            SettingsSecuritySection(store: Store(initialState: .preview) { SettingsFeature() })
        }
    }
}
