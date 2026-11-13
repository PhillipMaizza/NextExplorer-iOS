import ComposableArchitecture
import DesignSystem
import Localization
import SwiftUI

/// The Offline tab's delete confirmations for saved files, one file or the selection, shared by the
/// list, the grid and the Mac table.
private struct DownloadDeleteAlerts: ViewModifier {
    let store: StoreOf<OfflineTabFeature>

    /// No op setters: each confirmation sheet is dismiss disabled and only closes through one
    /// of `DSAlertSheet`'s own buttons, which drive the reducer directly.
    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(get: { store.deleteConfirmationItem != nil }, set: { _ in })
    }

    private var deleteConfirmationTitle: String {
        guard let item = store.deleteConfirmationItem else { return L10n.Downloads.deleteConfirmTitle }
        return L10n.Downloads.deleteConfirmOne(item.fileName)
    }

    private var bulkDeleteConfirmationBinding: Binding<Bool> {
        Binding(get: { store.bulkDeleteConfirmationIsPresented }, set: { _ in })
    }

    private var bulkDeleteConfirmationTitle: String {
        L10n.Downloads.deleteConfirmMany(store.selectedDownloadIDs.count)
    }

    func body(content: Content) -> some View {
        content
            .dsAlert(isPresented: deleteConfirmationBinding) {
                DSAlertSheet(
                    icon: IconKit.delete,
                    title: deleteConfirmationTitle,
                    // Distinguishes this from every other delete confirmation in the app, which
                    // deletes on the server: this one only ever touches the local copy.
                    message: L10n.Downloads.deleteSingleMessage,
                    confirmTitle: L10n.Common.delete,
                    dismissTitle: L10n.Common.cancel,
                    role: .destructive,
                    closeAccessibilityLabel: L10n.Common.close,
                    onConfirm: { store.send(.deleteConfirmed) },
                    onDismiss: { store.send(.deleteCancelled) }
                )
            }
            .hapticFeedback(.warning, trigger: store.deleteConfirmationItem)
            .dsAlert(isPresented: bulkDeleteConfirmationBinding) {
                DSAlertSheet(
                    icon: IconKit.delete,
                    title: bulkDeleteConfirmationTitle,
                    message: L10n.Downloads.deleteBulkMessage,
                    confirmTitle: L10n.Common.delete,
                    dismissTitle: L10n.Common.cancel,
                    role: .destructive,
                    closeAccessibilityLabel: L10n.Common.close,
                    onConfirm: { store.send(.bulkDeleteConfirmed) },
                    onDismiss: { store.send(.bulkDeleteCancelled) }
                )
            }
            .hapticFeedback(.warning, trigger: store.bulkDeleteConfirmationIsPresented)
    }
}

extension View {
    func downloadDeleteAlerts(store: StoreOf<OfflineTabFeature>) -> some View {
        modifier(DownloadDeleteAlerts(store: store))
    }
}

#Preview("Delete one") {
    var state = OfflineTabFeature.State()
    state.deleteConfirmationItem = LocalDownload(
        url: URL(fileURLWithPath: "/tmp/report.pdf"),
        fileName: "report.pdf",
        size: 1_200_000,
        modifiedDate: Date()
    )
    return Color.clear.downloadDeleteAlerts(store: Store(initialState: state) { OfflineTabFeature() })
}

#Preview("Delete several") {
    var state = OfflineTabFeature.State()
    state.selectedDownloadIDs = ["/tmp/a.pdf", "/tmp/b.pdf"]
    state.bulkDeleteConfirmationIsPresented = true
    return Color.clear.downloadDeleteAlerts(store: Store(initialState: state) { OfflineTabFeature() })
}
