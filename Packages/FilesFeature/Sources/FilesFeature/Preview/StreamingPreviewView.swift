import AVKit
import CoreModels
import DesignSystem
import SwiftUI

/// Full-screen video/audio player for `FileItem.isStreamableMedia` files that AVFoundation can
/// decode. Plays directly from a URL (`FilesClient.previewURL`, the same Range-seekable
/// `GET /api/preview` the web client scrubs, or a local file for a pinned/offline copy) rather than
/// downloading the whole file first.
///
/// Buffering and failure are driven off real `AVPlayer` state (`status`, `timeControlStatus`), not a
/// single "has it started" flag, so the spinner tracks actual stalls and a codec AVFoundation can't
/// decode reports back through `onPlaybackFailed` for the host to fall back to libvlc.
struct StreamingPreviewView: View {
    let item: FileItem
    let url: URL
    let serverURL: URL
    let onDismiss: () -> Void
    /// Called once if AVFoundation fails to load/decode this URL, so `VideoPlayerHost` can swap in
    /// `VLCPlayerView` for the same file. `nil` when there is no fallback (the error is shown here).
    private let onPlaybackFailed: (() -> Void)?
    private let onShare: (() -> Void)?
    private let onRename: (() -> Void)?
    private let onDownload: (() -> Void)?
    private let onDelete: (() -> Void)?

    @State private var player: AVPlayer
    @State private var hasStartedPlaying = false
    @State private var timeControlStatus: AVPlayer.TimeControlStatus = .paused
    @State private var didReportFailure = false

    init(
        item: FileItem,
        url: URL,
        serverURL: URL,
        onDismiss: @escaping () -> Void,
        onPlaybackFailed: (() -> Void)? = nil,
        onShare: (() -> Void)? = nil,
        onRename: (() -> Void)? = nil,
        onDownload: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.item = item
        self.url = url
        self.serverURL = serverURL
        self.onDismiss = onDismiss
        self.onPlaybackFailed = onPlaybackFailed
        self.onShare = onShare
        self.onRename = onRename
        self.onDownload = onDownload
        self.onDelete = onDelete
        // A local file needs no cookie. `AVPlayer(url:)` does NOT send cookies from
        // `HTTPCookieStorage.shared`, so for the remote stream the session cookie the server auths
        // `GET /api/preview` with never goes out and the stream 401s. Pass the matching cookies.
        let player: AVPlayer
        if url.isFileURL {
            player = AVPlayer(url: url)
        } else {
            let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
            let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPCookiesKey: cookies])
            player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        }
        // Let AVFoundation manage rebuffering so playback resumes automatically after a stall
        // instead of sitting paused, which is the main "buggy" symptom on a large stream.
        player.automaticallyWaitsToMinimizeStalling = true
        _player = State(initialValue: player)
    }

    /// The spinner shows while the player is waiting to fill its buffer, and before the first frame
    /// while the asset is still loading, but never once playback is actually under way.
    private var isBuffering: Bool {
        guard !hasStartedPlaying else { return timeControlStatus == .waitingToPlayAtSpecifiedRate }
        return true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VideoPlayer(player: player)
                    .ignoresSafeArea()

                // A poster frame before playback starts, matching the web client's `<video poster>`,
                // rather than a blank black rectangle. Keyed on "has playback ever started", not "is
                // playing now": the latter would bring the poster back over a paused frame.
                if item.isVideo, item.supportsThumbnail, !hasStartedPlaying {
                    ThumbnailImage(serverURL: serverURL, path: item.id, signature: item.cacheSignature, fallbackIcon: IconKit.document, iconTint: Color.secondaryDS)
                        .aspectRatio(contentMode: .fit)
                        .background(Color.black)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                if isBuffering {
                    DSSpinner()
                        .tint(Color.white)
                        .allowsHitTesting(false)
                }
            }
            .ignoresSafeArea()
            .previewChrome(
                title: item.name,
                systemShare: .remote(item, serverURL: serverURL),
                onShareLink: onShare,
                onRename: onRename,
                onDownload: onDownload,
                onDelete: onDelete,
                onClose: onDismiss
            )
        }
        .onReceive(player.publisher(for: \.rate)) { rate in
            if rate != 0 {
                hasStartedPlaying = true
            }
        }
        .onReceive(player.publisher(for: \.timeControlStatus)) { status in
            timeControlStatus = status
        }
        .onReceive(player.publisher(for: \.status)) { status in
            if status == .failed {
                reportFailureOnce()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { _ in
            reportFailureOnce()
        }
        .onAppear {
            // Only video gets free rotation; an audio-only stream stays locked to portrait.
            if item.isVideo {
                OrientationLock.shared.unlock()
            }
            // `setCategory` can block; AVFoundation warns against calling it synchronously on the
            // main thread while a session may already be active. `play()` stays on the main actor
            // for `VideoPlayer` to observe it.
            Task.detached(priority: .userInitiated) {
                try? AVAudioSession.sharedInstance().setCategory(.playback)
            }
            player.play()
        }
        .onDisappear {
            if item.isVideo {
                OrientationLock.shared.lock()
            }
            player.pause()
            Task.detached(priority: .userInitiated) {
                try? AVAudioSession.sharedInstance().setCategory(.ambient)
            }
        }
    }

    /// Report a decode/load failure exactly once, so the host swaps to the libvlc player. Guarded so
    /// the several failure signals (status, failed-to-end notification) don't fire it repeatedly.
    private func reportFailureOnce() {
        guard !didReportFailure, let onPlaybackFailed else { return }
        didReportFailure = true
        player.pause()
        onPlaybackFailed()
    }
}
