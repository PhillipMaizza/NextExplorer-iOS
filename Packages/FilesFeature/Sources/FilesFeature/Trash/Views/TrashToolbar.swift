import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// The trash list's toolbar: Select on its own beside a menu with Sort, the grid or list switch
/// and Empty Trash. While selecting, Select All and Cancel as in Browse, and the selection bar.
struct TrashToolbar: ToolbarContent {
    let store: StoreOf<TrashFeature>
    let isGridView: Bool
    let onSort: () -> Void
    let onToggleViewMode: () -> Void

    var body: some ToolbarContent {
        #if os(iOS)
            if store.isSelecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button { store.send(.selectAllTapped) } label: {
                        IconKit.selectAll
                    }
                    .buttonStyle(DSPressableButtonStyle())
                    .accessibilityLabelWithTooltip(store.isAllSelected
                        ? L10n.Select.deselectAll
                        : L10n.Select
                            .selectAll)
                }
                ToolbarItem(placement: .primaryAction) {
                    SelectModeCancelButton { store.send(.selectModeToggled) }
                }
                TrashSelectionToolbar(
                    isDisabled: store.selectedIDs.isEmpty || store.isBusy,
                    onRestore: { store.send(.restoreTapped(store.selectedItems)) },
                    onRestoreTo: { store.send(.restoreToTapped(store.selectedItems)) },
                    onDelete: { store.send(.deletePermanentlyTapped(store.selectedItems)) }
                )
            } else if !store.items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.send(.selectModeToggled) } label: {
                        Text(L10n.Common.select)
                            .foregroundStyle(Color.primaryDS)
                    }
                    .tint(Color.primaryDS)
                    .disabled(store.isBusy)
                }
                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    moreMenu
                }
            }
        #else
            // The Mac shows the trash as a table with its own toolbar (`MacTrashView`).
            ToolbarItem(placement: .automatic) { EmptyView() }
        #endif
    }

    #if os(iOS)
        private var moreMenu: some View {
            Menu {
                Button(action: onSort) {
                    Label { Text(L10n.Common.sort) } icon: { IconKit.sort }
                }
                Button(action: onToggleViewMode) {
                    Label {
                        Text(isGridView ? L10n.Select.listView : L10n.Select.gridView)
                    } icon: {
                        isGridView ? IconKit.listBullet : IconKit.squareGrid
                    }
                }
                Divider()
                Button(role: .destructive) { store.send(.emptyTrashTapped) } label: {
                    Label { Text(L10n.Trash.emptyTrash) } icon: { IconKit.delete }
                }
                .tint(Color.negativeText)
                .disabled(store.isBusy)
            } label: {
                IconKit.moreOptions
                    .foregroundStyle(Color.primaryDS)
            }
            .tint(Color.primaryDS)
            .accessibilityLabelWithTooltip(L10n.Common.more)
        }
    #endif
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
