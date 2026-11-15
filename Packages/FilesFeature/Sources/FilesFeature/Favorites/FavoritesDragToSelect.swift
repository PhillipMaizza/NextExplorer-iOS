import ComposableArchitecture
import SwiftUI

/// The Favorites list or grid swept by a finger in select mode, in the order it shows them.
struct FavoritesDragToSelect: ViewModifier {
    let store: StoreOf<FavoritesFeature>

    func body(content: Content) -> some View {
        content.dragToSelect(
            isEnabled: store.isSelecting,
            selection: store.selectedFavoriteIDs,
            order: { store.displayedFavorites.map(\.id) },
            onChange: { store.send(.selectionSwept($0)) }
        )
    }
}
