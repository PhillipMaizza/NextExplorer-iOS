import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import SwiftUI

struct BrowseTabView: View {
    @Bindable var store: StoreOf<BrowseTabFeature>

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            BrowseContentView(store: store.scope(state: \.root, action: \.root))
                .navigationTitle(store.root.title)
        } destination: { store in
            BrowseContentView(store: store)
                .navigationTitle(store.title)
        }
        .tint(Color.accent)
    }
}

#Preview {
    BrowseTabView(
        store: Store(
            initialState: BrowseTabFeature.State(
                serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/")
            )
        ) {
            BrowseTabFeature()
        } withDependencies: {
            $0.filesClient = .previewValue
        }
    )
}
