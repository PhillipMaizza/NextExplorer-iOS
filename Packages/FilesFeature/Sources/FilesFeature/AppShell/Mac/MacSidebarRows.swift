#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Constants {
        /// A Mac sidebar row's height and hover wash, matching the system list rows.
        static let macRowHeight: CGFloat = 28
        static let hoverOpacity: Double = 0.08
        static let selectedOpacity: Double = 0.14
        static let macLogoSize: CGFloat = .size24
    }

    /// The logo and name above the sections. Opens the About window, with the same hover pill as the rows.
    struct MacSidebarIdentity: View {
        let action: () -> Void
        @State private var isHovered = false

        var body: some View {
            aboutButton
        }

        private var aboutButton: some View {
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
    struct MacSidebarRow<Trailing: View>: View {
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
                        MacSidebarIcon(image: icon, isAccented: isSelected)
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

    /// The Mac sidebar's sections: the app's name, then a row per section with its ⌘ shortcut.
    struct MacSidebarSections: View {
        let store: StoreOf<MainTabFeature>
        @Environment(\.openWindow) private var openWindow

        /// The ⌘1 to ⌘5 hint shown at a row's trailing edge; Trash only exists where the server has one.
        private static func shortcutHint(for tab: MainTabFeature.Tab) -> String? {
            guard let index = MainTabSidebar.sectionItems(showsTrash: true).firstIndex(where: { $0.tab == tab })
            else { return nil }
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
            let isSelected = store.selectedTab == item.tab
            return MacSidebarRow(
                title: item.title,
                icon: Self.macIcon(for: item.tab, isSelected: isSelected),
                isSelected: isSelected
            ) {
                store.send(.tabSelected(item.tab))
            } trailing: {
                if hasNewFiles {
                    NewFilesDot()
                        .accessibilityHidden(true)
                }
                if let hint = Self.shortcutHint(for: item.tab) {
                    MacTag(
                        text: hint,
                        tint: isSelected ? .accent : .tertiaryDS,
                        style: isSelected ? .link : .tertiary
                    )
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

        /// The tab bar artwork is drawn for iOS tab bars; the Mac sidebar uses system symbols
        /// at the standard sidebar size instead.
        private static func macIcon(for tab: MainTabFeature.Tab, isSelected: Bool) -> Image {
            switch tab {
            case .browse: isSelected ? IconKit.folderFill : IconKit.folder
            case .favorites: isSelected ? IconKit.starFill : IconKit.star
            case .shared: isSelected ? IconKit.shareLinkFill : IconKit.shareLink
            case .downloads: isSelected ? IconKit.availableOfflineFill : IconKit.availableOffline
            case .settings: isSelected ? IconKit.gearshapeFill : IconKit.gearshape
            case .trash: isSelected ? IconKit.deleteFill : IconKit.delete
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
            .frame(width: 250, height: 260)
    }

    #Preview("Sections, Browse") {
        previewSections(selectedTab: .browse)
    }

    #Preview("Sections, Offline") {
        previewSections(selectedTab: .downloads)
    }

    #Preview("Identity") {
        MacSidebarIdentity {}
            .padding()
            .frame(width: 250)
    }

    #Preview("Rows") {
        VStack(spacing: 0) {
            MacSidebarRow(title: L10n.Tab.browse, icon: IconKit.tabBrowse, isSelected: true, action: {}) {
                MacTag(text: "\u{2318} 1")
            }
            MacSidebarRow(title: L10n.Tab.favorites, icon: IconKit.tabFavorites, action: {}) { EmptyView() }
        }
        .padding()
        .frame(width: 250)
    }
#endif
