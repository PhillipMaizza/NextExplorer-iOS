#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let width: CGFloat = 320
        static let avatarSize: CGFloat = .size32
        static let rowSpacing: CGFloat = .space12
        static let rowPadding: CGFloat = .space8
        static let actionIconSize: CGFloat = .iconSmall
        static let inactiveOpacity: Double = 0.5
        static let hoverOpacity: Double = 0.08
        static let serverMinimumScale: CGFloat = 0.7
    }

    /// The Mac sidebar's profile header opens this account popover, so switching, adding and
    /// signing out never needs a trip to Settings. Each account shows who (name) and where
    /// (server) on their own lines, like the Settings rows; the active one is shown in full
    /// strength, the others dimmed, switching on click and offering Sign Out on hover. Only emits `SettingsFeature`
    /// intent; the switch, add and remove work stays upstream.
    struct MacSidebarAccountMenu<Label: View>: View {
        let store: StoreOf<SettingsFeature>
        /// Change Password opens as a window sheet, from whichever section is on screen.
        let onChangePassword: () -> Void
        @ViewBuilder let label: () -> Label

        @State private var isPresented = false

        var body: some View {
            Button { isPresented.toggle() } label: {
                label()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Settings.sectionAccounts)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                MacAccountPopover(store: store) { action in
                    isPresented = false
                    action()
                }
                onChangePassword: {
                    isPresented = false
                    onChangePassword()
                }
            }
        }
    }

    private struct MacAccountPopover: View {
        let store: StoreOf<SettingsFeature>
        /// Closes the popover, then runs the action.
        let dismissThen: (@escaping () -> Void) -> Void
        let onChangePassword: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: .space4) {
                DSFieldLabel(L10n.Settings.sectionAccounts)
                    .padding(.horizontal, Metrics.rowPadding)
                    .padding(.top, .space4)
                ForEach(accounts) { account in
                    MacAccountRow(
                        account: account,
                        onSwitch: { dismissThen { store.send(.switchAccountTapped(account.id)) } },
                        onSignOut: { dismissThen { signOut(account) } }
                    )
                }
                Divider()
                    .padding(.vertical, .space4)
                MacPopoverActionRow(title: L10n.Settings.addAccount, icon: IconKit.plus, tone: .accent) {
                    dismissThen { store.send(.addAccountTapped) }
                }
                MacPopoverActionRow(title: L10n.Settings.rowChangePassword, icon: IconKit.key, action: onChangePassword)
                MacPopoverActionRow(title: L10n.Settings.signOutButton, icon: IconKit.signOut, tone: .danger) {
                    dismissThen { store.send(.signOutButtonTapped) }
                }
            }
            .padding(.space8)
            .frame(width: Metrics.width)
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

        /// Falls back to the signed in user before the shared account list has loaded.
        private var accounts: [AccountSummary] {
            guard store.accounts.isEmpty else { return store.accounts }
            return [AccountSummary(
                id: store.serverURL.absoluteString + "|" + store.user.username,
                username: store.displayName,
                serverURL: store.serverURL,
                isActive: true
            )]
        }
    }

    /// One account: avatar, name above server, and Sign Out on hover for an inactive one. The
    /// active account reads as current through its bold name and full strength avatar.
    private struct MacAccountRow: View {
        let account: AccountSummary
        let onSwitch: () -> Void
        let onSignOut: () -> Void

        @State private var isHovered = false

        var body: some View {
            HStack(spacing: Metrics.rowSpacing) {
                AvatarView(displayName: account.displayName, size: Metrics.avatarSize)
                    .opacity(account.isActive ? 1 : Metrics.inactiveOpacity)
                VStack(alignment: .leading, spacing: .space2) {
                    Text(account.displayName)
                        .type(.body2(account.isActive ? .bold : .regular), style: account.isActive ? .primaryOnSurface : .secondary)
                        .lineLimit(1)
                    // Shrinks a long host to fit before falling back to truncating it.
                    Text(account.serverHost)
                        .type(.body3(.regular), style: .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(Metrics.serverMinimumScale)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if !account.isActive, isHovered {
                    Button(action: onSignOut) {
                        IconKit.signOut
                            .foregroundStyle(Color.negativeText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabelWithTooltip(L10n.Settings.accountSignOut)
                }
            }
            .padding(Metrics.rowPadding)
            .background(MacPopoverHoverFill(isShown: !account.isActive && isHovered))
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture {
                if !account.isActive {
                    onSwitch()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(account.isActive
                ? L10n.Settings.accountActiveLabel(account.displayName, account.serverHost)
                : L10n.Settings.accountLabel(account.displayName, account.serverHost))
            .accessibilityAddTraits(account.isActive ? .isSelected : .isButton)
            .accessibilityAction(named: L10n.Settings.accountSignOut, onSignOut)
        }
    }

    /// An icon and title row in the popover's action list, highlighted on hover.
    private struct MacPopoverActionRow: View {
        enum Tone {
            case neutral, accent, danger

            var textStyle: Typography.TextStyle {
                switch self {
                case .neutral: .primaryOnSurface
                case .accent: .link
                case .danger: .error
                }
            }

            var iconColor: Color {
                switch self {
                case .neutral: .secondaryDS
                case .accent: .accentText
                case .danger: .negativeText
                }
            }
        }

        let title: String
        let icon: Image
        var tone: Tone = .neutral
        let action: () -> Void

        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: Metrics.rowSpacing) {
                    icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: Metrics.actionIconSize, height: Metrics.actionIconSize)
                        .frame(width: Metrics.avatarSize)
                    Text(title).type(.body2(.regular), style: tone.textStyle)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(tone.iconColor)
                .padding(.horizontal, Metrics.rowPadding)
                .padding(.vertical, .space8)
                .background(MacPopoverHoverFill(isShown: isHovered))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
        }
    }

    private struct MacPopoverHoverFill: View {
        let isShown: Bool

        var body: some View {
            RoundedRectangle(cornerRadius: .radiusSmall, style: .continuous)
                .fill(isShown ? Color.primaryDS.opacity(Metrics.hoverOpacity) : Color.clear)
        }
    }

    #Preview("Account popover") {
        MacAccountPopover(
            store: Store(
                initialState: SettingsFeature.State(
                    serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
                    user: User(id: "preview-user", username: "jdoe", email: "jane.doe@example.com", displayName: "Jane Doe", roles: [])
                )
            ) { SettingsFeature() },
            dismissThen: { $0() },
            onChangePassword: {}
        )
    }
#endif
