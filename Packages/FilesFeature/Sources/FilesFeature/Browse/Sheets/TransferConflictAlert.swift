import CoreModels
import DesignSystem
import Localization
import SwiftUI

extension DSAlertSheet {
    /// Asks what to do when a copy or move lands on names already in the destination: replace them,
    /// keep both (the server renames the incoming ones), or cancel. Raised over the list or over the
    /// gallery, whichever started the transfer.
    static func transferConflict(
        _ conflict: BrowseFeature.TransferConflict?,
        onResolve: @escaping (BrowseFeature.TransferConflictChoice?) -> Void
    ) -> DSAlertSheet {
        DSAlertSheet(
            icon: IconKit.warning,
            title: L10n.Browse.transferConflictTitle,
            message: transferConflictMessage(conflict),
            confirmTitle: L10n.Browse.transferConflictReplace,
            dismissTitle: L10n.Common.cancel,
            neutralTitle: L10n.Browse.transferConflictKeepBoth,
            role: .destructive,
            closeAccessibilityLabel: L10n.Common.close,
            onConfirm: { onResolve(.replace) },
            onNeutral: { onResolve(.keepBoth) },
            onDismiss: { onResolve(nil) }
        )
    }

    private static func transferConflictMessage(_ conflict: BrowseFeature.TransferConflict?) -> String {
        guard let conflict else { return "" }
        return conflict.count == 1
            ? L10n.Browse.transferConflictMessageOne(conflict.firstName)
            : L10n.Browse.transferConflictMessageMany(conflict.count)
    }
}

private enum PreviewSample {
    static func conflict(_ names: [String]) -> BrowseFeature.TransferConflict {
        let items = names.map { FileItem(name: $0, path: "Docs", dateModified: .distantPast, size: 1_024, kind: "pdf") }
        return BrowseFeature.TransferConflict(
            retry: BrowseFeature.TransferRetry(
                items: items,
                destination: "Docs",
                operation: .move,
                shouldClearClipboard: false
            ),
            collidingItems: items
        )
    }
}

#Preview("One name clashes") {
    DSAlertSheet.transferConflict(PreviewSample.conflict(["report.pdf"])) { _ in }
}

#Preview("Several names clash") {
    DSAlertSheet.transferConflict(PreviewSample.conflict(["report.pdf", "notes.pdf", "plan.pdf"])) { _ in }
}
