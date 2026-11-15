import DesignSystem
import Localization
import SwiftUI

/// Items the user asked to take out of Available Offline, held until they confirm. Removing deletes
/// the copy on this device, so every surface asks first.
struct OfflineRemovalRequest: Equatable, Sendable {
    let paths: [String]
    let names: [String]
    /// Set when the picked items are everything left in the kept folder on screen: the folder itself
    /// comes off instead (`paths` names it), and the confirmation says so.
    var emptiedFolderName: String?

    var title: String {
        names.count == 1 ? L10n.Offline.removeItemTitle(names[0]) : L10n.Offline.removeItemsTitle(names.count)
    }

    var message: String {
        emptiedFolderName.map { L10n.Offline.removeEmptiesFolderMessage($0) } ?? L10n.Offline.removeItemMessage
    }
}

extension OfflineRemovalRequest {
    /// Taking `items` off the device: one the user pinned is unpinned, one kept only through a pinned
    /// folder is left out of it while the folder stays pinned. An item inside another picked one comes
    /// off with it, so it is not named twice. `nil` when none of them can come off.
    static func removing(
        _ items: [(path: String, name: String)],
        pinnedPaths: Set<String>,
        coveringRoot: (String) -> String?
    ) -> OfflineRemovalRequest? {
        let removable = items.filter { pinnedPaths.contains($0.path) || coveringRoot($0.path) != nil }
        let paths = Set(removable.map(\.path))
        var kept: [(path: String, name: String)] = []
        for item in removable where !kept.contains(where: { $0.path == item.path }) {
            guard !paths.contains(where: { item.path.hasPrefix($0 + "/") }) else { continue }
            kept.append(item)
        }
        return kept.isEmpty ? nil : OfflineRemovalRequest(paths: kept.map(\.path), names: kept.map(\.name))
    }
}

/// What the Available Offline button does for a selection: add what is not offline yet, or, when
/// everything already is, remove it (an item kept through a pinned folder comes off on its own).
/// `nil` (button disabled) for no selection.
enum OfflineBulkAction: Equatable {
    case add
    case remove

    static func resolve(selectedIDs: [String], offlineIDs: Set<String>) -> OfflineBulkAction? {
        guard !selectedIDs.isEmpty else { return nil }
        if selectedIDs.contains(where: { !offlineIDs.contains($0) }) {
            return .add
        }
        return .remove
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
                message: request?.message ?? L10n.Offline.removeItemMessage,
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
