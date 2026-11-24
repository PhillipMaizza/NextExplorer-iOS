#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let locationColumnMinWidth: CGFloat = 200
    }

    /// Favorites as a Mac table, matching Browse's: name and location columns, double click to
    /// open, the favorite actions on right click, Delete to remove and drag to reorder. The
    /// selection is the table's own; there is no select mode on the Mac.
    struct MacFavoritesTableView: View {
        let store: StoreOf<FavoritesFeature>
        let favorites: [Favorite]

        @State private var selection: Set<Favorite.ID> = []
        @State private var sortOrder: [KeyPathComparator<Favorite>] = []
        @FocusState private var isFocused: Bool

        var body: some View {
            Table(of: Favorite.self, selection: $selection, sortOrder: $sortOrder) {
                TableColumn(L10n.Sort.name, value: \.displayName) { favorite in
                    HStack(spacing: .space8) {
                        MacFavoriteTile(favorite: favorite)
                        Text(favorite.displayName).lineLimit(1).truncationMode(.middle)
                        if store.offlineFavoriteIDs.contains(favorite.id) {
                            MacTableFolderIcon(
                                image: IconKit.availableOffline,
                                tint: Color.accent,
                                size: MacBrowseTableMetrics.badgeSize
                            )
                            .accessibilityLabel(L10n.Offline.badgeAvailable)
                        }
                    }
                    .macBoardTableCell()
                }
                .width(min: MacBrowseTableMetrics.nameColumnMinWidth)
                TableColumn(L10n.FileInfo.rowLocation, value: \.path) { favorite in
                    Text(MacInspectorLocation.trail(parent: (favorite.path as NSString).deletingLastPathComponent))
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(.secondary)
                }
                .width(min: Metrics.locationColumnMinWidth)
            } rows: {
                ForEach(sortOrder.isEmpty ? favorites : favorites.sorted(using: sortOrder)) { favorite in
                    // The app's own private drag type: a plain string would drop the id as text
                    // into other apps, and accept any text dragged in.
                    TableRow(favorite)
                        .draggable(ServerItemReference(
                            id: favorite.id,
                            origin: .current(serverURL: store.serverURL, scope: store.cacheScope)
                        ))
                        .dropDestination(for: ServerItemReference.self) { references in
                            guard sortOrder.isEmpty else { return }
                            let receiver = DragOrigin.current(serverURL: store.serverURL, scope: store.cacheScope)
                            move(references.first { $0.origin == receiver }?.id, onto: favorite.id)
                        }
                }
            }
            .contextMenu(forSelectionType: Favorite.ID.self) { ids in
                if ids.count == 1, let favorite = favorite(for: ids.first) {
                    FavoriteRowContextMenu(store: store, favorite: favorite)
                        .labelStyle(.titleAndIcon)
                }
            } primaryAction: { ids in
                if ids.count == 1, let favorite = favorite(for: ids.first) {
                    store.send(.rowTapped(favorite))
                }
            }
            .macBoardTable()
            // The table's scroll view otherwise draws its header material up under the pinned title.
            .clipped()
            .focused($isFocused)
            .focusEffectDisabled()
            .focusedWhenOnTop($isFocused)
            .onKeyPress(.return) {
                guard selection.count == 1, let favorite = favorite(for: selection.first) else { return .ignored }
                store.send(.rowTapped(favorite))
                return .handled
            }
            .onDeleteCommand(perform: removeSelection)
            .onChange(of: favorites.map(\.id)) { _, ids in
                selection.formIntersection(ids)
            }
        }

        private func favorite(for id: Favorite.ID?) -> Favorite? {
            favorites.first { $0.id == id }
        }

        /// One favorite goes straight away, as its menu item does; several go through the bulk
        /// remove confirmation.
        private func removeSelection() {
            if selection.count == 1, let favorite = favorite(for: selection.first) {
                store.send(.removeTapped(favorite))
            } else if selection.count > 1 {
                store.send(.deselectAllTapped)
                for id in selection {
                    store.send(.itemSelectionToggled(id))
                }
                store.send(.bulkRemoveTapped)
            }
        }

        /// Translated into the `IndexSet` and destination `onMove` reports, so the reducer handles both platforms
        /// alike.
        private func move(_ draggedID: String?, onto targetID: String) {
            let orderedIDs = favorites.map(\.id)
            guard store.canReorder,
                  let draggedID,
                  draggedID != targetID,
                  let source = orderedIDs.firstIndex(of: draggedID),
                  let target = orderedIDs.firstIndex(of: targetID)
            else { return }
            store.send(.favoritesMoved(IndexSet(integer: source), source < target ? target + 1 : target))
        }
    }

    #Preview("Favorites table") {
        MacFavoritesTableView(
            store: Store(
                initialState: FavoritesFeature.State(
                    serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/")
                )
            ) { FavoritesFeature() },
            favorites: MacFavoritePreviewData.favorites
        )
        .previewCanvas(.table)
    }
#endif
