import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// What the preview of a Favorites search result needs to act on its file: the rename sheet,
/// the delete confirmation and Create Share Link, plus the file action toasts. The host
/// `BrowseFeature` sets the state; without these its toolbar buttons did nothing.
struct FavoritesPreviewHostActions: ViewModifier {
    let host: StoreOf<BrowseFeature>
    /// Set by the preview's Create Share Link button.
    @Binding var shareTarget: FileItem?
    let onViewShares: () -> Void

    private var renameTarget: Binding<FileItem?> {
        Binding(get: { host.renameSheetItem }, set: {
            if $0 == nil {
                host.send(.renameCancelled)
            }
        })
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(get: { host.deleteConfirmationItem != nil }, set: { _ in })
    }

    func body(content: Content) -> some View {
        content
            .dsSheet(item: renameTarget) { item in
                NameInputSheet(
                    icon: IconKit.rename,
                    title: L10n.Browse.renameTitle,
                    placeholder: L10n.Browse.renameNamePlaceholder,
                    confirmTitle: L10n.Common.save,
                    initialName: item.name,
                    isBusy: host.isPerformingFileAction,
                    onConfirm: { host.send(.renameConfirmed($0)) },
                    onCancel: { host.send(.renameCancelled) }
                )
            }
            .dsAlert(isPresented: isConfirmingDelete) {
                DSAlertSheet(
                    icon: IconKit.delete,
                    title: host.deleteConfirmationItem.map { L10n.Browse.deleteConfirmOne($0.name) } ?? L10n.Browse.deleteConfirmTitle,
                    message: L10n.Browse.deleteMessage,
                    confirmTitle: L10n.Common.delete,
                    dismissTitle: L10n.Common.cancel,
                    role: .destructive,
                    closeAccessibilityLabel: L10n.Common.close,
                    onConfirm: { host.send(.deleteConfirmed) },
                    onDismiss: { host.send(.deleteCancelled) }
                )
            }
            .dsSheet(item: $shareTarget) { item in
                CreateShareLinkSheet(
                    store: Store(
                        initialState: CreateShareLinkFeature.State(
                            serverURL: host.serverURL,
                            itemName: item.name,
                            itemPath: item.path,
                            isDirectory: item.isDirectory
                        )
                    ) {
                        CreateShareLinkFeature()
                    },
                    onViewShares: onViewShares
                )
            }
            .featureToast(error: host.fileActionErrorMessage)
    }
}

#Preview("Favorites preview actions") {
    let host = Store(initialState: BrowseFeature.State(
        serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
        directoryPath: "Docs",
        title: "Docs"
    )) { BrowseFeature() } withDependencies: { $0.filesClient = .previewValue }
    return Text(verbatim: "report.pdf")
        .modifier(FavoritesPreviewHostActions(host: host, shareTarget: .constant(nil), onViewShares: {}))
}
