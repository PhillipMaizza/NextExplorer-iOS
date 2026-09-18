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
    /// Whether to try AVFoundation first. `false` (a non-native container) starts on libvlc directly.
    let preferNative: Bool
    /// A pinned copy to fall back to when the primary stream fails (offline). `nil` when the primary
    /// is already a local file, or nothing is pinned.
    var offlineFallbackURL: URL?
    let onDismiss: () -> Void
    var onShare: (() -> Void)?
    var onRename: (() -> Void)?
    var onDownload: (() -> Void)?
    var onDelete: (() -> Void)?

    @State private var currentURL: URL
    @State private var useVLCFallback: Bool
    @State private var didUseOfflineFallback = false

    init(
        item: FileItem,
        url: URL,
        serverURL: URL,
        preferNative: Bool,
        offlineFallbackURL: URL? = nil,
        onDismiss: @escaping () -> Void,
        onShare: (() -> Void)? = nil,
        onRename: (() -> Void)? = nil,
        onDownload: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.item = item
        self.url = url
        self.serverURL = serverURL
        self.preferNative = preferNative
        self.offlineFallbackURL = offlineFallbackURL
        self.onDismiss = onDismiss
        self.onShare = onShare
        self.onRename = onRename
        self.onDownload = onDownload
        self.onDelete = onDelete
        _currentURL = State(initialValue: url)
        _useVLCFallback = State(initialValue: !preferNative)
    }

    var body: some View {
        Group {
            if useVLCFallback {
                VLCPlayerView(
                    item: item, url: currentURL, serverURL: serverURL,
                    onDismiss: onDismiss,
                    onShare: onShare, onRename: onRename, onDownload: onDownload, onDelete: onDelete
                )
            } else {
                StreamingPreviewView(
                    item: item, url: currentURL, serverURL: serverURL,
                    onDismiss: onDismiss,
                    onPlaybackFailed: handlePlaybackFailure,
                    onShare: onShare, onRename: onRename, onDownload: onDownload, onDelete: onDelete
                )
            }
        }
        // A new identity when the URL switches, so the player view re-initialises against the new
        // source (its `AVPlayer` is built once in `init`).
        .id(currentURL)
    }

    private func handlePlaybackFailure() {
        // A failed stream with a pinned copy in hand means we're offline: play the local copy rather
        // than dead-ending. Otherwise it's a decode issue, so retry the same URL through libvlc.
        if let offlineFallbackURL, !didUseOfflineFallback, currentURL != offlineFallbackURL {
            didUseOfflineFallback = true
            currentURL = offlineFallbackURL
            useVLCFallback = !preferNative
        } else {
            useVLCFallback = true
        }
    }
}
