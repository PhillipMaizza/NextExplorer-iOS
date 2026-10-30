import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    /// Icon size for the iPad sidebar rows.
    static let sidebarIconSize: CGFloat = 24
    /// Opacity of the neutral selection pill behind the active sidebar row.
    static let sidebarSelectionOpacity: Double = 1.0
    /// Logo size in the iPad sidebar footer.
    static let sidebarFooterLogoSize: CGFloat = 40
    /// macOS sidebar: rows get extra breathing room and the column opens wider than the
    /// system default, since a Mac window has the space an iPad split view does not.
    static let macSidebarRowVerticalPadding: CGFloat = .space8
    static let macSidebarSelectionHorizontalInset: CGFloat = .space8
    static let macSidebarIconSize: CGFloat = .iconSmall
    static let macSidebarIconTitleSpacing: CGFloat = .space12
    static let macSidebarRowHorizontalPadding: CGFloat = .space12
    static let macSidebarMinWidth: CGFloat = 240
    static let macSidebarIdealWidth: CGFloat = 280
    static let macSidebarMaxWidth: CGFloat = 360
}

/// The split view's sidebar on iPad and the Mac: the signed in account, the sections, and the
/// app identity footer. Compact width uses the bottom tab bar instead.
struct MainTabSidebar: View {
    let store: StoreOf<MainTabFeature>
    #if os(macOS)
        @Environment(\.openSettings) private var openSettings
    #endif

    private static var sidebarItems: [(tab: MainTabFeature.Tab, title: String, icon: Image)] {
        [
            (.browse, L10n.Tab.browse, IconKit.tabBrowse),
            (.favorites, L10n.Tab.favorites, IconKit.tabFavorites),
            (.shared, L10n.Tab.shared, IconKit.tabShare),
            (.downloads, L10n.Tab.downloads, IconKit.tabDownloads),
            (.settings, L10n.Tab.settings, IconKit.tabSettings),
        ]
        #if os(macOS)
        // Mac downloads are saved wherever the user picks in Finder, so there is no in app
        // Downloads section to show; Settings has its own window (⌘,), opened by its own row.
        .filter { $0.tab != .downloads && $0.tab != .settings }
        #endif
    }

