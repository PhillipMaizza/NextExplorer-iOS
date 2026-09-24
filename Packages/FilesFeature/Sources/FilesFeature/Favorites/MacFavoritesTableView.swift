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
        @FocusState private var isFocused: Bool

        var body: some View {
            Table(of: Favorite.self, selection: $selection) {
                TableColumn(L10n.Sort.name) { favorite in
                    HStack(spacing: .space8) {
                        MacTableFolderIcon(
                            image: FavoriteIcon.symbol(for: favorite.icon),
                            tint: FavoriteColor.resolve(favorite.color) ?? Color.accent,
                            isFilled: FavoriteIcon.isFilled(favorite.icon)
                        )
                        Text(favorite.displayName).lineLimit(1).truncationMode(.middle)
                        if store.offlineFavoriteIDs.contains(favorite.id) {
                            MacTableFolderIcon(image: IconKit.download, tint: Color.accent)
                                .accessibilityLabel(L10n.Offline.badgeAvailable)
                        }
                    }
                    .padding(.vertical, MacBrowseTableMetrics.rowVerticalPadding)
                }
                .width(min: MacBrowseTableMetrics.nameColumnMinWidth)
                TableColumn(L10n.FileInfo.rowLocation) { favorite in
                    Text(favorite.path)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(Color.secondaryDS)
                }
                .width(min: Metrics.locationColumnMinWidth)
            } rows: {
                ForEach(favorites) { favorite in
                    TableRow(favorite)
                        .draggable(favorite.id)
                        .dropDestination(for: String.self) { droppedIDs in
                            move(droppedIDs.first, onto: favorite.id)
                        }
                }
            }
            .contextMenu(forSelectionType: Favorite.ID.self) { ids in
                if ids.count == 1, let favorite = favorite(for: ids.first) {
                    FavoriteRowContextMenu(store: store, favorite: favorite)
                }
            } primaryAction: { ids in
                if ids.count == 1, let favorite = favorite(for: ids.first) {
                    store.send(.rowTapped(favorite))
                }
            }
            .scrollContentBackground(.hidden)
            .alternatingRowBackgrounds(.disabled)
            .focused($isFocused)
            .focusEffectDisabled()
            .onAppear { isFocused = true }
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

        /// Translated into the `IndexSet` and destination `onMove` reports, so the reducer handles both platforms alike.
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
            favorites: [
                Favorite(id: "1", path: "/Documents/Projects", label: "Projects", icon: "folder", color: nil, position: 0, createdAt: Date(), updatedAt: Date()),
                Favorite(id: "2", path: "/Photos/2026", label: nil, icon: "star", color: "blue", position: 1, createdAt: Date(), updatedAt: Date()),
            ]
        )
        .frame(width: 700, height: 300)
    }
#endif
