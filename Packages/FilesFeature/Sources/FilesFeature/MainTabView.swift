import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import SwiftUI

public struct MainTabView: View {
    @Bindable var store: StoreOf<MainTabFeature>

    public init(store: StoreOf<MainTabFeature>) {
        self.store = store
    }

    public var body: some View {
        TabView(selection: Binding(
            get: { store.selectedTab },
            set: { store.send(.tabSelected($0)) }
        )) {
            BrowseTabView(store: store.scope(state: \.browse, action: \.browse))
                .tabItem { Label { Text("Browse") } icon: { IconKit.folder } }
                .tag(MainTabFeature.Tab.browse)

            FavoritesView(store: store.scope(state: \.favorites, action: \.favorites))
                .tabItem { Label { Text("Favorites") } icon: { IconKit.star } }
                .tag(MainTabFeature.Tab.favorites)

            SettingsView(store: store.scope(state: \.settings, action: \.settings))
                .tabItem { Label { Text("Settings") } icon: { IconKit.gearshape } }
                .tag(MainTabFeature.Tab.settings)
        }
        .tint(Color.accent)
        .hapticFeedback(.selection, trigger: store.selectedTab)
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
