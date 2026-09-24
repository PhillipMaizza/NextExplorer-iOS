import AppStorageKeys
import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

private enum Constants {
    static let barAnimationDuration: Double = 0.2
    /// Clearance so the floating upload bar rides above the tab bar rather than replacing it
    /// (a bottom `safeAreaInset` / `tabViewBottomAccessory` hides the Liquid Glass tab bar).
    static let barBottomClearance: CGFloat = 68
    /// Extra lift when a breadcrumb bar is also on screen (its height + `.safeAreaInset`
    /// spacing) so the upload bar rides above it, not over it.
    static let breadcrumbClearance: CGFloat = BrowseBreadcrumbBarMetrics.height + .space8
    /// Lifts the "upload complete" toast clear of the tab bar.
    static let toastTabBarClearance: CGFloat = 56
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

public struct MainTabView: View {
    @Bindable var store: StoreOf<MainTabFeature>
    @Environment(\.scenePhase) private var scenePhase
    /// `.onChange(of: scenePhase)` doesn't fire for the *initial* value, but iOS commonly
    /// still transitions `.inactive` → `.active` once shortly after a cold launch, once this
    /// view has already mounted — that transition would otherwise fire `.appBecameActive` and
    /// stomp on whatever `onAppear` just loaded. This tracks past the first activation so only
    /// a genuine later background→active resume triggers a sync.
    @State private var hasBecomeActiveBefore = false
    /// Tabs whose content has actually been selected at least once. A non-Browse `Tab` builds
    /// its `NavigationStack` off screen while the launch splash still covers the window, and
    /// UIKit lays that nav bar out at the wrong size and never revisits it (large title stuck
    /// inline until a manual tab switch forces a relayout — the NXTIOS-0018 bug class). Gating
    /// each tab's body on first selection defers the first layout pass to when the tab is
    /// actually on screen.
    @State private var visitedTabs: Set<MainTabFeature.Tab> = [.browse]
    /// Mirrors `store.uploads.isActive` so list screens can reserve bottom inset for the bar.
    @Shared(.inMemory(UploadBarChrome.visibilityKey)) private var isUploadBarVisible = false
    /// The bar's real rendered height, measured below and read by list screens instead of a
    /// guessed constant so the clearance stays right under Dynamic Type.
    @Shared(.inMemory(UploadBarChrome.heightKey)) private var uploadBarHeight = UploadBarChrome.fallbackHeight
    /// Settings → "Show Tab Labels": titles under each tab icon (with the smaller glyph set),
    /// or the full-size icons on their own.
    @AppStorage(AppStorageKeys.showTabLabels) private var showTabLabels = false
    /// Regular width (iPad) renders a `NavigationSplitView` sidebar; compact (iPhone, iPad
    /// narrow multitasking) keeps the bottom tab bar. Gated on size class, never device idiom.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Keep the sidebar open beside the detail in both orientations so the account header and
    /// sections stay visible; the toolbar toggle still hides it on demand.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    public init(store: StoreOf<MainTabFeature>) {
        self.store = store
    }

    #if os(macOS)
        /// The window (and tab) title: the folder on screen in Browse or a pushed Favorites
        /// folder, otherwise the section's name.
        private var macWindowTitle: String {
            switch store.selectedTab {
            case .browse: store.browse.path.last?.title ?? store.browse.root.title
            case .favorites: store.favorites.path.last?.title ?? L10n.Tab.favorites
            case .shared: L10n.Tab.shared
            case .downloads: L10n.Tab.downloads
            case .settings: L10n.Tab.settings
            }
        }
    #endif

