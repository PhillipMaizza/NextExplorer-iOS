import DesignSystem
import Localization
import SwiftUI

/// Items the user asked to take out of Available Offline, held until they confirm. Removing deletes
/// the copy on this device, so every surface asks first.
struct OfflineRemovalRequest: Equatable, Sendable {
    let paths: [String]
    let names: [String]

    var title: String {
        names.count == 1 ? L10n.Offline.removeItemTitle(names[0]) : L10n.Offline.removeItemsTitle(names.count)
    }
}

/// What the Available Offline button does for a selection: add what is not offline yet, or, when
/// everything already is, remove what the user pinned. `nil` (button disabled) for no selection or only
/// items that are offline through a parent folder.
enum OfflineBulkAction: Equatable {
    case add
    case remove

    static func resolve(selectedIDs: [String], offlineIDs: Set<String>, pinnedIDs: Set<String>) -> OfflineBulkAction? {
        guard !selectedIDs.isEmpty else { return nil }
        if selectedIDs.contains(where: { !offlineIDs.contains($0) }) {
            return .add
        }
        return selectedIDs.contains(where: pinnedIDs.contains) ? .remove : nil
    }

    var title: String {
        self == .remove ? L10n.Browse.actionRemoveFromOffline : L10n.Browse.actionAvailableOffline
    }

    var icon: Image {
        IconKit.availableOffline
    }
}

extension View {
    /// The confirmation every Available Offline removal shares. Both buttons drive the reducer, so the
    /// presentation binding never writes back.
    func offlineRemovalAlert(
        _ request: OfflineRemovalRequest?,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        dsAlert(isPresented: Binding(get: { request != nil }, set: { _ in })) {
            DSAlertSheet(
                icon: IconKit.availableOffline,
                title: request?.title ?? "",
                message: L10n.Offline.removeItemMessage,
                confirmTitle: L10n.Offline.removeConfirm,
                dismissTitle: L10n.Common.cancel,
                role: .destructive,
                closeAccessibilityLabel: L10n.Common.close,
                onConfirm: onConfirm,
                onDismiss: onCancel
            )
        }
    }
}
