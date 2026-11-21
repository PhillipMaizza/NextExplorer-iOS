import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import SwiftUI

#if os(macOS)
    extension MacRowDragDrop {
        /// Drag a row out (Finder, or onto a folder here) and let folder rows take drops.
        init(store: StoreOf<BrowseFeature>, item: FileItem) {
            self.init(
                item: item,
                serverURL: store.serverURL,
                scope: store.cacheScope,
                canDrag: !store.isSelecting,
                canDropHere: !store.isSelecting && (store.access?.canDelete ?? false),
                onDrop: { ids in store.send(.itemsDroppedOnFolder(ids: ids, folder: item)) }
            )
        }
    }
#endif

/// The tiles of a folder in grid mode.
struct BrowseGridCells<Menu: View>: View {
    let store: StoreOf<BrowseFeature>
    let items: IdentifiedArrayOf<FileItem>
    let source: BrowsePreviewSource
    let onTap: (FileItem) -> Void
    @ViewBuilder let menu: (FileItem) -> Menu

    var body: some View {
        ForEach(items) { item in
            Button {
                if store.isSelecting {
                    store.send(.itemSelectionToggled(item.id))
                } else {
                    onTap(item)
                }
            } label: {
                cell(for: item)
                    .dsGridTile(
                        isSelecting: store.isSelecting,
                        isSelected: store.selectedItemIDs.contains(item.id)
                    )
                    .dragSelectable(id: item.id)
                #if os(macOS)
                    .modifier(MacRowDragDrop(store: store, item: item))
                #else
                    .modifier(IOSBrowseItemDragDrop(store: store, item: item))
                #endif
            }
            .buttonStyle(DSPressableButtonStyle())
            .dsTapFlashSource(isEnabled: !store.isSelecting)
            .contextMenu {
                if !store.isSelecting {
                    menu(item)
                }
            } preview: {
                FileContextMenuPreview(
                    item: item,
                    serverURL: store.serverURL,
                    shouldShowThumbnails: store.preferences.shouldShowThumbnails
                )
            }
            // A tile has no swipe, so VoiceOver gets the row's swipe actions as its own.
            .accessibilityActions {
                BrowseQuickActionButtons(
                    actions: BrowseQuickAction.actions(for: item, store: store),
                    style: .accessibility
                )
            }
        }
    }

    private func cell(for item: FileItem) -> some View {
        GridCellView(
            item: item,
            isFavorite: store.favoritePaths.contains(item.id),
            serverURL: store.serverURL,
            shouldShowThumbnails: store.preferences.shouldShowThumbnails,
            folderSize: store.folderSizes[item.id],
            matchedSource: source.matched(item.id),
            isOpening: source.isOpening(item.id, in: store),
            isAvailableOffline: store.offlineItemIDs.contains(item.id)
        )
    }
}

/// The rows of a folder in list mode.
struct BrowseFolderRows<Menu: View>: View {
    let store: StoreOf<BrowseFeature>
    let source: BrowsePreviewSource
    let onTap: (FileItem) -> Void
    @ViewBuilder let menu: (FileItem) -> Menu

    var body: some View {
        // `store.displayedItems` filters + sorts on every read: bind it once here rather than
        // rederiving it per row (the separator checks below alone made it O(n^2 log n)).
        let items = store.displayedItems
        let firstItemID = items.first?.id
        let lastItemID = items.last?.id
        ForEach(items) { item in
            DSFlashingListRow {
                Button {
                    if store.isSelecting {
                        store.send(.itemSelectionToggled(item.id))
                    } else {
                        onTap(item)
                    }
                } label: {
                    cell(for: item)
                        .dsListSelection(
                            isSelecting: store.isSelecting,
                            isSelected: store.selectedItemIDs.contains(item.id)
                        )
                        .dragSelectable(id: item.id)
                    #if os(macOS)
                        // On the label, not the row chain: that chain is at the type checker's limit.
                        .modifier(MacRowDragDrop(store: store, item: item))
                    #else
                        // No row drag in the list: the lifted row left a dark edge; the grid still drags.
                        .modifier(IOSBrowseItemDragDrop(store: store, item: item, canDrag: false))
                    #endif
                }
                .buttonStyle(DSPressableButtonStyle())
                .accessibilityAddTraits(store.isSelecting && store.selectedItemIDs
                    .contains(item.id) ? [.isSelected] : [])
                .contextMenu {
                    if !store.isSelecting {
                        menu(item)
                    }
                } preview: {
                    FileContextMenuPreview(
                        item: item,
                        serverURL: store.serverURL,
                        shouldShowThumbnails: store.preferences.shouldShowThumbnails
                    )
                }
                .swipeActions(edge: .trailing) {
                    BrowseQuickActionButtons(actions: BrowseQuickAction.actions(for: item, store: store), style: .swipe)
                }
                .listRowSeparator(item.id == firstItemID ? .hidden : .visible, edges: .top)
                .listRowSeparator(item.id == lastItemID ? .hidden : .visible, edges: .bottom)
            }
        }
    }

    private func cell(for item: FileItem) -> some View {
        FileRowView(
            item: item,
            isFavorite: store.favoritePaths.contains(item.id),
            serverURL: store.serverURL,
            shouldShowThumbnails: store.preferences.shouldShowThumbnails,
            matchedSource: source.matched(item.id),
            isOpening: source.isOpening(item.id, in: store),
            isAvailableOffline: store.offlineItemIDs.contains(item.id),
            folderSize: store.folderSizes[item.id]
        )
    }
}
