import CoreModels
import Foundation
import SwiftUI

/// Chooses the video/audio player and recovers when playback fails.
///
/// AVFoundation is preferred for the formats it decodes (hardware decode, system transport, AirPlay);
/// on a decode/load failure it hands off to `VLCPlayerView` (libvlc) for the same URL, so a
/// mislabelled container or exotic codec still plays. Formats AVFoundation never handles start on
/// libvlc directly.
///
/// `offlineFallbackURL` is a pinned local copy that couldn't be verified complete (a placeholder
/// `FileItem` opened from search / Favorites). It is used only if the primary stream fails, i.e. when
/// offline, so online playback always streams the fresh file while a pinned copy still keeps the video
/// openable with no connection. A fully downloaded copy is handed in as the primary `url` instead, so
/// it plays locally straight away.
struct VideoPlayerHost: View {
    let item: FileItem
    let url: URL
    let serverURL: URL
    /// Whether to try AVFoundation first. `false` (a non native container) starts on libvlc directly.
    let shouldPreferNative: Bool
    /// A pinned copy to fall back to when the primary stream fails (offline). `nil` when the primary
    /// is already a local file, or nothing is pinned.
    var offlineFallbackURL: URL?
    let onDismiss: () -> Void
    var onShare: (() -> Void)?
    var onRename: (() -> Void)?
    var onDownload: (() -> Void)?
    var onDelete: (() -> Void)?
    /// Inside the gallery, which draws the bars and owns rotation.
    let isEmbedded: Bool

    @State private var currentURL: URL
    @State private var shouldUseVLCFallback: Bool
    @State private var hasUsedOfflineFallback = false

    init(
        item: FileItem,
        url: URL,
        serverURL: URL,
        shouldPreferNative: Bool,
        offlineFallbackURL: URL? = nil,
        onDismiss: @escaping () -> Void,
        onShare: (() -> Void)? = nil,
        onRename: (() -> Void)? = nil,
        onDownload: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        isEmbedded: Bool = false
    ) {
        self.item = item
        self.url = url
        self.serverURL = serverURL
        self.shouldPreferNative = shouldPreferNative
        self.offlineFallbackURL = offlineFallbackURL
        self.onDismiss = onDismiss
        self.onShare = onShare
        self.onRename = onRename
        self.onDownload = onDownload
        self.onDelete = onDelete
        self.isEmbedded = isEmbedded
        _currentURL = State(initialValue: url)
        _shouldUseVLCFallback = State(initialValue: !shouldPreferNative)
    }

    var body: some View {
        Group {
            if shouldUseVLCFallback, !currentURL.isFileURL, isMac {
                macLocalCopy
            } else if shouldUseVLCFallback {
                VLCPlayerView(
                    item: item,
                    url: currentURL,
                    serverURL: serverURL,
                    onDismiss: onDismiss,
                    onShare: onShare,
                    onRename: onRename,
                    onDownload: onDownload,
                    onDelete: onDelete,
                    isEmbedded: isEmbedded
                )
            } else {
                StreamingPreviewView(
                    item: item,
                    url: currentURL,
                    serverURL: serverURL,
                    onDismiss: onDismiss,
                    onPlaybackFailed: handlePlaybackFailure,
                    onShare: onShare,
                    onRename: onRename,
                    onDownload: onDownload,
                    onDelete: onDelete,
                    isEmbedded: isEmbedded
                )
            }
        }
        // A new identity when the URL switches, so the player view reinitialises against the new
        // source (its `AVPlayer` is built once in `init`).
        .id(currentURL)
    }

    private var isMac: Bool {
        #if os(macOS)
            true
        #else
            false
        #endif
    }

    @ViewBuilder
    private var macLocalCopy: some View {
        #if os(macOS)
            MediaPreviewChrome(
                item: item,
                serverURL: serverURL,
                isEmbedded: isEmbedded,
                hasOpenWithPage: MacVLCLocalCopy.isTooLarge(item),
                onDismiss: onDismiss,
                onShare: onShare,
                onRename: onRename,
                onDownload: onDownload,
                onDelete: onDelete
            ) {
                MacVLCLocalCopy(item: item, serverURL: serverURL) { currentURL = $0 }
            }
        #endif
    }

    private func handlePlaybackFailure() {
        // A failed stream with a pinned copy in hand means we're offline: play the local copy rather
        // than dead ending. Otherwise it's a decode issue, so retry the same URL through libvlc.
        if let offlineFallbackURL, !hasUsedOfflineFallback, currentURL != offlineFallbackURL {
            hasUsedOfflineFallback = true
            currentURL = offlineFallbackURL
            shouldUseVLCFallback = !shouldPreferNative
        } else {
            shouldUseVLCFallback = true
        }
    }
}
