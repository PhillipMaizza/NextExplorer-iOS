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
    /// Mirrors `store.uploads.isActive` so list screens can reserve bottom inset for the bar.
    @Shared(.inMemory(UploadBarChrome.visibilityKey)) private var isUploadBarVisible = false
    /// The bar's real rendered height, measured below and read by list screens instead of a
    /// guessed constant so the clearance stays right under Dynamic Type.
    @Shared(.inMemory(UploadBarChrome.heightKey)) private var uploadBarHeight = UploadBarChrome.fallbackHeight

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
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                guard hasBecomeActiveBefore else {
                    hasBecomeActiveBefore = true
                    return
                }
                store.send(.appBecameActive)
            }
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
                tabIcon(store.selectedTab == .browse ? IconKit.tabBrowseFill : IconKit.tabBrowse)
                    .accessibilityLabel(L10n.Tab.browse)
            }

            Tab(value: MainTabFeature.Tab.favorites) {
                FavoritesView(store: store.scope(state: \.favorites, action: \.favorites))
            } label: {
                tabIcon(store.selectedTab == .favorites ? IconKit.tabFavoritesFill : IconKit.tabFavorites)
                    .accessibilityLabel(L10n.Tab.favorites)
            }

            Tab(value: MainTabFeature.Tab.shared) {
                SharedView(store: store.scope(state: \.shared, action: \.shared))
            } label: {
                tabIcon(store.selectedTab == .shared ? IconKit.tabShareFill : IconKit.tabShare)
                    .accessibilityLabel(L10n.Tab.shared)
            }

            Tab(value: MainTabFeature.Tab.downloads) {
                DownloadsView(store: store.scope(state: \.downloads, action: \.downloads))
            } label: {
                tabIcon(store.selectedTab == .downloads ? IconKit.tabDownloadsFill : IconKit.tabDownloads)
                    .accessibilityLabel(L10n.Tab.downloads)
            }

            Tab(value: MainTabFeature.Tab.settings) {
                SettingsView(store: store.scope(state: \.settings, action: \.settings))
            } label: {
                tabIcon(store.selectedTab == .settings ? IconKit.tabSettingsFill : IconKit.tabSettings)
                    .accessibilityLabel(L10n.Tab.settings)
            }
        }
        .tint(Color.accent)
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
