import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// What a file opened on its own (a Favorites search result, a file kept offline) needs to act on
/// it: the rename sheet, the delete confirmation and Create Share Link, plus the file action toasts.
/// The host `BrowseFeature` sets the state; without these its toolbar buttons did nothing.
struct PreviewHostActions: ViewModifier {
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
                    title: host.deleteConfirmationItem.map { L10n.Browse.deleteConfirmOne($0.name) }
                        ?? L10n.Browse.deleteConfirmTitle,
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

/// The cover a screen opens one file in, without navigating to its folder: the host `BrowseFeature`
/// drives the same preview router Browse uses, and the actions above.
struct PreviewHostCover: ViewModifier {
    @Binding var host: StoreOf<BrowseFeature>?
    let onViewShares: () -> Void
    /// The file the preview asked to share.
    @State private var shareTarget: FileItem?

    func body(content: Content) -> some View {
        content.fullScreenCover(item: $host) { hostStore in
            if let previewItem = hostStore.previewItem {
                BrowsePreviewRouter(store: hostStore, item: previewItem, onShareTarget: { shareTarget = $0 })
                    .modifier(PreviewHostActions(
                        host: hostStore,
                        shareTarget: $shareTarget,
                        onViewShares: onViewShares
                    ))
            }
        }
    }
}

extension BrowseFeature.State {
    /// A host for previewing `item` alone, scoped to the folder holding it, with the cover's content
    /// set for the first frame; `rowTapped` then fetches it (or opens the kept copy offline).
    static func previewHost(for item: FileItem, serverURL: URL, folderTitle: String) -> Self {
        var host = Self(serverURL: serverURL, directoryPath: item.path, title: folderTitle)
        host.previewItem = item
        return host
    }
}

#Preview("Preview host actions") {
    let host = Store(initialState: BrowseFeature.State(
        serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
        directoryPath: "Docs",
        title: "Docs"
    )) { BrowseFeature() } withDependencies: { $0.filesClient = .previewValue }
    return Text(verbatim: "report.pdf")
        .modifier(PreviewHostActions(host: host, shareTarget: .constant(nil), onViewShares: {}))
}
