import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    /// Inset of a footer row's icon inside its pill, lining it up with the section rows above.
    static let footerRowInset: CGFloat = .space16
    /// Icon size for the iPad sidebar rows.
    static let sidebarIconSize: CGFloat = .iconMedium
    /// Space between a sidebar row's icon and its title, the same in every row.
    static let iconTitleSpacing: CGFloat = .space12
    /// The height of a section row in the iPad sidebar list, so the footer rows below it match.
    static let sidebarRowHeight: CGFloat = 52
    // The account block at the foot of the sidebar: larger on iPad, where it is a touch target
    // that opens the account popover.
    #if os(iOS)
        static let avatarSize: CGFloat = .size44
        static var profileNameType: Typography.TextType {
            .body1(.bold)
        }

        static var profileEmailType: Typography.TextType {
            .body3(.regular)
        }
    #elseif os(macOS)
        static let avatarSize: CGFloat = .size32
        static var profileNameType: Typography.TextType {
            .body3(.bold)
        }

        static var profileEmailType: Typography.TextType {
            .caption(.regular)
        }
    #endif
    /// The Mac sidebar column opens wider than the system default, since a Mac window has the
    /// space an iPad split view does not.
    static let macSidebarMinWidth: CGFloat = 240
    static let macSidebarIdealWidth: CGFloat = 280
    static let macSidebarMaxWidth: CGFloat = 360
    #if os(macOS)
        /// The Mac rows carry their own inset inside their pill, so the footer sits on the sections' edge.
        static let footerHorizontalPadding: CGFloat = .space8
        static let profileInset: CGFloat = MacSidebarMetrics.rowHorizontalPadding
    #else
        static let footerHorizontalPadding: CGFloat = .space16
        static let profileInset: CGFloat = footerRowInset
    #endif
}

/// The split view's sidebar on iPad and the Mac: the app's name, the sections, then the tip jar, help
/// and Settings, and the signed in account at the foot. Compact width uses the bottom tab bar instead.
struct MainTabSidebar: View {
    let store: StoreOf<MainTabFeature>
    @Environment(\.openURL) private var openURL
    #if os(macOS)
        @Environment(\.openSettings) private var openSettings
    #endif

    /// The tab bar's identifiers, so a sidebar row is the same destination to VoiceOver and UI tests.
    private static func identifier(for tab: MainTabFeature.Tab) -> String {
        switch tab {
        case .browse: AccessibilityIdentifiers.Tab.browse
        case .favorites: AccessibilityIdentifiers.Tab.favorites
        case .shared: AccessibilityIdentifiers.Tab.shared
        case .downloads: AccessibilityIdentifiers.Tab.downloads
        case .settings: AccessibilityIdentifiers.Tab.settings
        }
    }

    private static var sectionItems: [(tab: MainTabFeature.Tab, title: String, icon: Image)] {
        [
            (.browse, L10n.Tab.browse, IconKit.tabBrowse),
            (.favorites, L10n.Tab.favorites, IconKit.tabFavorites),
            (.shared, L10n.Tab.shared, IconKit.tabShare),
            (.downloads, L10n.Tab.offline, IconKit.tabDownloads),
        ]
    }

