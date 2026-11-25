#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import SwiftUI

    struct MacFavoritesInspector: ViewModifier {
        let store: StoreOf<FavoritesFeature>

        @State private var sharedLinks: [Share]?

        func body(content: Content) -> some View {
            HStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity)
                    .clipped()
                if let item = store.infoItem {
                    MacFileInspector(
                        item: item,
                        metadata: store.infoMetadata,
                        usage: store.infoUsage,
                        errorMessage: store.infoErrorMessage,
                        serverURL: store.serverURL,
                        isFavorite: store.infoFavorite != nil,
                        onToggleFavorite: {
                            guard let favorite = store.infoFavorite else { return }
                            store.send(.removeTapped(favorite))
                        },
                        shares: MacInspectorSharedLinks.links(sharedLinks, for: item),
                        onOpen: {
                            guard let favorite = store.infoFavorite else { return }
                            store.send(.rowTapped(favorite))
                        },
                        onRetry: {
                            guard let favorite = store.infoFavorite else { return }
                            store.send(.infoTapped(favorite))
                        },
                        shouldShowThumbnails: store.preferences.shouldShowThumbnails,
                        onClose: { store.send(.infoDismissed) },
                        more: { EmptyView() }
                    )
                    .macInspectorColumn()
                }
            }
            .animation(DSMotion.stateFade, value: store.infoItem != nil)
            .focusedSceneValue(
                \.closeMacInspector,
                store.infoItem != nil ? MacInspectorAction { store.send(.infoDismissed) } : nil
            )
            .focusedSceneValue(
                \.openMacInspector,
                store.infoItem != nil || store.tableSelection.count != 1
                    ? nil
                    : MacInspectorAction { store.send(.infoSelectionTapped) }
            )
            .modifier(MacInspectorSharedLinks(
                isOpen: store.infoItem != nil,
                serverURL: store.serverURL,
                links: $sharedLinks
            ))
        }
    }

    @MainActor
    private enum PreviewData {
        static let serverURL = URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/")

        static func store(phase: DataPhase, isOpen: Bool = true) -> StoreOf<FavoritesFeature> {
            var state = FavoritesFeature.State(serverURL: serverURL)
            state.favorites = IdentifiedArray(uniqueElements: MacFavoritePreviewData.favorites)
            state.phase = .loaded
            if isOpen, let favorite = MacFavoritePreviewData.favorites.first {
                state.infoItem = FileItem(
                    name: favorite.folderName,
                    path: (favorite.path as NSString).deletingLastPathComponent,
                    dateModified: .distantPast,
                    size: 0,
                    kind: FileItem.directoryKind
                )
                state.infoPhase = phase
                if phase == .loaded {
                    state.infoMetadata = FileMetadata(
                        path: favorite.path,
                        name: favorite.folderName,
                        kind: FileItem.directoryKind,
                        size: 0,
                        dateModified: .distantPast,
                        dateCreated: .distantPast
                    )
                }
            }
            return Store(initialState: state) { EmptyReducer() }
        }
    }

    #Preview("Loading") {
        MacFavoritesTableView(store: PreviewData.store(phase: .loading), favorites: MacFavoritePreviewData.favorites)
            .modifier(MacFavoritesInspector(store: PreviewData.store(phase: .loading)))
            .previewCanvas(.table)
    }

    #Preview("Loaded") {
        let store = PreviewData.store(phase: .loaded)
        MacFavoritesTableView(store: store, favorites: MacFavoritePreviewData.favorites)
            .modifier(MacFavoritesInspector(store: store))
            .previewCanvas(.table)
    }

    #Preview("Failed") {
        let store = PreviewData.store(phase: .failed("Couldn't load the info."))
        MacFavoritesTableView(store: store, favorites: MacFavoritePreviewData.favorites)
            .modifier(MacFavoritesInspector(store: store))
            .previewCanvas(.table)
    }

    #Preview("Closed") {
        let store = PreviewData.store(phase: .idle, isOpen: false)
        MacFavoritesTableView(store: store, favorites: MacFavoritePreviewData.favorites)
            .modifier(MacFavoritesInspector(store: store))
            .previewCanvas(.table)
    }
#endif
