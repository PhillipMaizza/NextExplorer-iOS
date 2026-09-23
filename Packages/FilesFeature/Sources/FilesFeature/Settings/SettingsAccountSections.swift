import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let avatarSize: CGFloat = .size48
    static let profileRowSpacing: CGFloat = .space12
    static let signOutFadeDuration: Double = 0.15
    static let tagHorizontalPadding: CGFloat = .space8
    static let tagVerticalPadding: CGFloat = .space4
    static let tagBorderWidth: CGFloat = 1
    /// Accent avatar dimming on an inactive account, so it reads as not current.
    static let inactiveOpacity: Double = 0.35
}

@MainActor
private func sectionHeader(_ title: String) -> some View {
    DSFieldLabel(title)
        .accessibilityAddTraits(.isHeader)
}

// MARK: Accounts (multi-server switcher)

/// The signed-in servers/accounts. The active account sits on top with a disclosure chevron;
/// expanding it reveals self-service password change and sign out (which act on the active
/// session). The other accounts follow, each switching on tap (no re-auth) with a trailing swipe
/// to sign it out, then a row to add another. The switch / remove / add work is owned upstream
/// where `authClient` lives; this only renders `store.accounts` and emits intent. Hidden while
/// searching.
struct SettingsAccountsSection: View {
    let store: StoreOf<SettingsFeature>
    @State private var isActiveAccountExpanded = false

    /// The active account. Falls back to one synthesized from the signed-in user + server when the
    /// shared account list hasn't been populated yet (a fresh mount before the switcher refresh, or
    /// a preview), so the active-account row, password change and sign out are always present.
    private var activeAccount: AccountSummary {
        if let active = store.accounts.first(where: \.isActive) {
            return active
        }
        return AccountSummary(
            id: store.serverURL.absoluteString + "|" + store.user.username,
            username: store.displayName,
            serverURL: store.serverURL,
            isActive: true
        )
    }

    var body: some View {
        Section {
            activeAccountRow(activeAccount)
            if isActiveAccountExpanded {
                changePasswordRow
                signOutRow
            }
            ForEach(store.accounts.filter { !$0.isActive }) { account in
                switchableAccountRow(account)
            }
            addAccountRow
        } header: {
            sectionHeader(L10n.Settings.sectionAccounts)
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
                    Text(account.serverHost)
                        .type(.body3(.regular), style: .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
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
                    Text(account.serverHost)
                        .type(.body3(.regular), style: .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.isSigningOut)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.Settings.accountLabel(account.displayName, account.serverHost))
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
            Label(L10n.Settings.accountSignOut, systemImage: "rectangle.portrait.and.arrow.right")
        }
    }

    /// A small accent "Active" pill on the active account row, in place of a leading checkmark.
    private var activeBadge: some View {
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

    /// Self service password change (`POST /api/auth/password`), nested under the active account.
    /// No profile editing here: the backend has no self-service profile endpoint, so an admin
    /// changes that from User Management instead.
    private var changePasswordRow: some View {
        DSNavigationRow(title: L10n.Settings.rowChangePassword, icon: IconKit.key) {
            store.send(.changePasswordButtonTapped)
        }
        .disabled(store.isSigningOut)
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
        .animation(.easeInOut(duration: Constants.signOutFadeDuration), value: store.isSigningOut)
    }

    /// Accent tinted to read as the primary "add" affordance, matching its plus icon.
    private var addAccountRow: some View {
        DSNavigationRow(title: L10n.Settings.addAccount, icon: IconKit.plus, accessory: .none, role: .accent) {
            store.send(.addAccountTapped)
        }
        .disabled(store.isSigningOut)
    }
}

// MARK: Server

/// The bound server, in its own section below the accounts (no header). The host is shown on the
/// account row, so it isn't repeated here. Admins tap through to `ServerDetailsView` to edit
/// branding; everyone else gets the same row read-only. Hidden while searching.
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
        }
        .listRowBackground(Color.backgroundSecondary)
    }
}

// MARK: Users (admin)

struct SettingsUsersSection: View {
    let store: StoreOf<SettingsFeature>

    var body: some View {
        if store.user.isAdmin {
            Section {
                DSNavigationRow(title: L10n.Settings.rowUserManagement, icon: IconKit.people) {
                    store.send(.userManagementButtonTapped)
                }
            } header: {
                sectionHeader(L10n.Settings.sectionUsers)
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }
}

// MARK: Server admin

/// Admin-only server config that isn't per-user: thumbnail generation and folder access
/// rules, each a pushed detail screen. Mirrors the web client's admin settings pages.
struct SettingsServerAdminSection: View {
    let store: StoreOf<SettingsFeature>

    var body: some View {
        if store.user.isAdmin {
            Section {
                DSNavigationRow(title: L10n.Settings.rowThumbnails, icon: IconKit.photo) {
                    store.send(.thumbnailSettingsButtonTapped)
                }
                DSNavigationRow(title: L10n.Settings.rowAccessRules, icon: IconKit.shield) {
                    store.send(.accessRulesButtonTapped)
                }
            } header: {
                sectionHeader(L10n.Settings.sectionAdmin)
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }
}

// MARK: Server storage

/// One disk-usage bar per volume — iOS's take on the web client's volume list. Only
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
                                Text(usageCaption(usage)).type(.body3(.regular), style: .secondary)
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
                sectionHeader(L10n.Settings.sectionServerStorage)
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }

    private func usageCaption(_ usage: StorageUsage) -> String {
        L10n.Settings.serverStorageUsed(
            SettingsFormat.byteFormatter.string(fromByteCount: usage.used),
            SettingsFormat.byteFormatter.string(fromByteCount: usage.capacity)
        )
    }
}
