import AppStorageKeys
import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI
#if os(macOS)
    import AppKit
#endif

private enum Constants {
    /// Clearance so the floating upload bar rides above the tab bar rather than replacing it
    /// (a bottom `safeAreaInset` / `tabViewBottomAccessory` hides the Liquid Glass tab bar).
    static let barBottomClearance: CGFloat = 68
    /// Extra lift when a breadcrumb bar is also on screen (its height + `.safeAreaInset`
    /// spacing) so the upload bar rides above it, not over it.
    static let breadcrumbClearance: CGFloat = BrowseBreadcrumbBarMetrics.height + .space8
    /// Lifts the "upload complete" toast clear of the tab bar.
    static let toastTabBarClearance: CGFloat = 56
    /// Coming back to the app refetches every open folder and checks offline pins. A Mac user
    /// switches apps all day, so there it waits this long since the last time.
    static let macActiveSyncInterval: TimeInterval = 30
}

public struct MainTabView: View {
    @Bindable var store: StoreOf<MainTabFeature>
    @Environment(\.scenePhase) private var scenePhase
    /// `.onChange(of: scenePhase)` doesn't fire for the *initial* value, but iOS commonly
    /// still transitions `.inactive` → `.active` once shortly after a cold launch, once this
    /// view has already mounted: that transition would otherwise fire `.appBecameActive` and
    /// stomp on whatever `onAppear` just loaded. This tracks past the first activation so only
    /// a genuine later background→active resume triggers a sync.
    @State private var hasBecomeActiveBefore = false
    @State private var lastActiveSync = Date.distantPast
    /// Tabs whose content has actually been selected at least once. A non Browse `Tab` builds
    /// its `NavigationStack` off screen while the launch splash still covers the window, and
    /// UIKit lays that nav bar out at the wrong size and never revisits it (large title stuck
    /// inline until a manual tab switch forces a relayout: the NXTIOS-0018 bug class). Gating
    /// each tab's body on first selection defers the first layout pass to when the tab is
    /// actually on screen.
    @State private var visitedTabs: Set<MainTabFeature.Tab> = [.browse]
    @State private var offlinePhase = OfflineDownloadProgress.Phase.idle
    /// Mirrors `store.uploads.isActive` so list screens can reserve bottom inset for the bar.
    @Shared(.inMemory(UploadBarChrome.visibilityKey)) private var isUploadBarVisible = false
    /// The bar's real rendered height, measured below and read by list screens instead of a
    /// guessed constant so the clearance stays right under Dynamic Type.
    @Shared(.inMemory(UploadBarChrome.heightKey)) private var uploadBarHeight = UploadBarChrome.fallbackHeight
    /// Settings → "Show Tab Labels": titles under each tab icon (with the smaller glyph set),
    /// or the full size icons on their own.
    @AppStorage(AppStorageKeys.showTabLabels) private var shouldShowTabLabels = false
    /// Regular width (iPad) renders a `NavigationSplitView` sidebar; compact (iPhone, iPad
    /// narrow multitasking) keeps the bottom tab bar. Gated on size class, never device idiom.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Keep the sidebar open beside the detail in both orientations so the account header and
    /// sections stay visible; the toolbar toggle still hides it on demand.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// Where the sidebar ends, so the path bar floating over the split view keeps to the detail
    /// column. The detail's own size is not reported again after a rotation; the sidebar's is.
    @State private var sidebarTrailingEdge: CGFloat = 0

    public init(store: StoreOf<MainTabFeature>) {
        self.store = store
    }

