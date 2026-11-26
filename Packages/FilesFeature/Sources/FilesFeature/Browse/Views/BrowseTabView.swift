import ComposableArchitecture
import DesignSystem
import FilesClient
import SwiftUI

struct BrowseTabView: View {
    @Bindable var store: StoreOf<BrowseTabFeature>

    /// The folder path bar is `SplitDetailBreadcrumb`, floating over the split view: an iPhone
    /// shows none.
    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            BrowseContentView(store: store.scope(state: \.root, action: \.root))
                .navigationDestination(item: $store.scope(state: \.trash, action: \.trash)) { trashStore in
                    TrashView(store: trashStore)
                        .hidesSystemBackOnMac()
                }
        } destination: { store in
            BrowseContentView(store: store)
                .hidesSystemBackOnMac()
        }
        .platformAccentTint()
        .instantPushOnMac(depth: store.path.count)
        #if os(macOS)
            .transformPreference(MacEmptyGuideKey.self) { guide in
                if !isRootVisible {
                    guide = nil
                }
            }
        #endif
    }

    #if os(macOS)
        private var isRootVisible: Bool {
            store.path.isEmpty && store.trash == nil
        }
    #endif
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
