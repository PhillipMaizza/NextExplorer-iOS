import DesignSystem
import Localization
import SwiftUI

/// The Offline tab's select mode bar. Pinned items can only leave the device's offline set, so they get
/// Remove from Offline; Share and Delete act on the files saved earlier.
struct OfflineSelectionToolbar: ToolbarContent {
    /// The picked pinned items, in the order the tab shows them, so the confirmation lists them alike.
    let selectedPinnedPaths: [String]
    let selectedDownloadURLs: [URL]
    let onRemoveFromOffline: ([String]) -> Void
    let onDelete: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            Spacer()
        }
        ToolbarItem(placement: .bottomBar) {
            SelectionToolbarButton(
                icon: OfflineBulkAction.remove.icon,
                role: .destructive,
                tint: .negative,
                accessibilityLabel: OfflineBulkAction.remove.title,
                isDisabled: selectedPinnedPaths.isEmpty
            ) {
                onRemoveFromOffline(selectedPinnedPaths)
            }
        }
        ToolbarItem(placement: .bottomBar) {
            ShareLink(items: selectedDownloadURLs) {
                IconKit.share
            }
            .accessibilityLabel(L10n.Common.share)
            .disabled(selectedDownloadURLs.isEmpty)
        }
        ToolbarItem(placement: .bottomBar) {
            SelectionToolbarButton(
                icon: IconKit.delete,
                role: .destructive,
                tint: .negative,
                accessibilityLabel: L10n.Common.delete,
                isDisabled: selectedDownloadURLs.isEmpty
            ) {
                onDelete()
            }
        }
    }
}

#if os(iOS)
    #Preview("Pinned and saved files picked") {
        NavigationStack {
            Color.backgroundPrimary
                .toolbar {
                    OfflineSelectionToolbar(
                        selectedPinnedPaths: ["Photos/trip.jpg"],
                        selectedDownloadURLs: [URL(fileURLWithPath: "/tmp/report.pdf")],
                        onRemoveFromOffline: { _ in },
                        onDelete: {}
                    )
                }
        }
    }

    #Preview("Only pinned items picked") {
        NavigationStack {
            Color.backgroundPrimary
                .toolbar {
                    OfflineSelectionToolbar(
                        selectedPinnedPaths: ["Documents"],
                        selectedDownloadURLs: [],
                        onRemoveFromOffline: { _ in },
                        onDelete: {}
                    )
                }
        }
    }
#endif
