#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import SwiftUI

    /// The Mac split view's detail: the selected section. One split view whose detail swaps by
    /// section, so the sidebar and its toggle stay put.
    struct MacTabDetail: View {
        let store: StoreOf<MainTabFeature>

        var body: some View {
            switch store.selectedTab {
            case .browse:
                BrowseTabView(store: store.scope(state: \.browse, action: \.browse))
            case .favorites:
                FavoritesView(store: store.scope(state: \.favorites, action: \.favorites))
            case .shared:
                SharedView(store: store.scope(state: \.shared, action: \.shared))
            case .downloads:
                OfflineTabView(
                    store: store.scope(state: \.downloads, action: \.downloads),
                    offlineStore: store.scope(state: \.offlineManage, action: \.offlineManage),
                    favorites: store.favorites.favorites
                )
            case .settings:
                SettingsView(store: store.scope(state: \.settings, action: \.settings))
            }
        }
    }

    #Preview("Browse") {
        MacTabDetail(store: Store(initialState: MainTabFeature.State(
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
            user: User(id: "preview-user", username: "jdoe", email: "jane.doe@example.com", displayName: "Jane Doe")
        )) { MainTabFeature() } withDependencies: {
            $0.filesClient = .previewValue
        })
        .frame(width: 700, height: 400)
    }
#endif
