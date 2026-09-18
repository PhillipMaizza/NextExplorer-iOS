import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// One favorite in the Favorites list, built on the shared `SelectableListRow` shell: tap toggles
/// selection while selecting, otherwise opens the folder; edit + remove hang off the swipes and
/// the shared context menu.
struct FavoriteListRow: View {
    let store: StoreOf<FavoritesFeature>
    let favorite: Favorite
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        SelectableListRow(
            isSelecting: store.isSelecting,
            isSelected: store.selectedFavoriteIDs.contains(favorite.id),
            isFirst: isFirst,
            isLast: isLast,
            onTap: handleTap
        ) {
            FileRowView(
                name: favorite.displayName,
                isDirectory: true,
                customIcon: FavoriteIcon.symbol(for: favorite.icon),
                customIconTint: FavoriteColor.resolve(favorite.color),
                customIconFilled: FavoriteIcon.isFilled(favorite.icon)
            )
        } leadingSwipe: {
            if !store.isSelecting {
                Button {
                    store.send(.editTapped(favorite))
                } label: {
                    IconKit.rename
                }
                .tint(.accent)
                .accessibilityLabel(L10n.Favorites.actionEdit)
            }
        } trailingSwipe: {
            if !store.isSelecting {
                // Unfavoriting doesn't touch the folder itself, so the swipe reads in
                // accent rather than destructive red.
                Button {
                    store.send(.removeTapped(favorite))
                } label: {
                    IconKit.unfavorite
                }
                .tint(.accent)
                .accessibilityLabel(L10n.Favorites.actionRemoveFromFavorites)
            }
        } contextMenu: {
            if !store.isSelecting {
                FavoriteRowContextMenu(store: store, favorite: favorite)
            }
        }
    }

    private func handleTap() {
        if store.isSelecting {
            store.send(.itemSelectionToggled(favorite.id))
        } else {
            store.send(.rowTapped(favorite))
        }
    }
}

/// One favorite as a grid tile: the same behavior as `FavoriteListRow` on the shared
/// `SelectableGridCell` shell.
struct FavoriteGridCell: View {
    let store: StoreOf<FavoritesFeature>
    let favorite: Favorite

    var body: some View {
        SelectableGridCell(
            isSelecting: store.isSelecting,
            isSelected: store.selectedFavoriteIDs.contains(favorite.id),
            onTap: handleTap
        ) {
            GridCellView(
                name: favorite.displayName,
                isDirectory: true,
                customIcon: FavoriteIcon.symbol(for: favorite.icon),
                customIconTint: FavoriteColor.resolve(favorite.color),
                customIconFilled: FavoriteIcon.isFilled(favorite.icon)
            )
        } contextMenu: {
            if !store.isSelecting {
                FavoriteRowContextMenu(store: store, favorite: favorite)
            }
        }
    }

    private func handleTap() {
        if store.isSelecting {
            store.send(.itemSelectionToggled(favorite.id))
        } else {
            store.send(.rowTapped(favorite))
        }
    }
}

private extension Favorite {
    static var preview: Favorite {
        Favorite(
            id: "preview-projects",
            path: "/Documents/Projects",
            label: "Projects",
            icon: "folder",
            color: nil,
            position: 0,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

#Preview("List row") {
    let store = Store(
        initialState: FavoritesFeature.State(
            serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/")
        )
    ) { FavoritesFeature() }
    return List {
        FavoriteListRow(store: store, favorite: .preview, isFirst: true, isLast: false)
        FavoriteListRow(store: store, favorite: .preview, isFirst: false, isLast: true)
    }
    .listStyle(.insetGrouped)
}

#Preview("Grid cell") {
    let store = Store(
        initialState: FavoritesFeature.State(
            serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/")
        )
    ) { FavoritesFeature() }
    return FavoriteGridCell(store: store, favorite: .preview)
        .frame(width: 120)
        .padding()
}
