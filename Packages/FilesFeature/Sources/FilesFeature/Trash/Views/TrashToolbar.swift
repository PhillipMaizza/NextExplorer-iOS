import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// The trash list's toolbar, the one Browse uses: the menu with Select, Sort, the grid or list
/// switch and a red Empty Trash; while selecting, Select All, Cancel and the selection bar.
struct TrashToolbar: ToolbarContent {
    let store: StoreOf<TrashFeature>
    let isGridView: Bool
    let onSort: () -> Void
    let onToggleViewMode: () -> Void

    var body: some ToolbarContent {
        selectSortToolbar(
            isSelecting: store.isSelecting,
            isAllSelected: store.isAllSelected,
            isSelectAvailable: !store.items.isEmpty && !store.isBusy,
            isGridView: isGridView,
            onSelectModeToggled: { store.send(.selectModeToggled) },
            onSelectAllToggled: { store.send(.selectAllTapped) },
            onCancel: { store.send(.selectModeToggled) },
            onToggleViewMode: onToggleViewMode,
            extraMenuItems: {
                Divider()
                Button(role: .destructive) { store.send(.emptyTrashTapped) } label: {
                    Label { Text(L10n.Trash.emptyTrash) } icon: { IconKit.delete }
                }
                .tint(Color.negativeText)
                .disabled(store.items.isEmpty || store.isBusy)
            }
        ) {
            Button(action: onSort) {
                Label { Text(L10n.Common.sort) } icon: { IconKit.sort }
            }
        }
        if store.isSelecting {
            TrashSelectionToolbar(
                isDisabled: store.selectedIDs.isEmpty || store.isBusy,
                onRestore: { store.send(.restoreTapped(store.selectedItems)) },
                onRestoreTo: { store.send(.restoreToTapped(store.selectedItems)) },
                onDelete: { store.send(.deletePermanentlyTapped(store.selectedItems)) }
            )
        }
    }
}

#if os(iOS)
    #Preview("Toolbar") {
        NavigationStack {
            Color.backgroundPrimary
                .toolbar { TrashToolbar(
                    store: TrashPreviewData.trash(),
                    isGridView: false,
                    onSort: {},
                    onToggleViewMode: {}
                ) }
        }
    }

    #Preview("Toolbar, selecting, dark") {
        NavigationStack {
            Color.backgroundPrimary
                .toolbar {
                    TrashToolbar(
                        store: TrashPreviewData.trash {
                            $0.isSelecting = true
                            $0.selectedIDs = ["t1"]
                        },
                        isGridView: true,
                        onSort: {},
                        onToggleViewMode: {}
                    )
                }
        }
        .preferredColorScheme(.dark)
    }
#endif
