#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    /// The Mac sidebar's profile header as an account menu, so switching, adding and signing out
    /// never needs a trip to Settings: every account (the active one checked), Add Account, Change
    /// Password, and Sign Out for any account. Only emits `SettingsFeature` intent; the switch,
    /// add and remove work stays upstream as in the Settings rows it replaces.
    struct MacSidebarAccountMenu<Label: View>: View {
        let store: StoreOf<SettingsFeature>
        /// Change Password opens inside Settings, so the caller switches to that section first.
        let onChangePassword: () -> Void
        @ViewBuilder let label: () -> Label

        var body: some View {
            Menu {
                Section(L10n.Settings.sectionAccounts) {
                    // Toggles, so the active account carries the menu's native checkmark.
                    ForEach(accounts) { account in
                        Toggle(title(for: account), isOn: Binding(
                            get: { account.isActive },
                            set: { _ in store.send(.switchAccountTapped(account.id)) }
                        ))
                    }
                }
                Section {
                    Button { store.send(.addAccountTapped) } label: {
                        SwiftUI.Label { Text(L10n.Settings.addAccount + "…") } icon: { IconKit.plus }
                    }
                    Button(action: onChangePassword) {
                        SwiftUI.Label { Text(L10n.Settings.rowChangePassword + "…") } icon: { IconKit.key }
                    }
                }
                Section {
                    signOut
                }
            } label: {
                label()
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel(L10n.Settings.sectionAccounts)
        }

        /// One Sign Out for a single account; with several, a submenu naming which one.
        @ViewBuilder
        private var signOut: some View {
            if accounts.count > 1 {
                Menu {
                    ForEach(accounts) { account in
                        Button(title(for: account)) { signOut(account) }
                    }
                } label: {
                    SwiftUI.Label { Text(L10n.Settings.signOutButton) } icon: { IconKit.signOut }
                }
            } else if let account = accounts.first {
                Button { signOut(account) } label: {
                    SwiftUI.Label { Text(L10n.Settings.signOutButton + "…") } icon: { IconKit.signOut }
                }
            }
        }

        /// The active account goes through the full sign out confirmation; another one is only
        /// dropped from this Mac, as its Settings row does.
        private func signOut(_ account: AccountSummary) {
            if account.isActive {
                store.send(.signOutButtonTapped)
            } else {
                store.send(.removeAccountTapped(account))
            }
        }

        /// Falls back to the signed-in user before the shared account list has loaded.
        private var accounts: [AccountSummary] {
            guard store.accounts.isEmpty else { return store.accounts }
            return [AccountSummary(
                id: store.serverURL.absoluteString + "|" + store.user.username,
                username: store.displayName,
                serverURL: store.serverURL,
                isActive: true
            )]
        }

        private func title(for account: AccountSummary) -> String {
            L10n.Settings.accountLabel(account.displayName, account.serverHost)
        }
    }

    #Preview("Account menu") {
        MacSidebarAccountMenu(
            store: Store(
                initialState: SettingsFeature.State(
                    serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
                    user: User(id: "preview-user", username: "jdoe", email: "jane.doe@example.com", displayName: "Jane Doe", roles: [])
                )
            ) { SettingsFeature() },
            onChangePassword: {}
        ) {
            Text(verbatim: "Phillip")
        }
        .padding()
    }
#endif
