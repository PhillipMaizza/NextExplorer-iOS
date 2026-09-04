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
    @AppStorage(AppStorageKeys.showTabLabels) private var showTabLabels = true

    public init(store: StoreOf<MainTabFeature>) {
        self.store = store
    }

    public var body: some View {
        tabs
            .overlay(alignment: .bottom) {
                if store.uploads.isBarVisible {
                    uploadStatusBar
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .onAppear { setUploadBarHeight(proxy.size.height) }
                                    .onChange(of: proxy.size.height) { _, height in setUploadBarHeight(height) }
                            }
                        )
                        .padding(.horizontal, .space16)
                        .padding(.bottom, Constants.barBottomClearance + breadcrumbClearance)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: Constants.barAnimationDuration), value: store.uploads.isBarVisible)
            .animation(.easeInOut(duration: Constants.barAnimationDuration), value: store.uploads.isActive)
            .animation(.easeInOut(duration: Constants.barAnimationDuration), value: breadcrumbClearance)
            .onChange(of: store.uploads.isBarVisible) { _, visible in
                $isUploadBarVisible.withLock { $0 = visible }
            }
            .sheet(isPresented: Binding(
                get: { store.uploads.isSheetPresented },
                set: { store.send(.uploads(.sheetPresented($0))) }
            )) {
                UploadsView(store: store.scope(state: \.uploads, action: \.uploads))
            }
            .dsToast(Binding(
                get: { uploadToastMessage },
                set: { if $0 == nil { store.send(.dismissUploadToast) } }
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
            .task { await store.send(.observeConnectivity).finish() }
    }

    private func setUploadBarHeight(_ height: CGFloat) {
        guard height > 0, abs(height - uploadBarHeight) >= 1 else { return }
        $uploadBarHeight.withLock { $0 = height }
    }

    @ViewBuilder
    private var uploadStatusBar: some View {
        if store.uploads.isActive {
            UploadProgressBar(
                title: uploadBarTitle,
                progress: store.uploads.currentJob?.progress ?? 0,
                onTap: { store.send(.uploads(.barTapped)) },
                onCancelAll: { store.send(.uploads(.cancelAllTapped), animation: .default) }
            )
        } else {
            UploadFailedBar(
                count: store.uploads.failedCount,
                onRetry: { store.send(.uploads(.retryAllFailedTapped), animation: .default) },
                onDismiss: { store.send(.uploads(.clearFinishedTapped), animation: .default) },
                onTap: { store.send(.uploads(.barTapped)) }
            )
        }
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
                    smallIcon: store.selectedTab == .browse ? IconKit.tabBrowseFillSmall : IconKit.tabBrowseSmall
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
                    smallIcon: store.selectedTab == .favorites ? IconKit.tabFavoritesFillSmall : IconKit.tabFavoritesSmall
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
                    smallIcon: store.selectedTab == .shared ? IconKit.tabShareFillSmall : IconKit.tabShareSmall
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
                    smallIcon: store.selectedTab == .downloads ? IconKit.tabDownloadsFillSmall : IconKit.tabDownloadsSmall
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
                    smallIcon: store.selectedTab == .settings ? IconKit.tabSettingsFillSmall : IconKit.tabSettingsSmall
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
    private func tabLabel(_ title: String, icon: Image, smallIcon: Image) -> some View {
        if showTabLabels {
            Label {
                Text(title)
            } icon: {
                tabIcon(smallIcon)
            }
            .accessibilityLabel(title)
        } else {
            tabIcon(icon)
                .accessibilityLabel(title)
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

    private var uploadBarTitle: String {
        let uploads = store.uploads
        if uploads.remainingCount <= 1, let name = uploads.currentJob?.fileName {
            return L10n.Uploads.barTitleOne(name)
        }
        return L10n.Uploads.barTitleMany(uploads.remainingCount)
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
