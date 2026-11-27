import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// One trashed item's actions, for the iOS context menu and the Mac table alike.
struct TrashItemMenu: View {
    let item: TrashItem
    let store: StoreOf<TrashFeature>

    var body: some View {
        if item.isAvailable {
            Button { store.send(.restoreTapped([item])) } label: {
                Label { Text(L10n.Trash.restore) } icon: { MenuIcon.restore.image }
            }
            Button { store.send(.restoreToTapped([item])) } label: {
                Label { Text(L10n.Trash.restoreTo) } icon: { MenuIcon.restoreTo.image }
            }
            if item.openPath != nil {
                Button { store.send(.openLocationTapped(item)) } label: {
                    Label { Text(L10n.Trash.openLocation) } icon: { MenuIcon.openLocation.image }
                }
            }
            Divider()
            RemovableMenuButton(title: L10n.Trash.deletePermanently, icon: MenuIcon.delete.image, isRemoval: true) {
                store.send(.deletePermanentlyTapped([item]))
            }
        } else {
            // Its volume is gone: an administrator may drop the record; the server refuses anyone else.
            RemovableMenuButton(title: L10n.Trash.forget, icon: MenuIcon.delete.image, isRemoval: true) {
                store.send(.forgetTapped(item))
            }
        }
    }
}

@MainActor
extension BrowseQuickAction {
    /// A trashed item's swipe, drawn as Browse draws its own: delete for good in red, restore in the
    /// accent. Nothing while selecting, or for an item whose volume is gone.
    static func trashActions(for item: TrashItem, store: StoreOf<TrashFeature>) -> [BrowseQuickAction] {
        guard !store.isSelecting, item.isAvailable else { return [] }
        return [
            BrowseQuickAction(
                title: L10n.Trash.deletePermanently,
                icon: MenuIcon.delete.image,
                tint: .negative,
                isEnabled: !store.isBusy,
                perform: { store.send(.deletePermanentlyTapped([item])) }
            ),
            BrowseQuickAction(
                title: L10n.Trash.restore,
                icon: MenuIcon.restore.image,
                tint: .accent,
                isEnabled: !store.isBusy,
                perform: { store.send(.restoreTapped([item])) }
            ),
        ]
    }
}

/// The select mode bar: restore in place, restore into a folder, delete for good.
struct TrashSelectionToolbar: ToolbarContent {
    let isDisabled: Bool
    let onRestore: () -> Void
    let onRestoreTo: () -> Void
    let onDelete: (() -> Void)?

    var body: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            SelectionToolbarButton(
                icon: MenuIcon.restore.image,
                accessibilityLabel: L10n.Trash.restore,
                isDisabled: isDisabled,
                action: onRestore
            )
        }
        ToolbarItem(placement: .bottomBar) {
            Spacer()
        }
        ToolbarItem(placement: .bottomBar) {
            SelectionToolbarButton(
                icon: MenuIcon.restoreTo.image,
                accessibilityLabel: L10n.Trash.restoreTo,
                isDisabled: isDisabled,
                action: onRestoreTo
            )
        }
        if let onDelete {
            ToolbarItem(placement: .bottomBar) {
                Spacer()
            }
            ToolbarItem(placement: .bottomBar) {
                SelectionToolbarButton(
                    icon: MenuIcon.delete.image,
                    role: .destructive,
                    tint: .negative,
                    accessibilityLabel: L10n.Trash.deletePermanently,
                    isDisabled: isDisabled,
                    action: onDelete
                )
            }
        }
    }
}

/// The confirmations of Delete Permanently, Forget and Empty Trash.
@MainActor
enum TrashConfirmation {
    static func alert(
        _ confirmation: TrashFeature.Confirmation?,
        isRunning: Bool,
        onConfirm: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> DSAlertSheet {
        let isEmpty = confirmation == .empty
        let count: Int = if case let .purge(ids, _) = confirmation {
            ids.count
        } else {
            0
        }
        return DSAlertSheet(
            icon: .delete,
            title: isEmpty ? L10n.Trash.confirmEmptyTitle : L10n.Trash.confirmDeleteTitle,
            message: isEmpty ? L10n.Trash.confirmEmptyMessage : L10n.Trash.confirmDeleteMessage(count),
            confirmTitle: isEmpty ? L10n.Trash.emptyTrash : L10n.Trash.deletePermanently,
            dismissTitle: L10n.Common.cancel,
            role: .destructive,
            isConfirmLoading: isRunning,
            closeAccessibilityLabel: L10n.Common.close,
            onConfirm: onConfirm,
            onDismiss: onDismiss
        )
    }
}

#Preview("Item menu") {
    List {
        Text(TrashPreviewData.items[0].name)
            .contextMenu { TrashItemMenu(item: TrashPreviewData.items[0], store: TrashPreviewData.trash()) }
        Text(TrashPreviewData.items[2].name)
            .contextMenu { TrashItemMenu(item: TrashPreviewData.items[2], store: TrashPreviewData.trash()) }
    }
}

#if os(iOS)
    #Preview("Selection bar") {
        NavigationStack {
            Color.backgroundPrimary
                .toolbar {
                    TrashSelectionToolbar(isDisabled: false, onRestore: {}, onRestoreTo: {}, onDelete: {})
                }
        }
    }

    #Preview("Selection bar, nothing picked") {
        NavigationStack {
            Color.backgroundPrimary
                .toolbar {
                    TrashSelectionToolbar(isDisabled: true, onRestore: {}, onRestoreTo: {}, onDelete: nil)
                }
        }
    }
#endif

#Preview("Delete confirmation") {
    Color.clear.sheet(isPresented: .constant(true)) {
        TrashConfirmation.alert(.purge(ids: ["a", "b"], forget: false), isRunning: false, onConfirm: {}, onDismiss: {})
    }
}

#Preview("Empty Trash running") {
    Color.clear.sheet(isPresented: .constant(true)) {
        TrashConfirmation.alert(.empty, isRunning: true, onConfirm: {}, onDismiss: {})
    }
}
