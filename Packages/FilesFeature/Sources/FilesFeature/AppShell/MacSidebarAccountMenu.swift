#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import Localization
    import SwiftUI

    /// The Mac sidebar's profile header opens this native account menu, so switching, adding
    /// and signing out never needs a trip to Settings. The accounts sit at the top with a
    /// checkmark on the active one (choosing another switches to it), then the account actions.
    /// Only emits `SettingsFeature` intent; the switch, add and remove work stays upstream.
    struct MacSidebarAccountMenu<Label: View>: View {
        let store: StoreOf<SettingsFeature>
        /// Change Password opens as a window sheet, from whichever section is on screen.
        let onChangePassword: () -> Void
        @ViewBuilder let label: () -> Label

        @Environment(\.openSettings) private var openSettings

        private var accounts: [AccountSummary] {
            store.accounts.isEmpty ? [store.activeAccount] : store.accounts
        }

        private var otherAccounts: [AccountSummary] {
            accounts.filter { !$0.isActive }
        }

        private var activeAccountID: Binding<String> {
            Binding(get: { store.activeAccount.id }, set: { id in
                if id != store.activeAccount.id {
                    store.send(.switchAccountTapped(id))
                }
            })
        }

        var body: some View {
            Menu {
                Picker(L10n.Settings.sectionAccounts, selection: activeAccountID) {
                    ForEach(accounts) { account in
                        Text(account.displayName)
                        Text(account.serverHost)
                    }
                }
                .pickerStyle(.inline)
                Divider()
                Button(L10n.MacSettings.addAccount) { store.send(.addAccountTapped) }
                Button(L10n.MacSettings.changePassword, action: onChangePassword)
                Button(L10n.Tab.settings + "…") { openSettings() }
                Divider()
                if !otherAccounts.isEmpty {
                    Menu(L10n.Settings.accountSignOut) {
                        ForEach(otherAccounts) { account in
                            Button(account.displayName + " (" + account.serverHost + ")") {
                                store.send(.removeAccountTapped(account))
                            }
                        }
                    }
                }
                Button(L10n.MacSettings.signOut, role: .destructive) { store.send(.signOutButtonTapped) }
            } label: {
                label()
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .disabled(store.isSigningOut)
            .accessibilityLabel(L10n.Settings.sectionAccounts)
        }
    }
#endif
