import AVKit
import ComposableArchitecture
import CoreModels
import DesignSystem
import SwiftUI

private enum Constants {
    static let closeButtonInset: CGFloat = .space16
    /// Vertical drag distance past which releasing dismisses the player.
    static let dismissDistanceThreshold: CGFloat = 120
    /// Projected fling distance that dismisses even on a short, fast flick.
    static let dismissPredictedThreshold: CGFloat = 360
    /// Only track a drag as a dismiss once it's clearly more vertical than horizontal —
    /// horizontal drags belong to the player's own scrubber.
    static let dragMinimumDistance: CGFloat = 12
    static let minBackgroundOpacity: Double = 0.35
    static let dragScaleFloor: CGFloat = 0.88
    static let dragScaleDivisor: CGFloat = 1400
    static let dragResetSpringResponse: Double = 0.3
    static let dragResetSpringDamping: Double = 0.85
    /// Fade the frozen content + dimmed backdrop to nothing on release-to-dismiss, then pull
    /// the cover with animations off — so the exit is a clean crossfade, not our motion
    /// fighting the fullScreenCover's own slide-from-bottom.
    static let dismissFadeDuration: Double = 0.2
    /// Content opacity at full drag progress (before release) — a slight fade under the
    /// finger on top of the shrink.
    static let draggingContentOpacityFloor: Double = 0.6
}

/// Full-screen video/audio player for `FileItem.isStreamableMedia` files: plays directly
/// from `FilesClient.previewURL` (the same `GET /api/preview` the server's own web client
/// scrubs with, via HTTP Range requests) rather than downloading the whole file first.
struct StreamingPreviewView: View {
    let item: FileItem
    let url: URL
    let serverURL: URL
    let onDismiss: () -> Void

    @State private var player: AVPlayer
    @State private var hasStartedPlaying = false
    /// Live vertical translation of an in-progress dismiss drag (0 when idle) — drives the
    /// content offset plus the background dim/shrink, matching the iOS Photos swipe-to-close.
    @State private var dragOffset: CGFloat = 0
    /// Set once a drag crosses the dismiss threshold: fades content + background to 0 while
    /// it flies off, so the fullScreenCover's own slide-out is never seen.
    @State private var isDismissing = false

    init(item: FileItem, url: URL, serverURL: URL, onDismiss: @escaping () -> Void) {
        self.item = item
        self.url = url
        self.serverURL = serverURL
        self.onDismiss = onDismiss
        self._player = State(initialValue: AVPlayer(url: url))
    }

    private var dragProgress: CGFloat {
        min(1, abs(dragOffset) / Constants.dismissDistanceThreshold)
    }

    private var backgroundOpacity: Double {
        if isDismissing { return 0 }
        return 1 - (1 - Constants.minBackgroundOpacity) * Double(dragProgress)
    }

    private var contentOpacity: Double {
        if isDismissing { return 0 }
        return 1 - (1 - Constants.draggingContentOpacityFloor) * Double(dragProgress)
    }

    private var dragScale: CGFloat {
        max(Constants.dragScaleFloor, 1 - abs(dragOffset) / Constants.dragScaleDivisor)
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            ZStack(alignment: .topTrailing) {
                VideoPlayer(player: player)
                    .ignoresSafeArea()

                // A poster frame before playback starts — matching the web client's `<video
                // poster>` — rather than a blank black rectangle while the stream buffers.
                // Keyed on "has playback ever started," not "is playing right now": the latter
                // would bring the poster back over the paused frame every time the user pauses.
                if item.isVideo, item.supportsThumbnail, !hasStartedPlaying {
                    ThumbnailImage(serverURL: serverURL, path: item.id, fallbackIcon: IconKit.document, iconTint: Color.secondaryDS)
                        .aspectRatio(contentMode: .fit)
                        .background(Color.black)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                DSCloseButton(action: onDismiss)
                    .padding(Constants.closeButtonInset)
            }
            .scaleEffect(dragScale)
            .offset(y: dragOffset)
            .opacity(contentOpacity)
        }
        .simultaneousGesture(dismissDrag)
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
        DragGesture(minimumDistance: Constants.dragMinimumDistance)
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
                let passedDistance = abs(value.translation.height) > Constants.dismissDistanceThreshold
                let passedFlick = abs(value.predictedEndTranslation.height) > Constants.dismissPredictedThreshold
                if passedDistance || passedFlick {
                    // Freeze the content where the finger left it and crossfade it out, then
                    // remove the cover with animations off — no fly-out to collide with the
                    // fullScreenCover's own slide.
                    withAnimation(.easeOut(duration: Constants.dismissFadeDuration)) {
                        isDismissing = true
                    } completion: {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { onDismiss() }
                    }
                } else {
                    withAnimation(.spring(
                        response: Constants.dragResetSpringResponse,
                        dampingFraction: Constants.dragResetSpringDamping
                    )) {
                        dragOffset = 0
                    }
                }
            }
    }
}
