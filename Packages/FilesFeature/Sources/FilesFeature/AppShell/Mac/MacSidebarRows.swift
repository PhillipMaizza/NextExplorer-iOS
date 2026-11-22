#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Constants {
        static let brandHeight: CGFloat = .size40
        static let logoSize: CGFloat = 26
        static let rowRadius: CGFloat = .radiusControl
        static let selectionShadowRadius: CGFloat = 1
        static let selectionShadowOffset: CGFloat = 1
        static let avatarSize: CGFloat = .size32
        static let chevronSize: CGFloat = .iconSmall
    }

    struct MacSidebarIdentity: View {
        let action: () -> Void
        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: .space8) {
                    IconKit.logo
                        .resizable()
                        .scaledToFit()
                        .frame(width: Constants.logoSize, height: Constants.logoSize)
                        .accessibilityHidden(true)
                    Text(AppIdentity.name)
                        .type(.headline4)
                        .foregroundStyle(Color.macChromeText)
                        .lineLimit(1)
                    Spacer(minLength: .zero)
                }
                .padding(.horizontal, .space12)
                .frame(maxWidth: .infinity, minHeight: Constants.brandHeight, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Constants.rowRadius, style: .continuous)
                        .fill(isHovered ? Color.macChromeHover : .clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, .space8)
            .onHover { isHovered = $0 }
            .help(L10n.Menu.about)
            .accessibilityLabel(L10n.Menu.about)
        }
    }

    struct MacSidebarRow<Trailing: View>: View {
        enum Size {
            case compact
            case regular

            var height: CGFloat {
                switch self {
                case .compact: 28
                case .regular: 36
                }
            }

            var iconSize: CGFloat {
                switch self {
                case .compact: 17
                case .regular: 18
                }
            }

            var iconSpacing: CGFloat {
                switch self {
                case .compact: .space12
                case .regular: .space8
                }
            }

            var rowGap: CGFloat {
                switch self {
                case .compact: .space2
                case .regular: .zero
                }
            }

            func textType(isSelected: Bool) -> Typography.TextType {
                switch self {
                case .compact: .body2(isSelected ? .semibold : .regular)
                case .regular: .body1(isSelected ? .semibold : .regular)
                }
            }
        }

        let title: String
        let icon: Image
        var isSelected = false
        var size: Size = .compact
        let action: () -> Void
        @ViewBuilder var trailing: () -> Trailing
        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: size.iconSpacing) {
                    icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: size.iconSize, height: size.iconSize)
                        .foregroundStyle(isSelected ? Color.accentText : Color.macChromeSecondary)
                        .accessibilityHidden(true)
                    Text(title)
                        .type(size.textType(isSelected: isSelected))
                        .foregroundStyle(Color.macChromeText)
                        .lineLimit(1)
                    Spacer(minLength: .zero)
                    trailing()
                }
                .padding(.horizontal, .space12)
                .frame(maxWidth: .infinity, minHeight: size.height, alignment: .leading)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Constants.rowRadius, style: .continuous)
                            .fill(Color.macSelection)
                            .shadow(
                                color: .macCardShadow,
                                radius: Constants.selectionShadowRadius,
                                y: Constants.selectionShadowOffset
                            )
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: Constants.rowRadius, style: .continuous)
                            .fill(Color.macChromeHover)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, size.rowGap)
            .onHover { isHovered = $0 }
            .accessibilityLabel(title)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    /// The Mac sidebar's sections: the app's name, then a row per section with its ⌘ shortcut.
    struct MacSidebarSections: View {
        let store: StoreOf<MainTabFeature>
        @Environment(\.openWindow) private var openWindow

        /// The ⌘1 to ⌘5 hint shown at a row's trailing edge; Trash only exists where the server has one.
        private static func shortcutHint(for tab: MainTabFeature.Tab) -> String? {
            guard let index = MainTabSidebar.sectionItems(showsTrash: true).firstIndex(where: { $0.tab == tab })
            else { return nil }
            return "\u{2318}\(index + 1)"
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
            let isSelected = store.selectedTab == item.tab
            return MacSidebarRow(
                title: item.title,
                icon: Self.macIcon(for: item.tab),
                isSelected: isSelected,
                size: .regular
            ) {
                store.send(.tabSelected(item.tab))
            } trailing: {
                if hasNewFiles {
                    NewFilesDot()
                        .accessibilityHidden(true)
                }
                if let hint = Self.shortcutHint(for: item.tab) {
                    MacKeyHint(hint, isHighlighted: isSelected)
                }
            }
            .listRowInsets(EdgeInsets())
            .accessibilityValue(hasNewFiles ? L10n.Offline.newFilesBadge : "")
            .accessibilityIdentifier(MainTabSidebar.identifier(for: item.tab))
        }

        var body: some View {
            List {
                macIdentity
                ForEach(
                    MainTabSidebar.sectionItems(showsTrash: store.browse.root.isTrashAvailable),
                    id: \.tab
                ) { item in
                    macRow(item)
                }
            }
            // The menu bar owns ⌘1 to ⌘3; Offline and Trash live in the sidebar only, so ⌘4 and ⌘5
            // are bound here, ⌘5 only while the server has a trash.
            .background {
                Button(L10n.Tab.offline) { store.send(.tabSelected(.downloads)) }
                    .keyboardShortcut("4")
                    .opacity(0)
                    .accessibilityHidden(true)
                if store.browse.root.isTrashAvailable {
                    Button(L10n.Trash.title) { store.send(.tabSelected(.trash)) }
                        .keyboardShortcut("5")
                        .opacity(0)
                        .accessibilityHidden(true)
                }
            }
        }

        private static func macIcon(for tab: MainTabFeature.Tab) -> Image {
            switch tab {
            case .browse: IconKit.macSidebarBrowse
            case .favorites: IconKit.macSidebarFavorites
            case .shared: IconKit.macSidebarShared
            case .downloads: IconKit.macSidebarOffline
            case .settings: IconKit.macSidebarSettings
            case .trash: IconKit.macSidebarTrash
            }
        }
    }

    struct MacSidebarAccountLabel: View {
        let displayName: String
        let server: String?
        @State private var isHovered = false

        var body: some View {
            HStack(spacing: .space12) {
                AvatarView(displayName: displayName, size: Constants.avatarSize)
                VStack(alignment: .leading, spacing: .space2) {
                    Text(displayName)
                        .type(.body2(.semibold))
                        .foregroundStyle(Color.macChromeText)
                        .lineLimit(1)
                    if let server {
                        Text(server)
                            .type(.body3(.regular))
                            .foregroundStyle(Color.macChromeSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: .zero)
                IconKit.chevronUpDown
                    .resizable()
                    .scaledToFit()
                    .frame(width: Constants.chevronSize, height: Constants.chevronSize)
                    .foregroundStyle(Color.macChromeSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, .space12)
            .padding(.vertical, .space8)
            .background(
                RoundedRectangle(cornerRadius: Constants.rowRadius, style: .continuous)
                    .fill(isHovered ? Color.macChromeButton : Color.macChromeHover)
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
        }
    }

    @MainActor
    private func previewSections(selectedTab: MainTabFeature.Tab) -> some View {
        var state = MainTabFeature.State(
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
            user: User.preview
        )
        state.selectedTab = selectedTab
        return MacSidebarSections(store: Store(initialState: state) { MainTabFeature() })
            .listStyle(.sidebar)
            .frame(width: MacSidebarWidth.ideal, height: MacSidebarWidth.ideal)
    }

    #Preview("Sections, Browse") {
        previewSections(selectedTab: .browse)
    }

    #Preview("Sections, Offline") {
        previewSections(selectedTab: .downloads)
    }

    #Preview("Account") {
        VStack(spacing: .space8) {
            MacSidebarAccountLabel(displayName: "Phillip Maizza", server: "nextexplorer.example.com")
            MacSidebarAccountLabel(displayName: "jdoe", server: nil)
        }
        .padding()
        .frame(width: MacSidebarWidth.ideal)
        .background(Color.macChrome)
    }

    #Preview("Identity") {
        MacSidebarIdentity {}
            .padding()
            .frame(width: MacSidebarWidth.ideal)
    }

    #Preview("Rows") {
        VStack(spacing: 0) {
            MacSidebarRow(
                title: L10n.Tab.browse,
                icon: IconKit.macSidebarBrowse,
                isSelected: true,
                size: .regular,
                action: {}
            ) {
                MacKeyHint("\u{2318}1", isHighlighted: true)
            }
            MacSidebarRow(title: L10n.Tab.favorites, icon: IconKit.macSidebarFavorites, size: .regular, action: {}) {
                MacKeyHint("\u{2318}2")
            }
            MacSidebarRow(title: L10n.Tab.settings, icon: IconKit.macSidebarSettings, size: .regular, action: {}) {
                EmptyView()
            }
        }
        .padding()
        .frame(width: MacSidebarWidth.ideal)
    }
#endif