    var body: some View {
        #if os(macOS)
            // Rows of its own on the window's frosted glass, rather than a list, so selection and
            // hover are the same pill in the sections and the footer.
            macSections
                .safeAreaInset(edge: .top, spacing: 0) {
                    MacSidebarHeader()
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    sidebarFooter
                }
                .navigationSplitViewColumnWidth(
                    min: Constants.macSidebarMinWidth,
                    ideal: Constants.macSidebarIdealWidth,
                    max: Constants.macSidebarMaxWidth
                )
        #else
            sidebarList
                .listStyle(.sidebar)
                // Suppress the system's opaque accent selection capsule; each row draws its own
                // pill via `listRowBackground` instead.
                .tint(Color.clear)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    sidebarFooter
                }
        #endif
    }

    #if os(macOS)
        private var macSections: some View {
            VStack(spacing: .space4) {
                ForEach(Self.sectionItems, id: \.tab) { item in
                    MacSidebarLinkRow(
                        title: item.title,
                        icon: Self.macIcon(for: item.tab),
                        isSelected: store.selectedTab == item.tab,
                        showsNewFilesDot: item.tab == .downloads && store.hasUnseenOfflineFiles
                    ) {
                        store.send(.tabSelected(item.tab))
                    }
                    .accessibilityIdentifier(Self.identifier(for: item.tab))
                }
            }
            .padding(.horizontal, .space8)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    #endif

    #if os(iOS)
        private var sidebarList: some View {
            List(selection: Binding(
                get: { store.selectedTab },
                set: {
                    if let tab = $0 {
                        store.send(.tabSelected(tab))
                    }
                }
            )) {
                Section {
                    appIdentity
                }
                Section {
                    ForEach(Self.sectionItems, id: \.tab) { item in
                        sidebarRow(item)
                    }
                }
            }
        }

        /// The app icon and name, heading the sidebar. Not a destination, so it carries no tag.
        /// Laid out like a section row (same icon frame, same leading edge), so the logo lines up with
        /// the section icons below it.
        private var appIdentity: some View {
            HStack(spacing: Constants.iconTitleSpacing) {
                IconKit.logo
                    .resizable()
                    .scaledToFit()
                    .frame(width: Constants.sidebarIconSize, height: Constants.sidebarIconSize)
                    .accessibilityHidden(true)
                Text(AppIdentity.name)
                    .type(.headline4, style: .primaryOnSurface)
                    .lineLimit(1)
            }
            .padding(.vertical, .space4)
            .accessibilityAddTraits(.isHeader)
            .listRowBackground(Color.clear)
        }
    #endif

    #if os(macOS)
        /// The tab bar artwork is drawn for iOS tab bars; the Mac sidebar uses system symbols
        /// at the standard sidebar size instead.
        private static func macIcon(for tab: MainTabFeature.Tab) -> Image {
            switch tab {
            case .browse: IconKit.folder
            case .favorites: IconKit.star
            case .shared: IconKit.shareLink
            case .downloads: IconKit.availableOffline
            case .settings: IconKit.gearshape
            }
        }
    #endif

    #if os(iOS)
        private func sidebarRow(_ item: (tab: MainTabFeature.Tab, title: String, icon: Image)) -> some View {
            let hasNewFiles = item.tab == .downloads && store.hasUnseenOfflineFiles
            let isSelected = store.selectedTab == item.tab
            return HStack {
                rowLabel(item.title, icon: item.icon, isSelected: isSelected)
                    .accessibilityLabel(item.title)
                if hasNewFiles {
                    Spacer()
                    NewFilesDot()
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .combine)
            // The dot reads as the row's value, as it does on the tab bar, not as part of its name.
            .accessibilityValue(hasNewFiles ? L10n.Offline.newFilesBadge : "")
            .accessibilityIdentifier(Self.identifier(for: item.tab))
            .accessibilityAddTraits(.isButton)
            .tag(item.tab)
            .listRowBackground(SidebarSelectionPill(isSelected: isSelected))
        }
    #endif

    #if os(iOS)
        /// One explicit stack rather than a `Label`, whose icon spacing differs inside a List and out of
        /// one: the section rows and the footer rows then line up exactly.
        private func rowLabel(_ title: String, icon: Image, isSelected: Bool) -> some View {
            HStack(spacing: Constants.iconTitleSpacing) {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: Constants.sidebarIconSize, height: Constants.sidebarIconSize)
                    .foregroundStyle(isSelected ? Color.primaryDS : Color.secondaryDS)
                Text(title)
                    .type(
                        .body1(isSelected ? .semibold : .regular),
                        style: isSelected ? .primaryOnSurface : .secondary
                    )
            }
        }
    #endif

    /// The tip jar, help and Settings, then a divider and the signed in account.
    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 0) {
            footerButton(L10n.TipJar.title, icon: IconKit.coffee, action: openTipJar)
            footerButton(L10n.Settings.rowSupport, icon: IconKit.help, opensOutside: true) {
                openURL(AppLinks.support)
            }
            settingsButton
            Divider()
                .padding(.top, .space16)
                .padding(.bottom, .space24)
            sidebarProfile
        }
        .padding(.horizontal, Constants.footerHorizontalPadding)
        .padding(.vertical, .space12)
    }

    private var settingsButton: some View {
        #if os(macOS)
            // Settings has its own window (⌘,) on the Mac.
            footerButton(L10n.Tab.settings, icon: IconKit.gearshape) { openSettings() }
        #else
            footerButton(L10n.Tab.settings, icon: IconKit.gearshape, isSelected: store.selectedTab == .settings) {
                store.send(.tabSelected(.settings))
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.Tab.settings)
        #endif
    }

    /// The Mac's main window hosts the tip jar; on iPad it is Settings, so the jar opens there.
    private func openTipJar() {
        #if os(iOS)
            store.send(.tabSelected(.settings))
        #endif
        store.send(.settings(.tipJarButtonTapped))
    }

    private func footerButton(
        _ title: String,
        icon: Image,
        isSelected: Bool = false,
        opensOutside: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        #if os(macOS)
            // The same frosted row as the sections, so both groups read as one sidebar.
            MacSidebarLinkRow(title: title, icon: icon, isSelected: isSelected, action: action)
        #else
            // The section rows' own label, height and inset, so both groups read as one list.
            Button(action: action) {
                HStack {
                    rowLabel(title, icon: icon, isSelected: isSelected)
                        .lineLimit(1)
                    if opensOutside {
                        Spacer(minLength: 0)
                        // A page outside the app, marked like a link that leaves it.
                        IconKit.externalLink
                            .foregroundStyle(Color.secondaryDS)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, Constants.footerRowInset)
                .frame(maxWidth: .infinity, minHeight: Constants.sidebarRowHeight, alignment: .leading)
                .background(SidebarSelectionPill(isSelected: isSelected))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        #endif
    }

    /// Signed in identity at the foot of the sidebar: avatar, name and email. It opens the account
    /// popover, for switching, adding and signing out without a trip to Settings.
    private var sidebarProfile: some View {
        SidebarAccountMenu(
            store: store.scope(state: \.settings, action: \.settings),
            onChangePassword: {
                #if os(iOS)
                    // Change Password is pushed inside Settings on iPad.
                    store.send(.tabSelected(.settings))
                #endif
                store.send(.settings(.changePasswordButtonTapped))
            },
            revealSettings: {
                #if os(iOS)
                    store.send(.tabSelected(.settings))
                #endif
            }
        ) {
            HStack(spacing: .space8) {
                profileSummary
                IconKit.chevronUpDown
                    .foregroundStyle(Color.secondaryDS)
            }
            .contentShape(Rectangle())
        }
    }

    private var profileSummary: some View {
        HStack(spacing: .space12) {
            AvatarView(displayName: store.settings.displayName, size: Constants.avatarSize)
            VStack(alignment: .leading, spacing: .space2) {
                Text(store.settings.displayName)
                    .type(Constants.profileNameType, style: .primaryOnSurface)
                    .lineLimit(1)
                if let email = store.settings.user.email {
                    Text(email)
                        .type(Constants.profileEmailType, style: .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Constants.profileInset)
    }
}

#if os(iOS)
    /// The selected row's pill: the accent capsule, so the sidebar's selection reads like the tab bar's.
    private struct SidebarSelectionPill: View {
        let isSelected: Bool

        var body: some View {
            if isSelected {
                Capsule(style: .continuous)
                    .fill(Color.accent)
                    .padding(.vertical, .space2)
            } else {
                Color.clear
            }
        }
    }
#endif

@MainActor
private func previewSidebar(selectedTab: MainTabFeature.Tab = .browse) -> some View {
    var state = MainTabFeature.State(
        serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
        user: User(id: "preview-user", username: "jdoe", email: "jane.doe@example.com", displayName: "Jane Doe")
    )
    state.selectedTab = selectedTab
    let store = Store(initialState: state) { MainTabFeature() } withDependencies: {
        $0.filesClient = .previewValue
    }
    return NavigationSplitView {
        MainTabSidebar(store: store)
    } detail: {
        Color.clear
    }
}

#Preview("Browse") {
    previewSidebar()
}

#Preview("Settings") {
    previewSidebar(selectedTab: .settings)
}
