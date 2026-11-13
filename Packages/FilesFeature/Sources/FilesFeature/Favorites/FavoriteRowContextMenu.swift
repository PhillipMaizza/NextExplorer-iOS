import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// The `…` / long-press action menu for one favorite, shared by the Favorites list rows and
/// grid cells. Edit (rename/recolor), then remove-from-favorites.
struct FavoriteRowContextMenu: View {
    let store: StoreOf<FavoritesFeature>
    let favorite: Favorite

    var body: some View {
        Button {
            store.send(.editTapped(favorite))
        } label: {
            Label { Text(L10n.Favorites.actionEdit) } icon: { IconKit.rename }
        }
        .tint(.primaryDS)
        let isOffline = store.offlineFavoriteIDs.contains(favorite.id)
        let isPinned = store.offlinePinnedFavoriteIDs.contains(favorite.id)
        Button {
            store.send(.offlineToggleTapped(favorite))
        } label: {
            Label {
                Text(isPinned ? L10n.Browse.actionRemoveFromOffline : L10n.Browse.actionAvailableOffline)
            } icon: {
                IconKit.availableOffline
            }
        }
        .tint(.primaryDS)
        .disabled(isOffline && !isPinned)
        Button(role: .destructive) {
            store.send(.removeTapped(favorite))
        } label: {
            Label { Text(L10n.Favorites.actionRemoveFromFavorites) } icon: { IconKit.unfavorite }
        }
        .tint(.negative)
    }
}
