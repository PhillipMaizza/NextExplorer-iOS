import ComposableArchitecture
import SwiftUI

/// Browse's list or grid swept by a finger in select mode: the shown items, in their shown order,
/// picked by the slide.
struct BrowseDragToSelect: ViewModifier {
    let store: StoreOf<BrowseFeature>

    func body(content: Content) -> some View {
        content.dragToSelect(
            isEnabled: store.isSelecting && !store.isSearching,
            selection: store.selectedItemIDs,
            order: { store.displayedItems.map(\.id) },
            onChange: { store.send(.selectionSwept($0)) }
        )
    }
}
