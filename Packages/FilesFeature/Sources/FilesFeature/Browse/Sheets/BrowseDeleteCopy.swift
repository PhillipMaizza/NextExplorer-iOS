import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

/// The single, bulk and preview delete confirmations, and the prompt about items the trash refused.
/// One builder, so every surface says the same thing about where the items go.
@MainActor
enum BrowseDeleteCopy {
    static func title(_ store: StoreOf<BrowseFeature>) -> String {
        guard let item = store.deleteConfirmationItem else { return L10n.Browse.deleteConfirmTitle }
        return L10n.Browse.deleteConfirmOne(item.name)
    }

    static func bulkTitle(_ store: StoreOf<BrowseFeature>) -> String {
        let selected = store.items.filter { store.selectedItemIDs.contains($0.id) }
        if selected.count == 1, let item = selected.first {
            return L10n.Browse.deleteConfirmOne(item.name)
        }
        return L10n.Browse.deleteConfirmMany(store.selectedItemIDs.count)
    }

    /// Whether the confirmation can show. The Mac's native alert keeps the buttons it opened with,
    /// so there it waits for the check that decides between Move to Trash and Delete; the iOS sheet
    /// follows the check as it lands.
    static func isReady(_ check: BrowseFeature.DeleteImpactCheck) -> Bool {
        #if os(macOS)
            check != .checking
        #else
            true
        #endif
    }

    /// The confirmation. Where the trash will take anything, the main button moves to the trash and
    /// a second one deletes for good; otherwise one button deletes, as before the trash.
    static func alert(
        title: String,
        check: BrowseFeature.DeleteImpactCheck,
        onConfirm: @escaping () -> Void,
        onDeletePermanently: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> DSAlertSheet {
        let movesToTrash = impact(check)?.movesAnyToTrash ?? false
        return DSAlertSheet(
            icon: IconKit.delete,
            title: title,
            message: message(check),
            confirmTitle: movesToTrash ? L10n.Trash.moveToTrash : L10n.Common.delete,
            dismissTitle: L10n.Common.cancel,
            neutralTitle: movesToTrash ? L10n.Trash.deletePermanently : nil,
            role: .destructive,
            closeAccessibilityLabel: L10n.Common.close,
            onConfirm: onConfirm,
            onNeutral: movesToTrash ? onDeletePermanently : nil,
            onDismiss: onDismiss
        )
    }

    /// Where the items go, why some cannot go to the trash, and what happens to their share links.
    /// A check still running or failed says what deleting for good says: the safe assumption.
    static func message(_ check: BrowseFeature.DeleteImpactCheck) -> String {
        var lines: [String] = []
        let impact = impact(check)
        if let plan = impact?.trash, plan.trashCount > 0 {
            lines.append(plan.retentionDays.map { L10n.Trash.deleteMessage($0) } ?? L10n.Trash.deleteMessageGeneric)
            if plan.permanentCount > 0 {
                lines.append(L10n.Trash.deleteSomePermanent(plan.permanentCount))
                lines += plan.permanentReasons.map(\.message)
            }
        } else {
            lines.append(L10n.Browse.deleteMessage)
            let reasons = impact?.trash?.permanentReasons.filter { $0 != .disabled } ?? []
            lines += reasons.map(\.message)
        }
        if let shareLine = shareLine(check) {
            lines.append(shareLine)
        }
        return lines.joined(separator: "\n\n")
    }

    /// The prompt after a delete that the trash refused for some items, which are still on disk.
    static func keptAlert(
        _ kept: [BrowseFeature.KeptDelete],
        onDeletePermanently: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> DSAlertSheet {
        DSAlertSheet(
            icon: IconKit.warning,
            title: L10n.Trash.keptTitle,
            message: kept.map(keptLine).joined(separator: "\n"),
            confirmTitle: L10n.Trash.deletePermanently,
            dismissTitle: L10n.Common.cancel,
            role: .destructive,
            closeAccessibilityLabel: L10n.Common.close,
            onConfirm: onDeletePermanently,
            onDismiss: onDismiss
        )
    }

    private static func impact(_ check: BrowseFeature.DeleteImpactCheck) -> DeleteImpact? {
        guard case let .loaded(impact) = check else { return nil }
        return impact
    }

    private static func shareLine(_ check: BrowseFeature.DeleteImpactCheck) -> String? {
        switch check {
        case let .loaded(impact) where impact.shareCount > 0 && impact.movesAnyToTrash:
            L10n.Trash.deleteLinkedShares(impact.shareCount)
        case let .loaded(impact) where impact.shareCount == 1:
            L10n.Browse.deleteLinkedSharesOne
        case let .loaded(impact) where impact.shareCount > 1:
            L10n.Browse.deleteLinkedSharesMany(impact.shareCount)
        case .unavailable:
            L10n.Browse.deleteLinkedSharesUnavailable
        case .idle, .checking, .loaded:
            nil
        }
    }

    private static func keptLine(_ kept: BrowseFeature.KeptDelete) -> String {
        if kept.reason == .tooLarge, let size = kept.size, let budget = kept.budgetBytes {
            return L10n.Trash.keptTooLarge(kept.item.name, FileSizeFormat.string(size), FileSizeFormat.string(budget))
        }
        return L10n.Trash.keptReason(kept.item.name, (kept.reason ?? .unknown).message)
    }
}

extension TrashRefusal {
    /// Why an item cannot go to the trash, as one sentence.
    var message: String {
        switch self {
        case .disabled: L10n.Trash.reasonDisabled
        case .otherDevice: L10n.Trash.reasonOtherDevice
        case .tooLarge: L10n.Trash.reasonTooLarge
        case .zoneRoot: L10n.Trash.reasonZoneRoot
        case .zoneUnwritable: L10n.Trash.reasonZoneUnwritable
        case .noZone: L10n.Trash.reasonNoZone
        case .unknown: L10n.Trash.reasonUnknown
        }
    }
}
