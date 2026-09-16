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
    static let signOutFadeDuration: Double = 0.15
}

@MainActor
private func sectionHeader(_ title: String) -> some View {
    DSFieldLabel(title)
        .accessibilityAddTraits(.isHeader)
}

// MARK: Profile

/// The account card at the top of Settings: identity, the bound server, self-service password
/// change, and sign out. Hidden while searching.
struct SettingsProfileSection: View {
    let store: StoreOf<SettingsFeature>

    var body: some View {
        Section {
            HStack(spacing: Constants.profileRowSpacing) {
                AvatarView(displayName: store.displayName, size: Constants.avatarSize)

                VStack(alignment: .leading, spacing: .space2) {
                    Text(store.displayName).type(.body2(.bold), style: .primaryOnSurface)
                    if let email = store.user.email {
                        Text(email).type(.body3(.regular), style: .secondary).lineLimit(1).truncationMode(.tail)
                    }
                }

                Spacer()
            }
            .overlay(alignment: .topTrailing) {
                if store.user.isAdmin {
                    roleTag
                }
            }
            .listRowSeparator(.hidden, edges: .bottom)

            serverRow
                .listRowSeparator(.hidden, edges: .top)

            changePasswordRow
            signOutRow
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    /// The server the session is bound to. Admins tap through to `ServerDetailsView` to edit
    /// branding; everyone else gets the same row read-only, showing the host.
    @ViewBuilder
    private var serverRow: some View {
        if store.user.isAdmin {
            DSNavigationRow(title: L10n.Settings.rowServer, icon: IconKit.server) {
                store.send(.serverDetailsButtonTapped)
            }
            .disabled(store.isSigningOut)
        } else {
            DSNavigationRow(title: L10n.Settings.rowServer, icon: IconKit.server, accessory: serverHostAccessory)
        }
    }

    private var serverHostAccessory: DSNavigationRow.Accessory {
        if let host = store.serverURL.host {
            .detail(host)
        } else {
            .none
        }
    }

    /// Self service password change (`POST /api/auth/password`). No profile editing here: the
    /// backend has no self service profile endpoint, so an admin changes that from User
    /// Management instead.
    private var changePasswordRow: some View {
        DSNavigationRow(title: L10n.Settings.rowChangePassword, icon: IconKit.key) {
            store.send(.changePasswordButtonTapped)
        }
        .disabled(store.isSigningOut)
    }

    /// Full width row, leading aligned like the rest of the card, in error red.
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

    private var roleTag: some View {
        Text(L10n.Settings.sectionAdmin.uppercased())
            .type(.caption(.semibold), style: .link)
            .padding(.horizontal, Constants.tagHorizontalPadding)
            .padding(.vertical, Constants.tagVerticalPadding)
            .overlay(
                RoundedRectangle(cornerRadius: .radiusSmall).strokeBorder(Color.accent, lineWidth: Constants.tagBorderWidth)
            )
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
