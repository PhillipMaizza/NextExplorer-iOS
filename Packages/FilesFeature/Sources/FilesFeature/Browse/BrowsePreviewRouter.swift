import AppStorageKeys
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
    /// Only the image gallery uses this: reports the swiped-to image so the cover's `.zoom`
    /// source follows the current page. Every other branch previews a single item.
    var onGalleryItemChange: (FileItem) -> Void = { _ in }

    @Dependency(\.offlineFileStore) private var offlineFileStore
    /// When on, a fully downloaded copy plays locally even online; off streams when online and uses
    /// the local copy only as an offline fallback.
    @AppStorage(AppStorageKeys.preferOfflineMedia) private var preferOfflineMedia = true

    /// The primary source: with "prefer offline copies" on, a fully downloaded pinned copy (its
    /// `dateModified|size` staleness key proves it is complete and current) plays locally even online.
    /// Otherwise the Range-seekable preview stream, so online playback streams the fresh file.
    private func playbackURL(for item: FileItem) -> URL? {
        if preferOfflineMedia, let complete = offlineFileStore.localURL(item) {
            return complete
        }
        return FilesClient.previewURL(serverURL: store.serverURL, item: item)
    }

    /// A pinned copy that couldn't be verified complete (a placeholder `FileItem` opened from search
    /// or Favorites, with no real size/date). Used only if the stream fails, i.e. offline. `nil` when
    /// the primary is already the verified local copy.
    private func offlineFallbackURL(for item: FileItem) -> URL? {
        guard offlineFileStore.localURL(item) == nil else { return nil }
        return offlineFileStore.localURLIgnoringStaleness(item)
    }

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
        } else if item.isStreamableMedia, let url = playbackURL(for: item) {
            let onShare: (() -> Void)? = (store.access?.canShare ?? false) ? { onShareTarget(item) } : nil
            let onRename: (() -> Void)? = (store.access?.canWrite ?? false) ? { store.send(.renameTapped(item)) } : nil
            let onDownload: (() -> Void)? = (store.access?.canDownload ?? false) ? {
                store.send(.downloadTapped(item, .documents, removeArchiveAfterDownload: removeArchiveAfterDownload))
            } : nil
            let onDelete: (() -> Void)? = (store.access?.canDelete ?? false) ? { store.send(.deleteTapped(item)) } : nil

            // Native formats start on AVPlayer and fall back to libvlc on a decode failure; the rest
            // start on libvlc directly. A pinned offline copy plays from its local file (no stream).
            VideoPlayerHost(
                item: item, url: url, serverURL: store.serverURL,
                preferNative: item.isNativelyPlayable,
                offlineFallbackURL: offlineFallbackURL(for: item),
                onDismiss: { store.send(.previewDismissed) },
                onShare: onShare, onRename: onRename, onDownload: onDownload, onDelete: onDelete
            )
        } else if item.isBrowsableArchive {
            ArchiveBrowserView(item: item, serverURL: store.serverURL, onDismiss: { store.send(.previewDismissed) })
        } else if item.isImage || item.isRawImage, !item.isSVG {
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
                } : nil,
                onCurrentItemChange: onGalleryItemChange
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
