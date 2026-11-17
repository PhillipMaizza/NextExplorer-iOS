import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// The trash list's toolbar, the one Browse uses: the menu with Select, Sort, the grid or list
/// switch and a red Empty Trash; while selecting, Select All, Cancel and the selection bar.
struct TrashToolbar: ToolbarContent {
    let store: StoreOf<TrashFeature>
    let onSort: () -> Void

    var body: some ToolbarContent {
        #if os(iOS)
            if !store.isSelecting, store.isEnabled, let days = store.retentionDays {
                ToolbarItem(placement: .topBarTrailing) {
                    TrashRetentionInfoButton(text: L10n.Trash.subtitle(days))
                }
                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
            }
        #endif
        selectSortToolbar(
            isSelecting: store.isSelecting,
            isAllSelected: store.isAllSelected,
            isSelectAvailable: !store.items.isEmpty && !store.isBusy,
            isGridView: false,
            isViewModeAvailable: false,
            onSelectModeToggled: { store.send(.selectModeToggled) },
            onSelectAllToggled: { store.send(.selectAllTapped) },
            onCancel: { store.send(.selectModeToggled) },
            onToggleViewMode: {},
            extraMenuItems: {
                Divider()
                Button(role: .destructive) { store.send(.emptyTrashTapped) } label: {
                    Label { Text(L10n.Trash.emptyTrash) } icon: { IconKit.delete }
                }
                .tint(.red)
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

/// The info button beside the menu: how long the trash keeps items, read in a small native menu.
private struct TrashRetentionInfoButton: View {
    let text: String

    var body: some View {
        Menu {
            Text(text)
        } label: {
            IconKit.info
                .foregroundStyle(Color.primaryDS)
        }
        .tint(Color.primaryDS)
        .accessibilityLabel(text)
    }
}

#Preview("Info button") {
    TrashRetentionInfoButton(text: L10n.Trash.subtitle(30))
        .padding(.space24)
}

#if os(iOS)
    #Preview("Toolbar") {
        NavigationStack {
            Color.backgroundPrimary
                .toolbar { TrashToolbar(
                    store: TrashPreviewData.trash(),
                    onSort: {}
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
                        onSort: {}
                    )
                }
        }
        .preferredColorScheme(.dark)
    }
#endif
