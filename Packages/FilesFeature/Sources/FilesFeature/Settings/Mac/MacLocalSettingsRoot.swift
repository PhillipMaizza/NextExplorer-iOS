#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let sidebarAvatarSize: CGFloat = .size32
        static let paneAvatarSize: CGFloat = .size40
        static let sidebarRowHeight: CGFloat = .size56
        static let badgeSize: CGFloat = .size16
        static let badgeGlyphSize: CGFloat = 9
        static let badgeOffset: CGFloat = 3
    }

    public struct MacLocalSettingsRoot: View {
        enum Pane {
            case account
            case general
            case about
        }

        let lockedAccount: AccountSummary?
        let onShowLockScreen: () -> Void
        let onSignOut: () -> Void
        let onTip: @MainActor () -> Void
        @State private var selection: Pane
        @State private var isShowingLicenses = false

        public init(
            lockedAccount: AccountSummary?,
            onShowLockScreen: @escaping () -> Void,
            onSignOut: @escaping () -> Void,
            onTip: @escaping @MainActor () -> Void
        ) {
            self.init(
                lockedAccount: lockedAccount,
                selection: .general,
                onShowLockScreen: onShowLockScreen,
                onSignOut: onSignOut,
                onTip: onTip
            )
        }

        init(
            lockedAccount: AccountSummary?,
            selection: Pane,
            onShowLockScreen: @escaping () -> Void,
            onSignOut: @escaping () -> Void,
            onTip: @escaping @MainActor () -> Void
        ) {
            self.lockedAccount = lockedAccount
            self.onShowLockScreen = onShowLockScreen
            self.onSignOut = onSignOut
            self.onTip = onTip
            _selection = State(initialValue: selection)
        }

        private var visibleSelection: Pane {
            selection == .account && lockedAccount == nil ? .general : selection
        }

        private var title: String? {
            switch visibleSelection {
            case .account: lockedAccount?.displayName
            case .general: MacSettingsCategory.general.headerTitle
            case .about: MacSettingsCategory.about.headerTitle
            }
        }

        public var body: some View {
            MacSettingsShell {
                Section {
                    if let lockedAccount {
                        MacLockedAccountRow(account: lockedAccount, isSelected: visibleSelection == .account) {
                            selection = .account
                        }
                        .macSettingsSidebarRow()
                    }
                    categoryRow(.general, pane: .general)
                }
                Section {
                    categoryRow(.about, pane: .about)
                }
            } detail: {
                MacPaneCard(title: title, subtitle: nil) {
                    pane
                }
            }
            .macLicensesSheet(isPresented: $isShowingLicenses)
        }

        private func categoryRow(_ category: MacSettingsCategory, pane: Pane) -> some View {
            MacSidebarRow(title: category.title, icon: category.icon, isSelected: visibleSelection == pane) {
                selection = pane
            }
            .macSettingsSidebarRow()
        }

        @ViewBuilder
        private var pane: some View {
            switch visibleSelection {
            case .account:
                if let lockedAccount {
                    MacLockedAccountPane(
                        account: lockedAccount,
                        onShowLockScreen: onShowLockScreen,
                        onSignOut: onSignOut
                    )
                }
            case .general:
                MacGeneralSettingsTab(showHiddenFiles: nil) {
                    if let lockedAccount {
                        HStack(spacing: .space12) {
                            MacNote(L10n.LockedSettings.note(lockedAccount.displayName), kind: .warning)
                            Button(L10n.LockedSettings.showLockScreen, action: onShowLockScreen)
                                .buttonStyle(.macDS(.primary, size: .small))
                                .fixedSize()
                        }
                    }
                }
            case .about:
                MacSettingsInfoPane(onTip: onTip) { isShowingLicenses = true }
            }
        }
    }

    private struct MacLockedAccountRow: View {
        let account: AccountSummary
        let isSelected: Bool
        let action: () -> Void
        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: .space12) {
                    MacLockedAvatar(name: account.displayName, size: Metrics.sidebarAvatarSize)
                    VStack(alignment: .leading, spacing: .zero) {
                        Text(account.displayName)
                            .type(.body1(isSelected ? .semibold : .regular))
                            .foregroundStyle(Color.macChromeText)
                            .lineLimit(1)
                        Text(L10n.Lock.status)
                            .type(.body3(.regular))
                            .foregroundStyle(Color.macChromeSecondary)
                    }
                    Spacer(minLength: .zero)
                }
                .padding(.horizontal, .space12)
                .macSidebarItemFrame(isRail: false, height: Metrics.sidebarRowHeight)
                .macSidebarSelection(isSelected: isSelected, isHovered: isHovered)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .onHover { isHovered = $0 }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        }
    }

    private struct MacLockedAccountPane: View {
        let account: AccountSummary
        let onShowLockScreen: () -> Void
        let onSignOut: () -> Void

        var body: some View {
            MacFormPage {
                VStack(alignment: .leading, spacing: .space8) {
                    MacFormGroup {
                        MacFormRow {
                            HStack(spacing: .space12) {
                                MacLockedAvatar(name: account.displayName, size: Metrics.paneAvatarSize)
                                MacRowTitle(title: account.displayName, subtitle: account.serverHost)
                            }
                        } control: {
                            MacChip(text: L10n.Lock.status, tone: .amber)
                        }
                        if let policy = account.requireSignIn {
                            MacValueRow(L10n.RequireSignIn.sectionLock, policy.lockAfter.title)
                            MacValueRow(
                                L10n.RequireSignIn.keepOfflineFiles,
                                policy.shouldKeepOfflineFiles ? L10n.Common.on : L10n.Common.off
                            )
                        }
                    }
                    MacFormFootnote(L10n.LockedSettings.accountFooter)
                }
                HStack(spacing: .space8) {
                    Button(L10n.LockedSettings.showLockScreen, action: onShowLockScreen)
                        .buttonStyle(.macDS(.primary))
                    Button(L10n.MacSettings.signOut, role: .destructive, action: onSignOut)
                        .buttonStyle(.macDS(.secondary))
                }
            }
        }
    }

    private struct MacLockedAvatar: View {
        let name: String
        let size: CGFloat

        var body: some View {
            AvatarView(displayName: name, size: size)
                .overlay(alignment: .bottomTrailing) {
                    IconKit.lock
                        .resizable()
                        .scaledToFit()
                        .bold()
                        .frame(width: Metrics.badgeGlyphSize, height: Metrics.badgeGlyphSize)
                        .foregroundStyle(Color.macChromeText)
                        .frame(width: Metrics.badgeSize, height: Metrics.badgeSize)
                        .background(Circle().fill(Color.macChrome))
                        .offset(x: Metrics.badgeOffset, y: Metrics.badgeOffset)
                }
                .accessibilityHidden(true)
        }
    }

    extension View {
        func macSettingsSidebarRow() -> some View {
            listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
        }
    }

    #Preview("General") {
        MacLocalSettingsRoot(
            lockedAccount: .lockedPreview,
            onShowLockScreen: {},
            onSignOut: {},
            onTip: {}
        )
        .previewCanvas(.settingsWindow)
    }

    #Preview("Account") {
        MacLocalSettingsRoot(
            lockedAccount: .lockedPreview,
            selection: .account,
            onShowLockScreen: {},
            onSignOut: {},
            onTip: {}
        )
        .previewCanvas(.settingsWindow)
    }

    #Preview("Info, dark") {
        MacLocalSettingsRoot(
            lockedAccount: .lockedPreview,
            selection: .about,
            onShowLockScreen: {},
            onSignOut: {},
            onTip: {}
        )
        .previewCanvas(.settingsWindow)
        .environment(\.colorScheme, .dark)
    }

    #Preview("Signed out") {
        MacLocalSettingsRoot(
            lockedAccount: nil,
            onShowLockScreen: {},
            onSignOut: {},
            onTip: {}
        )
        .previewCanvas(.settingsWindow)
    }

    private extension AccountSummary {
        static let lockedPreview = AccountSummary(
            id: "a",
            username: User.preview.username,
            serverURL: URL(string: "https://files.example.com") ?? URL(fileURLWithPath: "/"),
            isActive: false,
            requireSignIn: RequireSignIn(),
            isLocked: true
        )
    }
#endif
