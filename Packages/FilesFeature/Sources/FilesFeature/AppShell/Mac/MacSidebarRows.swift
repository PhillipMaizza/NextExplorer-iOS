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
        static let railRadius: CGFloat = 14
        static let railDotInset: CGFloat = 9
    }

    enum MacSidebarRail {
        static let width: CGFloat = 84
        static let item: CGFloat = .size48
    }

    extension EnvironmentValues {
        @Entry var isMacSidebarRail = false
        @Entry var isMacAccountPanelShown: Binding<Bool> = .constant(false)
    }

    struct MacSidebarIdentity: View {
        let action: () -> Void
        @Environment(\.isMacSidebarRail) private var isRail
        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: .space8) {
                    IconKit.logo
                        .resizable()
                        .scaledToFit()
                        .frame(width: Constants.logoSize, height: Constants.logoSize)
                        .accessibilityHidden(true)
                    if !isRail {
                        Text(AppIdentity.name)
                            .type(.headline4)
                            .foregroundStyle(Color.macChromeText)
                            .lineLimit(1)
                        Spacer(minLength: .zero)
                    }
                }
                .padding(.horizontal, isRail ? .zero : .space12)
                .macSidebarItemFrame(isRail: isRail, height: Constants.brandHeight)
                .background(
                    RoundedRectangle(
                        cornerRadius: isRail ? Constants.railRadius : Constants.rowRadius,
                        style: .continuous
                    )
                    .fill(isHovered ? Color.macChromeHover : .clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
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
        var shortcut: String?
        var hasDot = false
        let action: () -> Void
        @ViewBuilder var trailing: () -> Trailing
        @Environment(\.isMacSidebarRail) private var isRail
        @State private var isHovered = false

        private var tooltip: String {
            [title, shortcut].compactMap(\.self).joined(separator: "  ")
        }

        var body: some View {
            Button(action: action) {
                HStack(spacing: size.iconSpacing) {
                    icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: size.iconSize, height: size.iconSize)
                        .foregroundStyle(isSelected ? Color.accentText : Color.macChromeSecondary)
                        .accessibilityHidden(true)
                    if !isRail {
                        Text(title)
                            .type(size.textType(isSelected: isSelected))
                            .foregroundStyle(Color.macChromeText)
                            .lineLimit(1)
                        Spacer(minLength: .zero)
                        if hasDot {
                            NewFilesDot()
                                .accessibilityHidden(true)
                        }
                        if let shortcut {
                            MacKeyHint(shortcut, isHighlighted: isSelected)
                        }
                        trailing()
                    }
                }
                .padding(.horizontal, isRail ? .zero : .space12)
                .macSidebarItemFrame(isRail: isRail, height: size.height)
                .overlay(alignment: .topTrailing) {
                    if isRail, hasDot {
                        NewFilesDot()
                            .padding(Constants.railDotInset)
                            .accessibilityHidden(true)
                    }
                }
                .background {
                    if isSelected {
                        RoundedRectangle(
                            cornerRadius: isRail ? Constants.railRadius : Constants.rowRadius,
                            style: .continuous
                        )
                        .fill(Color.macSelection)
                        .shadow(
                            color: .macCardShadow,
                            radius: Constants.selectionShadowRadius,
                            y: Constants.selectionShadowOffset
                        )
                    } else if isHovered {
                        RoundedRectangle(
                            cornerRadius: isRail ? Constants.railRadius : Constants.rowRadius,
                            style: .continuous
                        )
                        .fill(Color.macChromeHover)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.vertical, size.rowGap)
            .onHover { isHovered = $0 }
            .help(isRail ? tooltip : "")
            .accessibilityLabel(title)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    extension MacSidebarRow where Trailing == EmptyView {
        init(
            title: String,
            icon: Image,
            isSelected: Bool = false,
            size: Size = .compact,
            shortcut: String? = nil,
            hasDot: Bool = false,
            action: @escaping () -> Void
        ) {
            self.init(
                title: title,
                icon: icon,
                isSelected: isSelected,
                size: size,
                shortcut: shortcut,
                hasDot: hasDot,
                action: action
            ) { EmptyView() }
        }
    }

    private extension View {
        func macSidebarItemFrame(isRail: Bool, height: CGFloat) -> some View {
            frame(
                minWidth: isRail ? MacSidebarRail.item : nil,
                maxWidth: isRail ? MacSidebarRail.item : .infinity,
                minHeight: isRail ? MacSidebarRail.item : height,
                alignment: isRail ? .center : .leading
            )
        }
    }

    /// The Mac sidebar's sections: the app's name, then a row per section with its ⌘ shortcut.
    enum MacShortcutHint {
        static let settings = "\u{2318},"
        static let search = "\u{2318}K"
        static let find = "\u{2318}F"
        static let escape = "esc"
        static let arrows = "\u{2191}\u{2193}"
        static let sideArrows = "\u{2190}\u{2192}"
        static let back = "\u{2318}["
        static let enter = "\u{21B5}"
        static let space = "space"

        static func tab(_ number: Int) -> String {
            "\u{2318}\(number)"
        }
    }

    struct MacSidebarSections: View {
        let store: StoreOf<MainTabFeature>
        @Environment(\.openWindow) private var openWindow

        /// The ⌘1 to ⌘5 hint shown at a row's trailing edge; Trash only exists where the server has one.
        private static func shortcutHint(for tab: MainTabFeature.Tab) -> String? {
            guard let index = MainTabSidebar.sectionItems(showsTrash: true).firstIndex(where: { $0.tab == tab })
            else { return nil }
            return MacShortcutHint.tab(index + 1)
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
                size: .regular,
                shortcut: Self.shortcutHint(for: item.tab),
                hasDot: hasNewFiles
            ) {
                store.send(.tabSelected(item.tab))
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

    #Preview("Sections, rail") {
        previewSections(selectedTab: .downloads)
            .environment(\.isMacSidebarRail, true)
            .frame(width: MacSidebarRail.width)
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
                shortcut: MacShortcutHint.tab(1),
                action: {}
            )
            MacSidebarRow(
                title: L10n.Tab.offline,
                icon: IconKit.macSidebarOffline,
                size: .regular,
                shortcut: MacShortcutHint.tab(4),
                hasDot: true,
                action: {}
            )
            MacSidebarRow(title: L10n.Tab.settings, icon: IconKit.macSidebarSettings, size: .regular, action: {})
        }
        .padding()
        .frame(width: MacSidebarWidth.ideal)
    }
#endif