    public var body: some View {
        shell
        #if os(macOS)
            .modifier(MacMainWindowChrome(store: store))
        #endif
            .overlay(alignment: .bottom) {
                if shouldShowTransferBars {
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
                        .padding(
                            .bottom,
                            (horizontalSizeClass == .regular ? .space16 : Constants.barBottomClearance) +
                                breadcrumbClearance
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(DSMotion.stateFade, value: store.uploads.isBarVisible)
            .animation(DSMotion.stateFade, value: store.uploads.isActive)
            .animation(DSMotion.stateFade, value: store.downloadQueue.isBarVisible)
            .animation(DSMotion.stateFade, value: store.downloadQueue.isActive)
            .animation(DSMotion.stateFade, value: offlinePhase.shouldShowOfflineBar)
            .onOfflinePhaseChange(initial: true) { offlinePhase = $0 }
            .animation(DSMotion.stateFade, value: breadcrumbClearance)
            .onChange(of: shouldShowTransferBars) { _, visible in
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
                DownloadQueueView(store: store.scope(state: \.downloadQueue, action: \.downloadQueue))
            }
        #if os(iOS)
            .fileMover(
                isPresented: Binding(
                    get: { !store.pendingExportURLs.isEmpty },
                    set: { _ in }
                ),
                files: store.pendingExportURLs,
                onCompletion: { result in
                    if case .success = result {
                        store.send(.deviceExportFinished(didSave: true))
                    } else {
                        store.send(.deviceExportFinished(didSave: false))
                    }
                },
                onCancellation: { store.send(.deviceExportFinished(didSave: false)) }
            )
        #endif
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
                        #if os(macOS)
                            // A Mac save lands in Finder, where the action reveals it.
                            if let savedURL = store.lastSavedDownloadURL {
                                return .success(message, actionTitle: L10n.Browse.showInFinder) {
                                    NSWorkspace.shared.activateFileViewerSelecting([savedURL])
                                }
                            }
                        #endif
                        return .success(message)
                    }
                },
                set: {
                    if $0 == nil {
                        store.send(.dismissDownloadToast)
                    }
                }
            ), extraBottomInset: Constants.toastTabBarClearance)
            .featureToast(
                error: store.settings.hasAccountChangeFailed ? L10n.Settings.accountChangeFailed : nil,
                extraBottomInset: Constants.toastTabBarClearance
            )
            .onChange(of: store.selectedTab, initial: true) { _, tab in
                visitedTabs.insert(tab)
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                guard hasBecomeActiveBefore else {
                    hasBecomeActiveBefore = true
                    lastActiveSync = Date()
                    return
                }
                #if os(macOS)
                    guard Date().timeIntervalSince(lastActiveSync) >= Constants.macActiveSyncInterval else { return }
                #endif
                lastActiveSync = Date()
                store.send(.appBecameActive)
            }
            .task {
                // Switching accounts remounts this view via its `.id`, so this `.task` can fire
                // while the switch action is still reducing. Yield first so the send lands on the
                // next tick, never reentrantly during that action (TCA forbids reentrant sends).
                await Task.yield()
                // Files shared in before this shell mounted (cold launch, or while signed out).
                store.send(.sharedFilesArrived)
                await store.send(.observeConnectivity).finish()
            }
    }

    private func setUploadBarHeight(_ height: CGFloat) {
        guard height > 0, abs(height - uploadBarHeight) >= 1 else { return }
        $uploadBarHeight.withLock { $0 = height }
    }

    /// The floating transfer bars; the Mac shows a toolbar activity button instead.
    private var shouldShowTransferBars: Bool {
        #if os(macOS)
            false
        #else
            store.uploads.isBarVisible || store.downloadQueue.isBarVisible || offlinePhase.shouldShowOfflineBar
        #endif
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

    /// One `NavigationSplitView` PER tab rather than a single split view whose detail swaps
    /// between sections. Hosting a path bound `NavigationStack` (TCA `StackState`) in a split
    /// view detail and then replacing it with another section's stack traps in
    /// `NavigationColumnState.boundPathChange` (EXC_BREAKPOINT) on the switch. Each `switch`
    /// branch is a distinct `NavigationSplitView` type, so changing tab tears the whole split
    /// view down and builds the next one fresh: the detail's bound path is never rebound in
    /// place. The shared `MainTabSidebar` + `columnVisibility` keep the sidebar (and its show/hide
    /// toggle) identical across tabs; TCA store state lives outside the view tree and survives.
    /// The Mac too: one split view with only `.id` on the swapped detail still traps there.
    private var splitView: some View {
        #if os(macOS)
            split { MacTabDetail(store: store) }
        #else
            perTabSplitView
        #endif
    }

    @ViewBuilder
    private var perTabSplitView: some View {
        switch store.selectedTab {
        case .browse:
            split { BrowseTabView(store: store.scope(state: \.browse, action: \.browse)) }
        case .favorites:
            split { FavoritesView(store: store.scope(state: \.favorites, action: \.favorites)) }
        case .shared:
            split { SharedView(store: store.scope(state: \.shared, action: \.shared)) }
        case .downloads:
            split { OfflineTabView(
                store: store.scope(state: \.downloads, action: \.downloads),
                offlineStore: store.scope(state: \.offlineManage, action: \.offlineManage),
                favorites: store.favorites.favorites
            ) }
        case .settings: split { SettingsView(store: store.scope(state: \.settings, action: \.settings)) }
        case .trash: split { NavigationStack { TrashView(store: store.scope(state: \.trash, action: \.trash)) } }
        }
    }

    private func split(@ViewBuilder detail: () -> some View) -> some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            MainTabSidebar(store: store)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxX } action: {
                    sidebarTrailingEdge = $0
                }
        } detail: {
            detail()
                .environment(\.isSplitViewDetail, true)
            #if os(macOS)
                // Every tab's content and toolbar sit on the same surface, not only Browse's.
                .backgroundGradient()
            #endif
        }
        .overlay(alignment: .bottom) {
            SplitDetailBreadcrumb(store: store)
                .padding(.leading, columnVisibility == .detailOnly ? 0 : max(0, sidebarTrailingEdge))
        }
        .navigationSplitViewStyle(.balanced)
        .platformAccentTint()
        #if os(macOS)
            .modifier(MacSplitChrome(
                store: store,
                sidebarInset: columnVisibility == .detailOnly ? 0 : max(0, sidebarTrailingEdge)
            ))
        #endif
    }

    private var tabs: some View {
        TabView(selection: Binding(
            get: { store.phoneTab },
            set: { store.send(.tabSelected($0)) }
        )) {
            Tab(value: MainTabFeature.Tab.browse) {
                BrowseTabView(store: store.scope(state: \.browse, action: \.browse))
            } label: {
                MainTabBarLabel(
                    tab: .browse,
                    isSelected: store.selectedTab == .browse,
                    shouldShowTitle: shouldShowTabLabels
                )
            }

            Tab(value: MainTabFeature.Tab.favorites) {
                if visitedTabs.contains(.favorites) {
                    FavoritesView(store: store.scope(state: \.favorites, action: \.favorites))
                }
            } label: {
                MainTabBarLabel(
                    tab: .favorites,
                    isSelected: store.selectedTab == .favorites,
                    shouldShowTitle: shouldShowTabLabels
                )
            }

            Tab(value: MainTabFeature.Tab.shared) {
                if visitedTabs.contains(.shared) {
                    SharedView(store: store.scope(state: \.shared, action: \.shared))
                }
            } label: {
                MainTabBarLabel(
                    tab: .shared,
                    isSelected: store.selectedTab == .shared,
                    shouldShowTitle: shouldShowTabLabels
                )
            }

            Tab(value: MainTabFeature.Tab.downloads) {
                if visitedTabs.contains(.downloads) {
                    OfflineTabView(
                        store: store.scope(state: \.downloads, action: \.downloads),
                        offlineStore: store.scope(state: \.offlineManage, action: \.offlineManage),
                        favorites: store.favorites.favorites
                    )
                }
            } label: {
                MainTabBarLabel(
                    tab: .downloads,
                    isSelected: store.selectedTab == .downloads,
                    shouldShowTitle: shouldShowTabLabels
                )
                .accessibilityValue(store.hasUnseenOfflineFiles ? L10n.Offline.newFilesBadge : "")
            }
            // An empty badge is the tab bar's dot: new files were kept since Offline was last opened.
            .badge(store.hasUnseenOfflineFiles ? Text(verbatim: "") : nil)

            Tab(value: MainTabFeature.Tab.settings) {
                if visitedTabs.contains(.settings) {
                    SettingsView(store: store.scope(state: \.settings, action: \.settings))
                }
            } label: {
                MainTabBarLabel(
                    tab: .settings,
                    isSelected: store.selectedTab == .settings,
                    shouldShowTitle: shouldShowTabLabels
                )
            }
        }
        .tint(Color.accent)
        // The tab bar caches its item views; without a fresh identity when the preference flips,
        // toggling labels off leaves the old titled items on screen. Rebuild on the toggle.
        // `visitedTabs` (MainTabView @State) and the store bound selection both survive it.
        .id(shouldShowTabLabels)
    }

    /// Room for the split view's `SplitDetailBreadcrumb` under the upload bar (none on iPhone,
    /// which shows no path).
    private var breadcrumbClearance: CGFloat {
        #if os(iOS)
            guard horizontalSizeClass == .regular else { return 0 }
        #endif
        return store.splitBreadcrumbPath == nil ? 0 : Constants.breadcrumbClearance
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
                user: User(
                    id: "preview-user",
                    username: "jdoe",
                    email: "jane.doe@example.com",
                    displayName: "Jane Doe",
                    roles: []
                )
            )
        ) {
            MainTabFeature()
        } withDependencies: {
            $0.filesClient = .previewValue
        }
    )
}
