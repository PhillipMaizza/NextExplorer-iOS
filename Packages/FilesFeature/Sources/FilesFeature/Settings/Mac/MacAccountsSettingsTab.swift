#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let listWidth: CGFloat = 220
        static let rowAvatarSize: CGFloat = .size32
        static let detailAvatarSize: CGFloat = 48
        static let statusDotSize: CGFloat = 10
        static let rowStatusDotSize: CGFloat = 9
        static let rowSpacing: CGFloat = .space8
        static let footerPadding: CGFloat = .space8
    }

    /// The Accounts tab: every signed in account on the left, the selected one's details and
    /// actions on the right, and a button to add another below the list.
    struct MacAccountsSettingsTab: View {
        let store: StoreOf<SettingsFeature>
        @State private var selectedID: String?

        private var accounts: [AccountSummary] {
            store.accounts.isEmpty ? [store.activeAccount] : store.accounts
        }

        private var selectedAccount: AccountSummary {
            accounts.first { $0.id == selectedID } ?? store.activeAccount
        }

        var body: some View {
            HStack(spacing: 0) {
                accountList
                Divider()
                MacAccountDetail(store: store, account: selectedAccount)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .onAppear { selectedID = selectedID ?? store.activeAccount.id }
            .onChange(of: store.accounts.map(\.id)) { _, ids in
                if let selectedID, !ids.contains(selectedID) {
                    self.selectedID = store.activeAccount.id
                }
            }
        }

        private var accountList: some View {
            VStack(spacing: 0) {
                List(accounts, selection: $selectedID) { account in
                    MacAccountRow(account: account)
                        .tag(account.id)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)

                Button {
                    store.send(.addAccountTapped)
                } label: {
                    Text(L10n.MacSettings.addAccount).frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .padding(Metrics.footerPadding)
                .disabled(store.isSigningOut)
            }
            .frame(width: Metrics.listWidth)
        }
    }

    private struct MacAccountRow: View {
        let account: AccountSummary

        var body: some View {
            HStack(spacing: Metrics.rowSpacing) {
                AvatarView(displayName: account.displayName, size: Metrics.rowAvatarSize)
                    .overlay(alignment: .bottomTrailing) {
                        if account.isActive {
                            StatusDot(size: Metrics.rowStatusDotSize)
                        }
                    }
                VStack(alignment: .leading) {
                    Text(account.displayName)
                        .lineLimit(1)
                    Text(account.serverHost)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(account.isActive
                ? L10n.Settings.accountActiveLabel(account.displayName, account.serverHost)
                : L10n.Settings.accountLabel(account.displayName, account.serverHost))
        }
    }

    /// The selected account: who and where it is, and what can be done with it. The signed in
    /// user's email and role are only known for the active account.
    private struct MacAccountDetail: View {
        let store: StoreOf<SettingsFeature>
        let account: AccountSummary

        var body: some View {
            MacSettingsPane {
                Section {
                    HStack(spacing: .space12) {
                        AvatarView(displayName: account.displayName, size: Metrics.detailAvatarSize)
                        VStack(alignment: .leading) {
                            Text(account.displayName).font(.title3.weight(.semibold))
                            Text(account.serverHost).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                Section {
                    LabeledContent(L10n.Settings.rowServer) { Text(account.serverHost).textSelection(.enabled) }
                    LabeledContent(L10n.MacSettings.username) { Text(account.username).textSelection(.enabled) }
                    if account.isActive {
                        if let email = store.user.email, !email.isEmpty {
                            LabeledContent(L10n.MacSettings.email) { Text(email).textSelection(.enabled) }
                        }
                        LabeledContent(L10n.MacSettings.role) {
                            Text(store.user.isAdmin ? L10n.MacSettings.roleAdmin : L10n.MacSettings.roleUser)
                        }
                    }
                    LabeledContent(L10n.MacSettings.status) {
                        HStack(spacing: .space4) {
                            if account.isActive {
                                StatusDot(size: Metrics.statusDotSize)
                            }
                            Text(account.isActive ? L10n.Settings.badgeActive : L10n.MacSettings.statusSignedIn)
                        }
                    }
                }
                Section {
                    HStack {
                        if account.isActive {
                            Button(L10n.MacSettings.changePassword) { store.send(.changePasswordButtonTapped) }
                        } else {
                            Button(L10n.MacSettings.switchAccount) { store.send(.switchAccountTapped(account.id)) }
                        }
                        Spacer()
                        Button(L10n.MacSettings.signOut, role: .destructive) {
                            store.send(account.isActive ? .signOutButtonTapped : .removeAccountTapped(account))
                        }
                    }
                    .disabled(store.isSigningOut)
                }
            }
        }
    }

    /// The green "signed in and current" dot.
    private struct StatusDot: View {
        let size: CGFloat

        var body: some View {
            Circle()
                .fill(Color.positive)
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: .borderWidthFocused))
                .accessibilityHidden(true)
        }
    }

    #Preview("Accounts") {
        @Shared(.inMemory(AccountSummary.sharedKey)) var accounts: [AccountSummary] = []
        $accounts.withLock {
            $0 = [
                AccountSummary(id: "a", username: "jdoe", serverURL: URL(string: "https://home.example.com") ?? URL(fileURLWithPath: "/"), isActive: true),
                AccountSummary(id: "b", username: "work", serverURL: URL(string: "https://files.acme.example.net") ?? URL(fileURLWithPath: "/"), isActive: false),
            ]
        }
        return MacAccountsSettingsTab(store: Store(initialState: .macPreview) { SettingsFeature() })
            .frame(width: 640, height: 460)
    }
#endif
