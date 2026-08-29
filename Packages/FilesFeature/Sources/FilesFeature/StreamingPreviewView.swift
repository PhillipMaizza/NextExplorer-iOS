import AVKit
import ComposableArchitecture
import CoreModels
import DesignSystem
import SwiftUI

/// Vertical swipe-to-dismiss thresholds and offset math are shared across the full-screen
/// media viewers — see `SwipeToDismissMetrics`.
private typealias DismissMetrics = SwipeToDismissMetrics

/// Full-screen video/audio player for `FileItem.isStreamableMedia` files: plays directly
/// from `FilesClient.previewURL` (the same `GET /api/preview` the server's own web client
/// scrubs with, via HTTP Range requests) rather than downloading the whole file first.
struct StreamingPreviewView: View {
    let item: FileItem
    let url: URL
    let serverURL: URL
    let onDismiss: () -> Void
    private let onShare: (() -> Void)?
    private let onRename: (() -> Void)?
    private let onDownload: (() -> Void)?
    private let onDelete: (() -> Void)?

    @State private var player: AVPlayer
    @State private var hasStartedPlaying = false
    /// Live vertical translation of an in-progress dismiss drag (0 when idle) — drives the
    /// content offset plus the background dim/shrink, matching the iOS Photos swipe-to-close.
    @State private var dragOffset: CGFloat = 0
    /// Set once a drag crosses the dismiss threshold: fades content + background to 0 while
    /// it flies off, so the fullScreenCover's own slide-out is never seen.
    @State private var isDismissing = false

    init(
        item: FileItem,
        url: URL,
        serverURL: URL,
        onDismiss: @escaping () -> Void,
        onShare: (() -> Void)? = nil,
        onRename: (() -> Void)? = nil,
        onDownload: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.item = item
        self.url = url
        self.serverURL = serverURL
        self.onDismiss = onDismiss
        self.onShare = onShare
        self.onRename = onRename
        self.onDownload = onDownload
        self.onDelete = onDelete
        self._player = State(initialValue: AVPlayer(url: url))
    }

    private var backgroundOpacity: Double {
        DismissMetrics.backgroundOpacity(forOffset: dragOffset, isDismissing: isDismissing)
    }

    private var contentOpacity: Double {
        DismissMetrics.contentOpacity(forOffset: dragOffset, isDismissing: isDismissing)
    }

    private var dragScale: CGFloat {
        DismissMetrics.scale(forOffset: dragOffset)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .opacity(backgroundOpacity)
                    .ignoresSafeArea()

                ZStack {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()

                    // A poster frame before playback starts — matching the web client's `<video
                    // poster>` — rather than a blank black rectangle while the stream buffers.
                    // Keyed on "has playback ever started," not "is playing right now": the latter
                    // would bring the poster back over the paused frame every time the user pauses.
                    if item.isVideo, item.supportsThumbnail, !hasStartedPlaying {
                        ThumbnailImage(serverURL: serverURL, path: item.id, signature: item.cacheSignature, fallbackIcon: IconKit.document, iconTint: Color.secondaryDS)
                            .aspectRatio(contentMode: .fit)
                            .background(Color.black)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    }

                    // Audio (and video with no poster) shows nothing but a black rectangle
                    // while the stream buffers — a spinner until the first frame plays.
                    if !hasStartedPlaying, !(item.isVideo && item.supportsThumbnail) {
                        ProgressView()
                            .tint(Color.white)
                            .allowsHitTesting(false)
                    }
                }
                .scaleEffect(dragScale)
                .offset(y: dragOffset)
                .opacity(contentOpacity)
            }
            .ignoresSafeArea()
            .simultaneousGesture(dismissDrag)
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
            if rate != 0 { hasStartedPlaying = true }
        }
        .onAppear {
            // Only video gets free rotation — an audio-only stream has nothing worth
            // rotating for, so it stays locked to portrait like every non-media screen.
            if item.isVideo { OrientationLock.shared.unlock() }
            // `setCategory` can block — AVFoundation warns against calling it synchronously
            // on the main thread while a session may already be active. `play()` itself must
            // stay on the main actor for `VideoPlayer` to observe it.
            Task.detached(priority: .userInitiated) {
                try? AVAudioSession.sharedInstance().setCategory(.playback)
            }
            player.play()
        }
        .onDisappear {
            if item.isVideo { OrientationLock.shared.lock() }
            player.pause()
            Task.detached(priority: .userInitiated) {
                try? AVAudioSession.sharedInstance().setCategory(.ambient)
            }
        }
    }

    /// Vertical swipe (either direction) to dismiss, like the iOS Photos viewer — runs
    /// alongside the player's own horizontal scrubber, which keeps its horizontal drags.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: DismissMetrics.minimumDragDistance)
            .onChanged { value in
                guard !isDismissing, abs(value.translation.height) > abs(value.translation.width) else {
                    dragOffset = 0
                    return
                }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                guard abs(value.translation.height) > abs(value.translation.width) else {
                    dragOffset = 0
                    return
                }
                if DismissMetrics.shouldDismiss(
                    translationHeight: value.translation.height,
                    predictedHeight: value.predictedEndTranslation.height
                ) {
                    // Freeze the content where the finger left it and crossfade it out, then
                    // remove the cover with animations off — no fly-out to collide with the
                    // fullScreenCover's own slide.
                    withAnimation(.easeOut(duration: DismissMetrics.dismissFadeDuration)) {
                        isDismissing = true
                    } completion: {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { onDismiss() }
                    }
                } else {
                    withAnimation(.spring(
                        response: DismissMetrics.resetSpringResponse,
                        dampingFraction: DismissMetrics.resetSpringDamping
                    )) {
                        dragOffset = 0
                    }
                }
            }
    }
}
