import ComposableArchitecture
import CoreModels
import DesignSystem
import SwiftUI

/// Select mode's bottom bar: one menu holding every action for the picked items.
struct BrowseSelectionToolbar: ToolbarContent {
    let store: StoreOf<BrowseFeature>
    let onShareLink: (FileItem) -> Void

    var body: some ToolbarContent {
        if store.isSelecting {
            #if os(iOS)
                ToolbarItem(placement: .bottomBar) {
                    Spacer()
                }
            #endif
            // One menu holds every action, and only once something is picked.
            if store.hasSelectionOnScreen {
                ToolbarItem(placement: .selectionBar) {
                    SelectionActionsMenu(
                        availability: store.selectionAvailability,
                        onInfo: { store.send(.infoTapped($0)) },
                        onRename: { store.send(.renameTapped($0)) },
                        onShareLink: onShareLink,
                        onShareKept: { store.send(.keptShareTapped(store.selectedItems)) },
                        onCopy: { store.send(.bulkCopyTapped, animation: DSMotion.listDiff) },
                        onMove: { store.send(.bulkMoveTapped, animation: DSMotion.listDiff) },
                        onSave: { store.send(.bulkDownloadTapped) },
                        onOffline: { store.send(.bulkOfflineTapped) },
                        onFavorite: { store.send(.bulkFavoriteTapped) },
                        onDelete: { store.send(.bulkDeleteTapped) }
                    )
                }
            }
        }
    }
}

#Preview {
    var state = BrowseFeature.State.preview(items: browsePreviewItems)
    state.isSelecting = true
    state.selectedItemIDs = [browsePreviewItems[1].id]
    let store = Store(initialState: state) { BrowseFeature() }
    return NavigationStack {
        Text(verbatim: "")
            .toolbar { BrowseSelectionToolbar(store: store, onShareLink: { _ in }) }
    }
}
