import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// The `…` / long press action menu for one favorite, shared by the Favorites list rows and
/// grid cells. Edit (rename/recolor), then remove from favorites.
struct FavoriteRowContextMenu: View {
    let store: StoreOf<FavoritesFeature>
    let favorite: Favorite

    /// Showing the saved list with no network: only taking a kept folder off the device works.
    private var isOffline: Bool {
        store.dataSource != .live
    }

    var body: some View {
        if !isOffline {
            Section {
                Button {
                    store.send(.editTapped(favorite))
                } label: {
                    Label { Text(L10n.Favorites.actionEdit) } icon: { IconKit.rename }
                }
                .tint(.primaryDS)
            }
        }
        // Available Offline and Favorites, always their own group; taking the folder off either is red.
        Section {
            // A folder kept through a pinned parent removes that parent, after a confirmation naming it.
            let isKept = store.offlineFavoriteIDs.contains(favorite.id)
            if !isOffline || isKept {
                RemovableMenuButton(
                    title: isKept ? L10n.Browse.actionRemoveFromOffline : L10n.Browse.actionAvailableOffline,
                    icon: IconKit.availableOffline,
                    isRemoval: isKept
                ) {
                    store.send(.offlineToggleTapped(favorite))
                }
            }
            if !isOffline {
                Button(role: .destructive) {
                    store.send(.removeTapped(favorite))
                } label: {
                    Label { Text(L10n.Favorites.actionRemoveFromFavorites) } icon: { IconKit.unfavorite }
                }
                .tint(.negative)
            }
        }
    }
}
