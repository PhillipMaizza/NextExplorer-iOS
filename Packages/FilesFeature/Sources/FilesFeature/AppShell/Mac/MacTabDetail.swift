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
            case .trash:
                MacTrashView(store: store.scope(state: \.trash, action: \.trash))
            }
        }
    }

    /// What the Mac split view adds over every section: the search panel's opener, the offline bar
    /// beside the sidebar, the transfers button and the window's Upload, Refresh and Search.
    struct MacSplitChrome: ViewModifier {
        let store: StoreOf<MainTabFeature>
        /// Where the sidebar ends, so the offline bar spans only the content beside it.
        let sidebarInset: CGFloat
        @Binding var columnVisibility: NavigationSplitViewVisibility

        func body(content: Content) -> some View {
            content
                .toolbar {
                    if columnVisibility == .detailOnly {
                        MacNavigationToolbar(store: store, columnVisibility: $columnVisibility)
                    }
                }
                .environment(\.openSpotlight, OpenSpotlightAction { store.send(.spotlightOpened) })
                .modifier(MacOfflineStatusBar(store: store, leadingInset: sidebarInset))
                .toolbar {
                    // Uploads and downloads only: an offline run has its own bar along the window's bottom.
                    if store.uploads.isBarVisible || store.downloadQueue.isBarVisible {
                        ToolbarItem(id: "transfers", placement: .primaryAction) {
                            MacTransferActivityButton(store: store)
                        }
                    }
                }
                .macWindowToolbar()
        }
    }

    #Preview("Split chrome") {
        NavigationStack {
            Text(verbatim: "Section")
                .frame(width: 600, height: 300)
        }
        .modifier(MacSplitChrome(
            store: Store(initialState: MainTabFeature.State(
                serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
                user: User.preview
            )) { MainTabFeature() },
            sidebarInset: 0,
            columnVisibility: .constant(.all)
        ))
    }

    #Preview("Browse") {
        MacTabDetail(store: Store(initialState: MainTabFeature.State(
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
            user: User.preview
        )) { MainTabFeature() } withDependencies: {
            $0.filesClient = .previewValue
        })
        .frame(width: 700, height: 400)
    }
#endif
