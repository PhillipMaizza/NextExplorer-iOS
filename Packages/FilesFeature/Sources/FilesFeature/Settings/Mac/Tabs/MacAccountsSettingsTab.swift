#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FolderPickerFeature
    import Localization
    import SwiftUI

    private enum Metrics {
        static let avatarSize: CGFloat = .size32
        static let accountRowHeight: CGFloat = .size56
    }

    /// The Accounts tab: every signed in account, the chosen one's details below it, and for the
    /// active account its security and Shared Files settings.
    struct MacAccountsSettingsTab: View {
        let store: StoreOf<SettingsFeature>
        @State private var selectedID: String?

        private var selectedAccount: AccountSummary {
            store.accountRows.first { $0.id == selectedID } ?? store.activeAccount
        }

        var body: some View {
            MacFormPage {
                MacFormGroup {
                    ForEach(store.accountRows) { account in
                        MacAccountRow(
                            store: store,
                            account: account,
                            isSelected: account.id == selectedAccount.id
                        ) {
                            selectedID = account.id
                        }
                    }
                }
                if selectedAccount.isActive {
                    HStack(alignment: .top, spacing: .space24) {
                        detailsGroup(selectedAccount)
                            .frame(maxWidth: .infinity)
                        VStack(spacing: .space24) {
                            MacSecuritySection(store: store)
                            MacUploadDefaultsSection(
                                store: store.scope(state: \.uploadDefaults, action: \.uploadDefaults)
                            )
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    detailsGroup(selectedAccount)
                }
                accountActions(selectedAccount)
            }
            .sheet(item: Bindable(store).scope(
                state: \.uploadDefaults.folderPicker,
                action: \.uploadDefaults.folderPicker
            )) { pickerStore in
                DestinationPickerView(store: pickerStore)
            }
            .task { store.send(.signInStatusRequested) }
            .onChange(of: store.accounts.map(\.id)) { _, ids in
                if let selectedID, !ids.contains(selectedID) {
                    self.selectedID = nil
                }
            }
        }

        private func detailsGroup(_ account: AccountSummary) -> some View {
            MacFormGroup(account.displayName) {
                MacValueRow(L10n.MacSettings.username, account.username)
                if account.isActive {
                    if let email = store.user.email, !email.isEmpty {
                        MacValueRow(L10n.MacSettings.email, email)
                    }
                    MacValueRow(
                        L10n.MacSettings.role,
                        store.user.isAdmin ? L10n.MacSettings.roleAdmin : L10n.MacSettings.roleUser
                    )
                }
                MacValueRow(L10n.MacSettings.status, L10n.MacSettings.statusSignedIn)
                MacValueRow(L10n.Settings.rowServer, account.serverHost)
            }
        }

        private func accountActions(_ account: AccountSummary) -> some View {
            HStack(spacing: .space8) {
                if !account.isActive {
                    Button(L10n.MacSettings.switchAccount) { store.send(.switchAccountTapped(account.id)) }
                        .buttonStyle(.macDS(.primary))
                }
                Button(L10n.MacSettings.signOut, role: .destructive) {
                    store.send(account.isActive ? .signOutButtonTapped : .removeAccountTapped(account))
                }
                .buttonStyle(.macDS(.secondary))
            }
            .disabled(store.isSigningOut)
        }
    }

    private struct MacAccountRow: View {
        let store: StoreOf<SettingsFeature>
        let account: AccountSummary
        let isSelected: Bool
        let onSelect: () -> Void

        var body: some View {
            MacFormRow {
                HStack(spacing: .space12) {
                    AvatarView.person(account.displayName, size: Metrics.avatarSize)
                    VStack(alignment: .leading, spacing: .space2) {
                        Text(account.displayName)
                            .type(.body2(.semibold))
                            .lineLimit(1)
                        if let server = account.serverSubtitle {
                            Text(server)
                                .type(.body3(.regular), style: .secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            } control: {
                if account.isActive {
                    MacChip(text: L10n.Settings.badgeActive, tone: .green)
                } else if !isSelected {
                    Button(L10n.MacSettings.switchAccount) { store.send(.switchAccountTapped(account.id)) }
                        .buttonStyle(.macDS(.secondary, size: .small))
                        .fixedSize()
                }
            }
            .frame(minHeight: Metrics.accountRowHeight)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: .radiusControl, style: .continuous)
                        .fill(Color.macSelection)
                        .elevation(.level1)
                        .padding(.space4)
                }
            }
            .macSelectable(isSelected: isSelected, onSelect: onSelect)
            .accessibilityLabel(account.isActive
                ? L10n.Settings.accountActiveLabel(account.displayName, account.serverHost)
                : L10n.Common.pair(account.displayName, account.serverHost))
                .accessibilityActions {
                    if !account.isActive {
                        Button(L10n.MacSettings.switchAccount) { store.send(.switchAccountTapped(account.id)) }
                    }
                }
                .contextMenu {
                    if !account.isActive {
                        Button(L10n.MacSettings.switchAccount) { store.send(.switchAccountTapped(account.id)) }
                        Button(L10n.MacSettings.signOut, role: .destructive) {
                            store.send(.removeAccountTapped(account))
                        }
                    }
                }
                .disabled(store.isSigningOut)
        }
    }

    #Preview("Accounts") {
        @Shared(.inMemory(AccountSummary.sharedKey)) var accounts: [AccountSummary] = []
        $accounts.withLock {
            $0 = [
                AccountSummary(
                    id: "a",
                    username: User.preview.username,
                    serverURL: URL(string: "https://home.example.com") ?? URL(fileURLWithPath: "/"),
                    isActive: true
                ),
                AccountSummary(
                    id: "b",
                    username: "work",
                    serverURL: URL(string: "https://files.acme.example.net") ?? URL(fileURLWithPath: "/"),
                    isActive: false
                ),
            ]
        }
        return MacAccountsSettingsTab(store: Store(initialState: .macPreview) { SettingsFeature() })
            .previewCanvas(.settingsWindow)
    }
#endif
