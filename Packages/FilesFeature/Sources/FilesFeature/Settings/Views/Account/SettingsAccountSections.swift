import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let avatarSize: CGFloat = .size48
    static let profileRowSpacing: CGFloat = .space12
    static let tagHorizontalPadding: CGFloat = .space8
    static let tagVerticalPadding: CGFloat = .space4
    static let tagBorderWidth: CGFloat = 1
    /// Accent avatar dimming on an inactive account, so it reads as not current.
    static let inactiveOpacity: Double = .opacityDim
}

// MARK: Accounts (multiserver switcher)

/// The signed in servers/accounts. The active account sits on top with a disclosure chevron;
/// expanding it reveals sign out (which acts on the active session). The other accounts follow,
/// each switching on tap (no reauth) with a trailing swipe to sign it out, then a row to add
/// another. The switch / remove / add work is owned upstream where `authClient` lives; this only
/// renders `store.accounts` and emits intent. Hidden while searching.
struct SettingsAccountsSection: View {
    let store: StoreOf<SettingsFeature>
    @State private var isActiveAccountExpanded = false
    /// On iPad the sidebar's account popover switches, adds, signs out and opens the second factor,
    /// so the section is left out there.
    @Environment(\.isSplitViewDetail) private var isSplitViewDetail

    private var activeAccount: AccountSummary {
        store.activeAccount
    }

    var body: some View {
        if !isSplitViewDetail {
            accountsSection
        }
    }

