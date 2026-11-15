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
    /// A Mac footer row's height and hover wash, matching the system list rows above.
    static let macRowHeight: CGFloat = 28
    /// Where the system's selection pill sits inside a sidebar row, so the hover wash lines up with it.
    static let macPillInset: CGFloat = .space16
    static let hoverOpacity: Double = 0.08
    static let selectedOpacity: Double = 0.14
    static let macLogoSize: CGFloat = .size32
    /// Keeps the account chevron off the Mac card's edge.
    static let chevronTrailingInset: CGFloat = .space12
    /// The wash behind the Mac account card.
    static let accountCardOpacity: Double = 0.06
    static let macSidebarMinWidth: CGFloat = 200
    static let macSidebarIdealWidth: CGFloat = 250
    static let macSidebarMaxWidth: CGFloat = 360
    #if os(macOS)
        /// The Mac rows carry their own inset inside their pill, so the footer sits on the sections' edge.
        static let footerHorizontalPadding: CGFloat = macPillInset
        static let profileInset: CGFloat = .space8
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
        @Environment(\.openWindow) private var openWindow
    #endif

    #if os(macOS)
        /// The Mac column's width range, applied where the split view hosts the sidebar.
        static let macColumnWidth = (
            min: Constants.macSidebarMinWidth,
            ideal: Constants.macSidebarIdealWidth,
            max: Constants.macSidebarMaxWidth
        )
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
            // The system sidebar list: native selection, hover and vibrancy over the window's glass.
            // The footer is a sibling of the list, not an inset over it, so its rows get their own hover.
            VStack(spacing: 0) {
                macSections
                    .listStyle(.sidebar)
                sidebarFooter
            }
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
        /// The ⌘1 to ⌘4 hint shown at a row's trailing edge.
        private static func shortcutHint(for tab: MainTabFeature.Tab) -> String? {
            guard let index = sectionItems.firstIndex(where: { $0.tab == tab }) else { return nil }
            return "\u{2318} \(index + 1)"
        }

        /// The logo and name above the sections. Opens the About window, and is not a destination.
        private var macIdentity: some View {
            MacSidebarIdentity {
                openWindow(id: MacAboutView.windowID)
            }
            .selectionDisabled()
            .listRowSeparator(.hidden)
        }

        private func macRow(_ item: (tab: MainTabFeature.Tab, title: String, icon: Image)) -> some View {
            let hasNewFiles = item.tab == .downloads && store.hasUnseenOfflineFiles
            return MacSidebarRow(
                title: item.title,
                icon: Self.macIcon(for: item.tab),
                isSelected: store.selectedTab == item.tab
            ) {
                store.send(.tabSelected(item.tab))
            } trailing: {
                if hasNewFiles {
                    NewFilesDot()
                        .accessibilityHidden(true)
                }
                if let hint = Self.shortcutHint(for: item.tab) {
                    MacTag(text: hint)
                }
            }
            .listRowInsets(EdgeInsets())
            .accessibilityValue(hasNewFiles ? L10n.Offline.newFilesBadge : "")
            .accessibilityIdentifier(Self.identifier(for: item.tab))
        }

        private var macSections: some View {
            List {
                macIdentity
                ForEach(Self.sectionItems, id: \.tab) { item in
                    macRow(item)
                }
            }
            // The menu bar owns ⌘1 to ⌘3; Offline lives in the sidebar only, so ⌘4 is bound here.
            .background {
                Button(L10n.Tab.offline) { store.send(.tabSelected(.downloads)) }
                    .keyboardShortcut("4")
                    .opacity(0)
                    .accessibilityHidden(true)
            }
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
                #if os(macOS)
                    openURL(AppLinks.supportMail)
                #else
                    openURL(AppLinks.support)
                #endif
            }
            #if os(iOS)
                settingsButton
            #endif
            #if os(macOS)
                sidebarProfile
                    .padding(.vertical, .space8)
                    .background(
                        RoundedRectangle(cornerRadius: .radiusControl, style: .continuous)
                            .fill(Color.primaryDS.opacity(Constants.accountCardOpacity))
                    )
                    .padding(.top, .space12)
            #else
                Divider()
                    .padding(.top, .space16)
                    .padding(.bottom, .space24)
                sidebarProfile
            #endif
        }
        .padding(.horizontal, Constants.footerHorizontalPadding)
        .padding(.vertical, .space12)
    }

    #if os(iOS)
        private var settingsButton: some View {
            footerButton(L10n.Tab.settings, icon: IconKit.gearshape, isSelected: store.selectedTab == .settings) {
                store.send(.tabSelected(.settings))
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.Tab.settings)
        }
    #endif

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
            MacSidebarRow(title: title, icon: icon, action: action) {
                if opensOutside {
                    IconKit.externalLink
                        .foregroundStyle(Color.secondaryDS)
                        .accessibilityHidden(true)
                }
            }
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
                    .padding(.trailing, Constants.chevronTrailingInset)
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

#if os(macOS)
    /// The logo and name above the sections. Opens the About window, with the same hover pill as the rows.
    private struct MacSidebarIdentity: View {
        let action: () -> Void
        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: .space8) {
                    IconKit.logo
                        .resizable()
                        .scaledToFit()
                        .frame(width: Constants.macLogoSize, height: Constants.macLogoSize)
                        .accessibilityHidden(true)
                    Text(AppIdentity.name)
                        .type(.headline4, style: .primaryOnSurface)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, .space12)
                .frame(maxWidth: .infinity, minHeight: Constants.macRowHeight, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: .radiusControl, style: .continuous)
                        .fill(Color.primaryDS.opacity(isHovered ? Constants.hoverOpacity : 0))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, .space8)
            .onHover { isHovered = $0 }
            .help(L10n.Menu.about)
            .accessibilityLabel(L10n.Menu.about)
        }
    }

    /// A sidebar row drawn here rather than by the list, so the selected and hovered pills keep a gap
    /// between rows. Used by the sections and the footer links alike.
    private struct MacSidebarRow<Trailing: View>: View {
        let title: String
        let icon: Image
        var isSelected = false
        let action: () -> Void
        @ViewBuilder var trailing: () -> Trailing
        @State private var isHovered = false

        private var fillOpacity: Double {
            if isSelected {
                Constants.selectedOpacity
            } else if isHovered {
                Constants.hoverOpacity
            } else {
                0
            }
        }

        var body: some View {
            Button(action: action) {
                HStack {
                    Label {
                        Text(title)
                    } icon: {
                        MacSidebarIcon(image: icon)
                    }
                    .fontWeight(isSelected ? .semibold : .regular)
                    Spacer(minLength: 0)
                    trailing()
                }
                .padding(.horizontal, .space12)
                .frame(maxWidth: .infinity, minHeight: Constants.macRowHeight, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: .radiusControl, style: .continuous)
                        .fill(Color.primaryDS.opacity(fillOpacity))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, .space2)
            .onHover { isHovered = $0 }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
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