    public var body: some View {
        shell
        #if os(macOS)
            .modifier(MacDockUploadStatus(remaining: store.uploads.remainingCount, progress: store.uploads.overallProgress))
            .windowTitle(macWindowTitle)
        #endif
            .overlay(alignment: .bottom) {
                if isAnyTransferBarVisible {
                    TransferStatusBars(store: store)
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .onAppear { setUploadBarHeight(proxy.size.height) }
                                    .onChange(of: proxy.size.height) { _, height in setUploadBarHeight(height) }
                            }
                        )
                        .padding(.horizontal, .space16)
                        // The bottom tab bar only exists on compact; on the iPad sidebar layout
                        // there's none to clear, so the bar rides on a normal bottom margin.
                        .padding(.bottom, (horizontalSizeClass == .regular ? .space16 : Constants.barBottomClearance) + breadcrumbClearance)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: Constants.barAnimationDuration), value: store.uploads.isBarVisible)
            .animation(.easeInOut(duration: Constants.barAnimationDuration), value: store.uploads.isActive)
            .animation(.easeInOut(duration: Constants.barAnimationDuration), value: store.downloadQueue.isBarVisible)
            .animation(.easeInOut(duration: Constants.barAnimationDuration), value: store.downloadQueue.isActive)
            .animation(.easeInOut(duration: Constants.barAnimationDuration), value: breadcrumbClearance)
            .onChange(of: isAnyTransferBarVisible) { _, visible in
                $isUploadBarVisible.withLock { $0 = visible }
            }
            .sheet(isPresented: Binding(
                get: { store.uploads.isSheetPresented },
                set: { store.send(.uploads(.sheetPresented($0))) }
            )) {
                UploadsView(store: store.scope(state: \.uploads, action: \.uploads))
            }
            .sheet(isPresented: Binding(
                get: { store.downloadQueue.isSheetPresented },
                set: { store.send(.downloadQueue(.sheetPresented($0))) }
            )) {
                DownloadQueueView(
                    store: store.scope(state: \.downloadQueue, action: \.downloadQueue),
                    onOpenDownloads: { store.send(.openDownloadsTab) }
                )
            }
            .dsToast(Binding(
                get: { uploadToastMessage },
                set: {
                    if $0 == nil {
                        store.send(.dismissUploadToast)
                    }
                }
            ), extraBottomInset: Constants.toastTabBarClearance)
            .dsToast(Binding(
                get: {
                    store.downloadToast.map { message in
                        .success(message, actionTitle: L10n.Browse.open) { store.send(.openDownloadsTab) }
                    }
                },
                set: {
                    if $0 == nil {
                        store.send(.dismissDownloadToast)
                    }
                }
            ), extraBottomInset: Constants.toastTabBarClearance)
            .hapticFeedback(.selection, trigger: store.selectedTab)
            .onChange(of: store.selectedTab, initial: true) { _, tab in
                visitedTabs.insert(tab)
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                guard hasBecomeActiveBefore else {
                    hasBecomeActiveBefore = true
                    return
                }
                store.send(.appBecameActive)
            }
            .task {
                // Switching accounts remounts this view via its `.id`, so this `.task` can fire
                // while the switch action is still reducing. Yield first so the send lands on the
                // next tick, never reentrantly during that action (TCA forbids reentrant sends).
                await Task.yield()
                await store.send(.observeConnectivity).finish()
            }
    }

    private func setUploadBarHeight(_ height: CGFloat) {
        guard height > 0, abs(height - uploadBarHeight) >= 1 else { return }
        $uploadBarHeight.withLock { $0 = height }
    }

    private var isAnyTransferBarVisible: Bool {
        store.uploads.isBarVisible || store.downloadQueue.isBarVisible
    }

    /// Regular width shows the sidebar split view; compact keeps the bottom tab bar.
    @ViewBuilder
    private var shell: some View {
        if horizontalSizeClass == .regular {
            splitView
        } else {
            tabs
        }
    }

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
        // Downloads section to show.
        .filter { $0.tab != .downloads }
        #endif
    }

    /// One `NavigationSplitView` PER tab rather than a single split view whose detail swaps
    /// between sections. Hosting a path-bound `NavigationStack` (TCA `StackState`) in a split
    /// view detail and then replacing it with another section's stack traps in
    /// `NavigationColumnState.boundPathChange` (EXC_BREAKPOINT) on the switch. Each `switch`
    /// branch is a distinct `NavigationSplitView` type, so changing tab tears the whole split
    /// view down and builds the next one fresh — the detail's bound path is never rebound in
    /// place. The shared `sidebar` + `columnVisibility` keep the sidebar (and its show/hide
    /// toggle) identical across tabs; TCA store state lives outside the view tree and survives.
    @ViewBuilder
    private var splitView: some View {
        switch store.selectedTab {
        case .browse:
            split { BrowseTabView(store: store.scope(state: \.browse, action: \.browse)) }
        case .favorites:
            split { FavoritesView(store: store.scope(state: \.favorites, action: \.favorites)) }
        case .shared:
            split { SharedView(store: store.scope(state: \.shared, action: \.shared)) }
        case .downloads:
            split { DownloadsView(store: store.scope(state: \.downloads, action: \.downloads)) }
        case .settings:
            split { SettingsView(store: store.scope(state: \.settings, action: \.settings)) }
        }
    }

    private func split(@ViewBuilder detail: () -> some View) -> some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detail()
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Color.accent)
    }

    private var sidebar: some View {
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
    @ViewBuilder
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
        }
    }

    private func sidebarRow(_ item: (tab: MainTabFeature.Tab, title: String, icon: Image)) -> some View {
        let isSelected = store.selectedTab == item.tab
        #if os(macOS)
            let row = Button { store.send(.tabSelected(item.tab)) } label: {
                HStack(spacing: Constants.macSidebarIconTitleSpacing) {
                    sidebarIcon(item.icon, color: isSelected ? Color.primaryDS : Color.secondaryDS)
                    Text(item.title)
                        .type(.body1(isSelected ? .semibold : .regular), style: isSelected ? .primaryOnSurface : .secondary)
                }
                .padding(.vertical, Constants.macSidebarRowVerticalPadding)
                .padding(.horizontal, Constants.macSidebarRowHorizontalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
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

    /// Signed-in identity at the top of the iPad sidebar: avatar + name + email. Read only here;
    /// account actions (change password, sign out) stay in the Settings section.
    private var sidebarProfile: some View {
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

    /// App identity footer pinned to the bottom of the iPad sidebar: logo + marketing version.
    /// The interactive credits ("made by" / buy a coffee) stay in the Settings detail, where
    /// the tip jar sheet is presented.
    private var sidebarFooter: some View {
        VStack(spacing: .space8) {
            IconKit.logo
                .resizable()
                .scaledToFit()
                .frame(width: Constants.sidebarFooterLogoSize, height: Constants.sidebarFooterLogoSize)
            Text(appVersionText)
                .type(.body3(.regular), style: .tertiary)
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

    private var tabs: some View {
        TabView(selection: Binding(
            get: { store.selectedTab },
            set: { store.send(.tabSelected($0)) }
        )) {
            Tab(value: MainTabFeature.Tab.browse) {
                BrowseTabView(store: store.scope(state: \.browse, action: \.browse))
            } label: {
                tabLabel(
                    L10n.Tab.browse,
                    icon: store.selectedTab == .browse ? IconKit.tabBrowseFill : IconKit.tabBrowse,
                    smallIcon: store.selectedTab == .browse ? IconKit.tabBrowseFillSmall : IconKit.tabBrowseSmall,
                    identifier: AccessibilityIdentifiers.Tab.browse
                )
            }

            Tab(value: MainTabFeature.Tab.favorites) {
                if visitedTabs.contains(.favorites) {
                    FavoritesView(store: store.scope(state: \.favorites, action: \.favorites))
                }
            } label: {
                tabLabel(
                    L10n.Tab.favorites,
                    icon: store.selectedTab == .favorites ? IconKit.tabFavoritesFill : IconKit.tabFavorites,
                    smallIcon: store.selectedTab == .favorites ? IconKit.tabFavoritesFillSmall : IconKit.tabFavoritesSmall,
                    identifier: AccessibilityIdentifiers.Tab.favorites
                )
            }

            Tab(value: MainTabFeature.Tab.shared) {
                if visitedTabs.contains(.shared) {
                    SharedView(store: store.scope(state: \.shared, action: \.shared))
                }
            } label: {
                tabLabel(
                    L10n.Tab.shared,
                    icon: store.selectedTab == .shared ? IconKit.tabShareFill : IconKit.tabShare,
                    smallIcon: store.selectedTab == .shared ? IconKit.tabShareFillSmall : IconKit.tabShareSmall,
                    identifier: AccessibilityIdentifiers.Tab.shared
                )
            }

            Tab(value: MainTabFeature.Tab.downloads) {
                if visitedTabs.contains(.downloads) {
                    DownloadsView(store: store.scope(state: \.downloads, action: \.downloads))
                }
            } label: {
                tabLabel(
                    L10n.Tab.downloads,
                    icon: store.selectedTab == .downloads ? IconKit.tabDownloadsFill : IconKit.tabDownloads,
                    smallIcon: store.selectedTab == .downloads ? IconKit.tabDownloadsFillSmall : IconKit.tabDownloadsSmall,
                    identifier: AccessibilityIdentifiers.Tab.downloads
                )
            }

            Tab(value: MainTabFeature.Tab.settings) {
                if visitedTabs.contains(.settings) {
                    SettingsView(store: store.scope(state: \.settings, action: \.settings))
                }
            } label: {
                tabLabel(
                    L10n.Tab.settings,
                    icon: store.selectedTab == .settings ? IconKit.tabSettingsFill : IconKit.tabSettings,
                    smallIcon: store.selectedTab == .settings ? IconKit.tabSettingsFillSmall : IconKit.tabSettingsSmall,
                    identifier: AccessibilityIdentifiers.Tab.settings
                )
            }
        }
        .tint(Color.accent)
        // The tab bar caches its item views; without a fresh identity when the preference flips,
        // toggling labels off leaves the old titled items on screen. Rebuild on the toggle.
        // `visitedTabs` (MainTabView @State) and the store-bound selection both survive it.
        .id(showTabLabels)
    }

    /// A tab bar item: title + smaller glyph when "Show Tab Labels" is on, the full-size icon
    /// on its own otherwise. The title carries the accessibility label in both modes.
    @ViewBuilder
    private func tabLabel(_ title: String, icon: Image, smallIcon: Image, identifier: String) -> some View {
        if showTabLabels {
            Label {
                Text(title)
            } icon: {
                tabIcon(smallIcon)
            }
            .accessibilityLabel(title)
            .accessibilityIdentifier(identifier)
        } else {
            tabIcon(icon)
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
        }
    }

    private func tabIcon(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFit()
    }

    /// Whether the current tab is showing a `BrowseBreadcrumbBar` right now — the upload bar
    /// has to sit above it. Mirrors `BrowseTabView` / `FavoritesView`'s own visibility rule.
    private var breadcrumbClearance: CGFloat {
        switch store.selectedTab {
        case .browse:
            let dir = store.browse.path.last?.directoryPath ?? store.browse.root.directoryPath
            let selecting = store.browse.path.last?.isSelecting ?? store.browse.root.isSelecting
            return (!dir.isEmpty && !selecting) ? Constants.breadcrumbClearance : 0
        case .favorites:
            let dir = store.favorites.path.last?.directoryPath ?? ""
            let selecting = store.favorites.path.last?.isSelecting ?? false
            return (!dir.isEmpty && !selecting) ? Constants.breadcrumbClearance : 0
        default:
            return 0
        }
    }

    private var uploadToastMessage: DSToastMessage? {
        guard let toast = store.uploadToast else { return nil }
        if let destination = toast.openDestination {
            return .success(toast.message, actionTitle: L10n.Browse.open) {
                store.send(.openUploadedLocation(destination))
            }
        }
        return .success(toast.message)
    }
}

#Preview {
    MainTabView(
        store: Store(
            initialState: MainTabFeature.State(
                serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
                user: User(id: "preview-user", username: "jdoe", email: "jane.doe@example.com", displayName: "Jane Doe", roles: [])
            )
        ) {
            MainTabFeature()
        } withDependencies: {
            $0.filesClient = .previewValue
        }
    )
}