    private var accountsSection: some View {
        Section {
            activeAccountRow(activeAccount)
            if isActiveAccountExpanded {
                signOutRow
            }
            ForEach(store.accountRows.filter { !$0.isActive }) { account in
                switchableAccountRow(account)
            }
            addAccountRow
        } header: {
            SettingsSectionHeader(L10n.Settings.sectionAccounts)
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    /// The active account: tapping toggles the disclosure rather than switching (it is already
    /// active). The chevron flips like the Shared card's header.
    private func activeAccountRow(_ account: AccountSummary) -> some View {
        Button {
            withAnimation(DSMotion.disclosure) { isActiveAccountExpanded.toggle() }
        } label: {
            HStack(spacing: Constants.profileRowSpacing) {
                AvatarView(displayName: account.displayName, size: Constants.avatarSize)

                VStack(alignment: .leading, spacing: .space2) {
                    Text(account.displayName).type(.body2(.bold), style: .primaryOnSurface)
                    if let server = account.serverSubtitle {
                        Text(server)
                            .type(.body3(.regular), style: .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()

                activeBadge

                IconKit.chevronDown
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.tertiaryDS)
                    .frame(width: .iconXSmall, height: .iconXSmall)
                    .rotationEffect(.degrees(isActiveAccountExpanded ? 180 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.isSigningOut)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityIdentifiers.Settings.activeAccount)
        .accessibilityLabel(L10n.Settings.accountActiveLabel(account.displayName, account.serverHost))
        .accessibilityAddTraits(isActiveAccountExpanded ? [.isButton, .isSelected] : .isButton)
    }

    private func switchableAccountRow(_ account: AccountSummary) -> some View {
        Button {
            store.send(.switchAccountTapped(account.id))
        } label: {
            HStack(spacing: Constants.profileRowSpacing) {
                AvatarView(displayName: account.displayName, size: Constants.avatarSize)
                    .opacity(Constants.inactiveOpacity)

                VStack(alignment: .leading, spacing: .space2) {
                    // Secondary color (not primary) so an inactive account reads as dimmed.
                    Text(account.displayName).type(.body2(.regular), style: .secondary)
                    if let server = account.serverSubtitle {
                        Text(server)
                            .type(.body3(.regular), style: .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.isSigningOut)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.Common.pair(account.displayName, account.serverHost))
        .accessibilityAddTraits(.isButton)
        .swipeActions(edge: .trailing) {
            removeAccountButton(account)
        }
        #if os(macOS)
        .contextMenu { removeAccountButton(account) }
        #endif
    }

    private func removeAccountButton(_ account: AccountSummary) -> some View {
        Button(role: .destructive) {
            store.send(.removeAccountTapped(account))
        } label: {
            Label { Text(L10n.Settings.accountSignOut) } icon: { IconKit.signOut }
        }
    }

    private var activeBadge: some View {
        AccountActiveBadge()
    }

    private var signOutRow: some View {
        DSNavigationRow(
            title: store.isSigningOut ? L10n.Settings.signingOut : L10n.Settings.signOutButton,
            icon: IconKit.signOut,
            accessory: .none,
            role: .destructive,
            isLoading: store.isSigningOut
        ) {
            store.send(.signOutButtonTapped)
        }
        .animation(DSMotion.quickFade, value: store.isSigningOut)
    }

    /// Accent tinted to read as the primary "add" affordance, matching its plus icon.
    private var addAccountRow: some View {
        DSNavigationRow(title: L10n.Settings.addAccount, icon: IconKit.plus, accessory: .none, role: .accent) {
            store.send(.addAccountTapped)
        }
        .disabled(store.isSigningOut)
    }
}

extension SettingsFeature.State {
    /// Every account to list. Falls back to one synthesized from the signed in user + server when
    /// the shared account list hasn't been populated yet (a fresh mount before the switcher
    /// refresh, or a preview), so the active account row, password change and sign out are always
    /// present. The active account shows the signed in user's current email over the one saved
    /// with its session, which can be stale or missing.
    var accountRows: [AccountSummary] {
        guard !accounts.isEmpty else { return [signedInAccount] }
        return accounts.map { account in
            guard account.isActive else { return account }
            var current = account
            current.email = user.email ?? account.email
            return current
        }
    }

    var activeAccount: AccountSummary {
        accountRows.first(where: \.isActive) ?? signedInAccount
    }

    private var signedInAccount: AccountSummary {
        AccountSummary(
            id: SessionCredentials.accountID(serverURL: serverURL, username: user.username),
            username: user.username,
            serverURL: serverURL,
            isActive: true,
            email: user.email
        )
    }
}

// MARK: Server

/// The bound server, in its own section below the accounts (no header). The host is shown on the
/// account row, so it isn't repeated here. Admins tap through to `ServerDetailsView` to edit
/// branding; everyone else gets the same row read only. Hidden while searching.
struct SettingsProfileSection: View {
    let store: StoreOf<SettingsFeature>

    var body: some View {
        Section {
            if store.user.isAdmin {
                DSNavigationRow(title: L10n.Settings.rowServer, icon: IconKit.server) {
                    store.send(.serverDetailsButtonTapped)
                }
                .disabled(store.isSigningOut)
            } else {
                DSNavigationRow(title: L10n.Settings.rowServer, icon: IconKit.server, accessory: .none)
            }
            SettingsClientCertificateRow(store: store)
        }
        .listRowBackground(Color.backgroundSecondary)
    }
}

// MARK: Server admin

/// Admin only server config that isn't per user: thumbnail generation and folder access
/// rules, each a pushed detail screen. Mirrors the web client's admin settings pages.
struct SettingsServerAdminSection: View {
    @Bindable var store: StoreOf<SettingsFeature>

    var body: some View {
        if store.user.isAdmin {
            Section {
                DSNavigationRow(title: L10n.Settings.rowThumbnails, icon: IconKit.photo) {
                    store.send(.thumbnailSettingsButtonTapped)
                }
                DSNavigationRow(title: L10n.Settings.rowAccessRules, icon: IconKit.shield) {
                    store.send(.accessRulesButtonTapped)
                }
                DSNavigationRow(title: L10n.UploadSettings.navigationTitle, icon: IconKit.upload) {
                    store.send(.uploadSettingsButtonTapped)
                }
                DSNavigationRow(title: L10n.SearchIndexSettings.navigationTitle, icon: IconKit.search) {
                    store.send(.searchIndexSettingsButtonTapped)
                }
                DSNavigationRow(title: L10n.FolderSizeSettings.navigationTitle, icon: IconKit.folder) {
                    store.send(.folderSizeSettingsButtonTapped)
                }
                DSNavigationRow(title: L10n.FfmpegSettings.navigationTitle, icon: IconKit.film) {
                    store.send(.ffmpegSettingsButtonTapped)
                }
                DSNavigationRow(title: L10n.TrashSettings.navigationTitle, icon: IconKit.delete) {
                    store.send(.trashSettingsButtonTapped)
                }
                DSNavigationRow(title: L10n.VersionedFiles.navigationTitle, icon: IconKit.archiveDocument) {
                    store.send(.versionedFilesButtonTapped)
                }
                DSNavigationRow(title: L10n.ActivityLog.navigationTitle, icon: IconKit.time) {
                    store.send(.activityLogButtonTapped)
                }
                DSNavigationRow(title: L10n.ServerTools.navigationTitle, icon: IconKit.gearshape) {
                    store.send(.serverToolsButtonTapped)
                }
            } header: {
                SettingsSectionHeader(L10n.Settings.sectionAdmin)
            }
            .listRowBackground(Color.backgroundSecondary)
            .navigationDestination(item: $store.scope(state: \.serverTools, action: \.serverTools)) { toolsStore in
                ServerToolsView(store: toolsStore)
            }
        }
    }
}

// MARK: Server storage

/// One disk usage bar per volume: iOS's take on the web client's volume list. Only
/// present when the server reports `volumeUsage.enabled` and has returned volumes.
struct SettingsServerStorageSection: View {
    let store: StoreOf<SettingsFeature>

    var body: some View {
        if store.isVolumeUsageEnabled, !store.serverUsage.isEmpty {
            Section {
                ForEach(store.serverUsage) { row in
                    VStack(alignment: .leading, spacing: .space8) {
                        HStack {
                            Text(row.volume.name).type(.body2(.regular), style: .primaryOnSurface)
                            Spacer()
                            if let usage = row.usage, usage.isMeaningful {
                                Text(usage.usedCaption).type(.body3(.regular), style: .secondary)
                            } else if row.usage == nil {
                                DSSpinner(size: .small)
                            }
                        }
                        if let usage = row.usage, usage.isMeaningful {
                            DSUsageBar(fraction: usage.fraction)
                        }
                    }
                    .padding(.vertical, .space4)
                }
            } header: {
                SettingsSectionHeader(L10n.Settings.sectionServerStorage)
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }
}

@MainActor
extension StorageUsage {
    var usedCaption: String {
        L10n.Settings.serverStorageUsed(
            FileSizeFormat.string(used),
            FileSizeFormat.string(capacity)
        )
    }
}

/// A small accent "Active" pill on the active account, in place of a leading checkmark.
private struct AccountActiveBadge: View {
    var body: some View {
        Text(L10n.Settings.badgeActive.uppercased())
            .type(.caption(.semibold), style: .link)
            .padding(.horizontal, Constants.tagHorizontalPadding)
            .padding(.vertical, Constants.tagVerticalPadding)
            .overlay(
                RoundedRectangle(cornerRadius: .radiusSmall)
                    .strokeBorder(Color.accent, lineWidth: Constants.tagBorderWidth)
            )
            .accessibilityHidden(true)
    }
}
