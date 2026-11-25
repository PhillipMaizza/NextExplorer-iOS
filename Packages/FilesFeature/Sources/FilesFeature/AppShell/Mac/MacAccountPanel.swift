#if os(macOS)
    import AppStorageKeys
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let width: CGFloat = 320
        static let radius: CGFloat = .radiusMedium
        static let rowRadius: CGFloat = .radiusSmall
        static let rowHeight: CGFloat = .size36
        static let accountRowHeight: CGFloat = .size48
        static let headerAvatar: CGFloat = .size40
        static let rowAvatar: CGFloat = 28
        static let rowIcon: CGFloat = .iconSmall
        static let shadowRadius: CGFloat = 30
        static let shadowY: CGFloat = 11
        static let shadowOpacity: Double = 0.35
        static let addDash: [CGFloat] = [3, 3]
        static let addStroke: CGFloat = .borderWidthFocused
        static let addGlyph: CGFloat = .iconXSmall
        static let fullBottomInset: CGFloat = 84
        static let railLeadingInset: CGFloat = MacSidebarRail.width - .space8
    }

    struct MacAccountPanel: View {
        let store: StoreOf<SettingsFeature>
        let close: () -> Void
        @Environment(\.openSettings) private var openSettings
        @AppStorage(AppStorageKeys.macSettingsPane) private var settingsPane = MacSettingsCategory.general

        var body: some View {
            VStack(alignment: .leading, spacing: .zero) {
                header
                actions
                separator
                accounts
                MacAccountAddRow { run { store.send(.addAccountTapped) } }
                separator
                MacAccountPanelRow(icon: IconKit.signOut, title: L10n.Settings.signOutButton, isDestructive: true) {
                    run { store.send(.signOutButtonTapped) }
                }
            }
            .padding(.space8)
            .frame(width: Metrics.width)
            .background(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .fill(Color.macCard)
                    .shadow(
                        color: .black.opacity(Metrics.shadowOpacity),
                        radius: Metrics.shadowRadius,
                        y: Metrics.shadowY
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .strokeBorder(Color.macLine)
            )
            .background {
                Button(L10n.Common.close, action: close)
                    .keyboardShortcut(.cancelAction)
                    .opacity(.zero)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.Settings.sectionAccounts)
            .task { store.send(.signInStatusRequested) }
        }

        @ViewBuilder
        private var actions: some View {
            MacAccountPanelRow(
                icon: IconKit.account,
                title: L10n.MacSettings.accountSettings,
                shortcut: MacShortcutHint.settings
            ) {
                openSettingsPane(.accounts)
            }
            if store.shouldShowTwoFactorRow {
                MacAccountPanelRow(icon: IconKit.key, title: L10n.MacSettings.changePassword) {
                    run { store.send(.changePasswordButtonTapped) }
                }
                MacAccountPanelRow(icon: IconKit.shield, title: L10n.TwoFactor.navigationTitle) {
                    run { store.send(.twoFactorButtonTapped) }
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.Settings.twoFactorRow)
            }
            MacAccountPanelRow(icon: IconKit.keyHorizontal, title: L10n.ApiTokens.navigationTitle) {
                openSettingsPane(.apiTokens)
            }
        }

        @ViewBuilder
        private var accounts: some View {
            Text(L10n.MacSettings.switchAccountHeader)
                .type(.caption(.semibold))
                .foregroundStyle(Color.secondaryDS)
                .padding(.horizontal, .space12)
                .padding(.top, .space8)
                .padding(.bottom, .space4)
                .accessibilityAddTraits(.isHeader)
            ForEach(store.accountRows) { account in
                MacAccountSwitchRow(
                    account: account,
                    onSwitch: { run { store.send(.switchAccountTapped(account.id)) } },
                    onRemove: { run { store.send(.removeAccountTapped(account)) } }
                )
            }
        }

        private var header: some View {
            HStack(alignment: .center, spacing: .space12) {
                AvatarView(displayName: store.activeAccount.displayName, size: Metrics.headerAvatar)
                VStack(alignment: .leading, spacing: .space2) {
                    Text(store.activeAccount.displayName)
                        .type(.body1(.bold))
                        .lineLimit(1)
                    if let subtitle = store.user.email ?? store.activeAccount.serverSubtitle {
                        Text(subtitle)
                            .type(.body3(.regular))
                            .foregroundStyle(Color.secondaryDS)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: .zero)
                if store.user.isAdmin {
                    MacChip(text: L10n.Settings.sectionAdmin, tone: .amber)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, .space12)
            .padding(.top, .space12)
            .padding(.bottom, .space16)
            .accessibilityElement(children: .combine)
        }

        private var separator: some View {
            Rectangle()
                .fill(Color.macLine)
                .frame(height: .borderWidthHairline)
                .padding(.horizontal, .space4)
                .padding(.vertical, .space4)
                .accessibilityHidden(true)
        }

        private func run(_ action: @escaping () -> Void) {
            close()
            action()
        }

        private func openSettingsPane(_ pane: MacSettingsCategory) {
            settingsPane = pane
            run { openSettings() }
        }

        static func padding(isRail: Bool) -> EdgeInsets {
            isRail
                ? EdgeInsets(top: 0, leading: Metrics.railLeadingInset, bottom: .space12, trailing: 0)
                : EdgeInsets(top: 0, leading: .space16, bottom: Metrics.fullBottomInset, trailing: 0)
        }
    }

    private struct MacAccountPanelRow: View {
        let icon: Image
        let title: String
        var shortcut: String?
        var isDestructive = false
        let action: () -> Void
        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: .space12) {
                    icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: Metrics.rowIcon, height: Metrics.rowIcon)
                        .foregroundStyle(isDestructive ? Color.negativeText : Color.secondaryDS)
                        .accessibilityHidden(true)
                    Text(title)
                        .type(.body2(.regular))
                        .foregroundStyle(isDestructive ? Color.negativeText : Color.primaryDS)
                    Spacer(minLength: .zero)
                    if let shortcut {
                        MacKeyHint(shortcut)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, .space12)
                .frame(maxWidth: .infinity, minHeight: Metrics.rowHeight)
                .background(MacAccountRowFill(isShown: isHovered))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
        }
    }

    private struct MacAccountSwitchRow: View {
        let account: AccountSummary
        let onSwitch: () -> Void
        let onRemove: () -> Void
        @State private var isHovered = false

        var body: some View {
            Button {
                if !account.isActive {
                    onSwitch()
                }
            } label: {
                HStack(spacing: .space12) {
                    AvatarView(displayName: account.displayName, size: Metrics.rowAvatar)
                    VStack(alignment: .leading, spacing: .zero) {
                        Text(account.displayName)
                            .type(.body2(.semibold))
                            .foregroundStyle(Color.primaryDS)
                            .lineLimit(1)
                        if let server = account.serverSubtitle {
                            Text(server)
                                .type(.caption(.regular))
                                .foregroundStyle(Color.secondaryDS)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: .zero)
                    if account.isActive {
                        IconKit.checkmark
                            .font(.body.weight(.bold))
                            .foregroundStyle(Color.primaryDS)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, .space12)
                .frame(maxWidth: .infinity, minHeight: Metrics.accountRowHeight)
                .background(MacAccountRowFill(isShown: isHovered))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .contextMenu {
                if !account.isActive {
                    Button(L10n.Settings.accountSignOut, role: .destructive, action: onRemove)
                }
            }
            .accessibilityLabel(account.isActive
                ? L10n.Settings.accountActiveLabel(account.displayName, account.serverHost)
                : L10n.Common.pair(account.displayName, account.serverHost))
                .accessibilityAddTraits(account.isActive ? .isSelected : [])
                .accessibilityAction(named: L10n.Settings.accountSignOut, onRemove)
        }
    }

    private struct MacAccountAddRow: View {
        let action: () -> Void
        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: .space12) {
                    Circle()
                        .strokeBorder(
                            Color.macLine,
                            style: StrokeStyle(lineWidth: Metrics.addStroke, dash: Metrics.addDash)
                        )
                        .frame(width: Metrics.rowAvatar, height: Metrics.rowAvatar)
                        .overlay {
                            IconKit.plus
                                .resizable()
                                .scaledToFit()
                                .frame(width: Metrics.addGlyph, height: Metrics.addGlyph)
                                .foregroundStyle(Color.secondaryDS)
                        }
                        .accessibilityHidden(true)
                    Text(L10n.MacSettings.addAccount)
                        .type(.body2(.regular))
                        .foregroundStyle(Color.primaryDS)
                    Spacer(minLength: .zero)
                }
                .padding(.horizontal, .space12)
                .frame(maxWidth: .infinity, minHeight: Metrics.accountRowHeight)
                .background(MacAccountRowFill(isShown: isHovered))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
        }
    }

    private struct MacAccountRowFill: View {
        let isShown: Bool

        var body: some View {
            RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
                .fill(isShown ? Color.macRow : .clear)
        }
    }

    @MainActor
    private func previewPanel(isAdmin: Bool) -> some View {
        MacAccountPanel(
            store: Store(initialState: SettingsFeature.State(
                serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
                user: isAdmin ? User.previewAdmin : User.preview
            )) { SettingsFeature() },
            close: {}
        )
        .padding(.space32)
        .background(Color.macChrome)
    }

    #Preview("Account panel") { previewPanel(isAdmin: false) }
    #Preview("Account panel, admin") { previewPanel(isAdmin: true) }
#endif
