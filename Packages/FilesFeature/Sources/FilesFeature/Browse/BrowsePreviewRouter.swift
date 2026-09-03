import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

/// Routes one preview-target `FileItem` to the right full-screen cover: unsupported screen,
/// streaming player, archive browser, image gallery, download-backed file preview, or the text
/// editor. Branch order must match `BrowseContentView.isPreviewContentReady`. The share sheet
/// target is view-local to `BrowseContentView`, so it's handed back through `onShareTarget`.
struct BrowsePreviewRouter: View {
    let store: StoreOf<BrowseFeature>
    let item: FileItem
    let removeArchiveAfterDownload: Bool
    let onShareTarget: (FileItem) -> Void

    var body: some View {
        if item.isUnsupportedForPreview {
            UnsupportedFilePreviewView(
                item: item,
                systemShare: .remote(item, serverURL: store.serverURL),
                onDismiss: { store.send(.previewDismissed) },
                onShareLink: (store.access?.canShare ?? false) ? {
                    onShareTarget(item)
                } : nil,
                onRename: (store.access?.canWrite ?? false) ? {
                    store.send(.renameTapped(item))
                } : nil,
                onDownload: (store.access?.canDownload ?? false) ? {
                    store.send(.downloadTapped(item, .documents, removeArchiveAfterDownload: removeArchiveAfterDownload))
                } : nil,
                onDelete: (store.access?.canDelete ?? false) ? {
                    store.send(.deleteTapped(item))
                } : nil
            )
        } else if item.isStreamableMedia, let url = FilesClient.previewURL(serverURL: store.serverURL, item: item) {
            // Guaranteed `isNativelyPlayable` here — undecodable containers/codecs are
            // `isUnsupportedForPreview` and handled by the branch above.
            StreamingPreviewView(
                item: item,
                url: url,
                serverURL: store.serverURL,
                onDismiss: { store.send(.previewDismissed) },
                onShare: (store.access?.canShare ?? false) ? {
                    onShareTarget(item)
                } : nil,
                onRename: (store.access?.canWrite ?? false) ? {
                    store.send(.renameTapped(item))
                } : nil,
                onDownload: (store.access?.canDownload ?? false) ? {
                    store.send(.downloadTapped(item, .documents, removeArchiveAfterDownload: removeArchiveAfterDownload))
                } : nil,
                onDelete: (store.access?.canDelete ?? false) ? {
                    store.send(.deleteTapped(item))
                } : nil
            )
        } else if item.isBrowsableArchive {
            ArchiveBrowserView(item: item, serverURL: store.serverURL, onDismiss: { store.send(.previewDismissed) })
        } else if (item.isImage || item.isRawImage) && !item.isSVG {
            ImageGalleryView(
                items: store.displayedItems.filter { ($0.isImage || $0.isRawImage) && !$0.isSVG },
                initialItem: item,
                serverURL: store.serverURL,
                onDismiss: { store.send(.previewDismissed) },
                onShare: (store.access?.canShare ?? false) ? { current in
                    onShareTarget(current)
                } : nil,
                onRename: (store.access?.canWrite ?? false) ? { current in
                    store.send(.renameTapped(current))
                } : nil,
                onDownload: (store.access?.canDownload ?? false) ? { current in
                    store.send(.downloadTapped(current, .documents, removeArchiveAfterDownload: removeArchiveAfterDownload))
                } : nil,
                onDelete: (store.access?.canDelete ?? false) ? { current in
                    store.send(.deleteTapped(current))
                } : nil
            )
        } else if item.isPreviewableViaDownload {
            FilePreviewContainerView(
                fileURL: store.previewFileURL,
                errorMessage: store.previewErrorMessage,
                onDismiss: { store.send(.previewDismissed) },
                onShareLink: (store.access?.canShare ?? false) ? {
                    onShareTarget(item)
                } : nil,
                onRename: (store.access?.canWrite ?? false) ? {
                    store.send(.renameTapped(item))
                } : nil,
                onDownload: (store.access?.canDownload ?? false) ? {
                    store.send(.downloadTapped(item, .documents, removeArchiveAfterDownload: removeArchiveAfterDownload))
                } : nil,
                onDelete: (store.access?.canDelete ?? false) ? {
                    store.send(.deleteTapped(item))
                } : nil
            )
        } else {
            TextFilePreviewView(
                item: item,
                serverURL: store.serverURL,
                fileName: item.name,
                kind: item.kind,
                content: store.textContent,
                errorMessage: store.textEditorErrorMessage,
                isLoading: store.isLoadingTextContent,
                isSaving: store.isSavingTextContent,
                onSave: { store.send(.textSaveTapped($0)) },
                onRetry: { store.send(.textContentRetryTapped) },
                onDismiss: { store.send(.previewDismissed) }
            )
        }
    }
}