    var body: some View {
        sidebarList
            .listStyle(.sidebar)
            // Suppress the system's opaque accent selection capsule; each row draws its own
            // translucent neutral pill via `listRowBackground` instead.
            .tint(Color.clear)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                sidebarFooter
            }
        #if os(macOS)
            .navigationSplitViewColumnWidth(
                min: Constants.macSidebarMinWidth,
                ideal: Constants.macSidebarIdealWidth,
                max: Constants.macSidebarMaxWidth
            )
        #endif
    }

    /// macOS draws its own selection shape behind a selectable sidebar row that `.tint` can't
    /// hide, so on the Mac the rows are plain buttons and only the accent pill marks the tab.
    private var sidebarList: some View {
        #if os(macOS)
            List { sidebarSections }
        #else
            List(selection: Binding(
                get: { store.selectedTab },
                set: {
                    if let tab = $0 {
                        store.send(.tabSelected(tab))
                    }
                }
            )) { sidebarSections }
        #endif
    }

    @ViewBuilder
    private var sidebarSections: some View {
        Section {
            sidebarProfile
        }
        Section {
            ForEach(Self.sidebarItems, id: \.tab) { item in
                sidebarRow(item)
            }
            #if os(macOS)
                macSettingsRow
            #endif
        }
    }

    #if os(macOS)
        /// Settings is its own window on the Mac, so this row opens it instead of selecting a tab.
        private var macSettingsRow: some View {
            Button { openSettings() } label: {
                macSidebarLabel(title: L10n.Tab.settings, icon: IconKit.tabSettings, isSelected: false)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .accessibilityLabel(L10n.Tab.settings)
        }

        private func macSidebarLabel(title: String, icon: Image, isSelected: Bool) -> some View {
            HStack(spacing: Constants.macSidebarIconTitleSpacing) {
                sidebarIcon(icon, color: isSelected ? Color.primaryDS : Color.secondaryDS)
                Text(title)
                    .type(.body1(isSelected ? .semibold : .regular), style: isSelected ? .primaryOnSurface : .secondary)
            }
            .padding(.vertical, Constants.macSidebarRowVerticalPadding)
            .padding(.horizontal, Constants.macSidebarRowHorizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
    #endif

    private func sidebarRow(_ item: (tab: MainTabFeature.Tab, title: String, icon: Image)) -> some View {
        let isSelected = store.selectedTab == item.tab
        #if os(macOS)
            let row = Button { store.send(.tabSelected(item.tab)) } label: {
                macSidebarLabel(title: item.title, icon: item.icon, isSelected: isSelected)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        #else
            let row = Label {
                Text(item.title)
                    .type(.body1(isSelected ? .semibold : .regular), style: isSelected ? .primaryOnSurface : .secondary)
            } icon: {
                sidebarIcon(item.icon, color: isSelected ? Color.primaryDS : Color.secondaryDS)
            }
        #endif
        return row
            .tag(item.tab)
            .listRowBackground(sidebarSelectionBackground(isSelected: isSelected))
            .accessibilityLabel(item.title)
    }

    /// Translucent neutral selection pill: `primaryDS` at low opacity lightens the dark sidebar
    /// and darkens the light one, a soft capsule rather than the accent fill.
    @ViewBuilder
    private func sidebarSelectionBackground(isSelected: Bool) -> some View {
        if isSelected {
            Capsule(style: .continuous)
                .fill(Color.accent.opacity(Constants.sidebarSelectionOpacity))
                .padding(.vertical, .space2)
            #if os(macOS)
                .padding(.horizontal, Constants.macSidebarSelectionHorizontalInset)
            #endif
        } else {
            Color.clear
        }
    }

    private static var sidebarIconSize: CGFloat {
        #if os(macOS)
            Constants.macSidebarIconSize
        #else
            Constants.sidebarIconSize
        #endif
    }

    private func sidebarIcon(_ image: Image, color: Color) -> some View {
        image
            .resizable()
            .scaledToFit()
            .frame(width: Self.sidebarIconSize, height: Self.sidebarIconSize)
            .foregroundStyle(color)
    }

    /// Signed in identity at the top of the sidebar: avatar + name + email. Read only on iPad,
    /// where account actions stay in Settings; the Mac opens an account menu from it.
    private var sidebarProfile: some View {
        #if os(macOS)
            MacSidebarAccountMenu(
                store: store.scope(state: \.settings, action: \.settings),
                onChangePassword: {
                    store.send(.settings(.changePasswordButtonTapped))
                }
            ) {
                HStack(spacing: .space8) {
                    profileSummary
                    IconKit.chevronUpDown
                        .foregroundStyle(Color.secondaryDS)
                }
                .contentShape(Rectangle())
            }
        #else
            profileSummary
        #endif
    }

    private var profileSummary: some View {
        HStack(spacing: .space12) {
            AvatarView(displayName: store.settings.displayName, size: .size44)
            VStack(alignment: .leading, spacing: .space2) {
                Text(store.settings.displayName)
                    .type(.body2(.bold), style: .primaryOnSurface)
                    .lineLimit(1)
                if let email = store.settings.user.email {
                    Text(email)
                        .type(.body3(.regular), style: .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, .space4)
    }

    /// App identity footer pinned to the bottom of the sidebar: logo + marketing version. On iPad
    /// the interactive credits stay in the Settings detail, where the tip jar sheet is presented;
    /// the Mac adds the coffee link here and hosts the tip jar on its main window.
    private var sidebarFooter: some View {
        VStack(spacing: .space8) {
            IconKit.logo
                .resizable()
                .scaledToFit()
                .frame(width: Constants.sidebarFooterLogoSize, height: Constants.sidebarFooterLogoSize)
            Text(appVersionText)
                .type(.body3(.regular), style: .tertiary)
            #if os(macOS)
                // The Mac's Settings window has no credits block, so the tip jar starts here.
                Button {
                    store.send(.settings(.tipJarButtonTapped))
                } label: {
                    (Text(L10n.Settings.creditsLikeApp + " ").fontWeight(.regular)
                        + Text(L10n.Settings.creditsBuyCoffee).fontWeight(.bold).foregroundColor(.accent))
                        .type(.body3(.regular), style: .tertiary)
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(.plain)
            #endif
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, .space16)
    }

    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return L10n.Settings.appVersion(version, build)
            .replacingOccurrences(of: "(\(build))", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

#Preview {
    NavigationSplitView {
        MainTabSidebar(store: Store(initialState: MainTabFeature.State(
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
            user: User(id: "preview-user", username: "jdoe", email: "jane.doe@example.com", displayName: "Jane Doe")
        )) { MainTabFeature() } withDependencies: { $0.filesClient = .previewValue })
    } detail: {
        Color.clear
    }
}
