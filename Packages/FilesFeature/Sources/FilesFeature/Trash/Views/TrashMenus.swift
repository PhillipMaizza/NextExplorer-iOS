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
                Label { Text(L10n.Trash.restore) } icon: { IconKit.restore }
            }
            Button { store.send(.restoreToTapped([item])) } label: {
                Label { Text(L10n.Trash.restoreTo) } icon: { IconKit.restoreTo }
            }
            if item.openPath != nil {
                Button { store.send(.openLocationTapped(item)) } label: {
                    Label { Text(L10n.Trash.openLocation) } icon: { IconKit.folder }
                }
            }
            Divider()
            Button(role: .destructive) { store.send(.deletePermanentlyTapped([item])) } label: {
                Label { Text(L10n.Trash.deletePermanently) } icon: { IconKit.delete }
            }
        } else {
            // Its volume is gone: an administrator may drop the record; the server refuses anyone else.
            Button(role: .destructive) { store.send(.forgetTapped(item)) } label: {
                Label { Text(L10n.Trash.forget) } icon: { IconKit.delete }
            }
        }
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
                icon: IconKit.restore,
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
                icon: IconKit.restoreTo,
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
                    icon: IconKit.delete,
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
            icon: IconKit.delete,
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
