import AppStorageKeys
import ComposableArchitecture
import CoreModels
import FilesClient
import SwiftUI

/// Plays a video or audio file from the right source: a complete pinned copy when "prefer offline
/// copies" is on, otherwise the Range seekable preview stream, with an unverified pinned copy kept
/// as the fallback for when the stream fails offline. Shared by the full screen player and the
/// gallery's media page.
struct MediaPreview: View {
    let item: FileItem
    let serverURL: URL
    var isEmbedded = false
    var onDismiss: () -> Void = {}
    var onShare: (() -> Void)?
    var onRename: (() -> Void)?
    var onDownload: (() -> Void)?
    var onDelete: (() -> Void)?

    @Dependency(\.offlineFileStore) private var offlineFileStore
    /// When on, a fully downloaded copy plays locally even online; off streams when online and uses
    /// the local copy only as an offline fallback.
    @AppStorage(AppStorageKeys.preferOfflineMedia) private var shouldPreferOfflineMedia = true

    /// Where this item plays from, read off the main thread once per item: each lookup stats the
    /// offline store on disk, too much to repeat on every render of a playing page.
    @State private var sources: MediaSources?

    private var sourcesID: String {
        "\(item.id)\u{0}\(item.cacheSignature)\u{0}\(shouldPreferOfflineMedia)"
    }

    var body: some View {
        Group {
            if let sources, let url = sources.playback {
                player(url: url, offlineFallbackURL: sources.offlineFallback)
            }
        }
        .task(id: sourcesID) {
            let store = offlineFileStore
            let item = item
            let serverURL = serverURL
            let prefersOffline = shouldPreferOfflineMedia
            sources = await Task.detached(priority: .userInitiated) {
                MediaSources(item: item, serverURL: serverURL, prefersOffline: prefersOffline, store: store)
            }.value
        }
    }

    private func player(url: URL, offlineFallbackURL: URL?) -> some View {
        // Native formats start on AVPlayer and fall back to libvlc on a decode failure; the rest
        // start on libvlc directly.
        VideoPlayerHost(
            item: item,
            url: url,
            serverURL: serverURL,
            preferNative: item.isNativelyPlayable,
            offlineFallbackURL: offlineFallbackURL,
            onDismiss: onDismiss,
            onShare: onShare,
            onRename: onRename,
            onDownload: onDownload,
            onDelete: onDelete,
            isEmbedded: isEmbedded
        )
    }
}

/// A media file's playback source and its fallback.
private struct MediaSources: Equatable {
    /// A pinned copy whose `dateModified|size` staleness key proves it complete and current plays
    /// locally even online when preferred; otherwise online playback streams the fresh file.
    let playback: URL?
    /// A pinned copy that couldn't be verified complete (a placeholder `FileItem` opened from search
    /// or Favorites, with no real size or date), used only if the stream fails. `nil` when the
    /// primary is already the verified local copy.
    let offlineFallback: URL?

    init(item: FileItem, serverURL: URL, prefersOffline: Bool, store: OfflineFileStore) {
        let complete = store.localURL(item)
        if prefersOffline, let complete {
            playback = complete
        } else {
            playback = FilesClient.previewURL(serverURL: serverURL, item: item)
        }
        offlineFallback = complete == nil ? store.localURLIgnoringStaleness(item) : nil
    }
}

#Preview("Video") {
    MediaPreview(
        item: FileItem(name: "clip.mp4", path: "Videos", dateModified: .distantPast, size: 1_048_576, kind: "mp4"),
        serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/")
    )
}

#Preview("Embedded audio") {
    MediaPreview(
        item: FileItem(name: "song.mp3", path: "Music", dateModified: .distantPast, size: 4_194_304, kind: "mp3"),
        serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
        isEmbedded: true
    )
}
