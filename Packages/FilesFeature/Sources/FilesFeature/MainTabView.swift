import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

public struct MainTabView: View {
    @Bindable var store: StoreOf<MainTabFeature>
    @Environment(\.scenePhase) private var scenePhase
    /// `.onChange(of: scenePhase)` doesn't fire for the *initial* value, but iOS commonly
    /// still transitions `.inactive` → `.active` once shortly after a cold launch, once this
    /// view has already mounted — that transition would otherwise fire `.appBecameActive` and
    /// stomp on whatever `onAppear` just loaded. This tracks past the first activation so only
    /// a genuine later background→active resume triggers a sync.
    @State private var hasBecomeActiveBefore = false

    public init(store: StoreOf<MainTabFeature>) {
        self.store = store
    }

    public var body: some View {
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

    private func tabIcon(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFit()
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
