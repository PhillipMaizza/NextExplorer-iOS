import CoreModels
import DesignSystem
import Localization
import SwiftUI
import VLCKitSPM
#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

/// Full-screen player for the video/audio containers and codecs AVFoundation can't decode
/// (avi, webm, mkv, wmv, flv, mpg, mpeg; ogg, opus, wma), backed by libvlc via VLCKit: parity
/// with the web client's player. `StreamingPreviewView` (AVPlayer) still handles the natively
/// decodable formats.
///
/// Streams from `GET /api/preview` (Range-seekable) so large videos play without a full download.
/// libvlc uses its own HTTP stack, not `URLSession`'s shared cookie storage, so the session cookie
/// is passed explicitly as an `:http-cookie` option or the stream 401s. Archive entries pass a
/// local file URL, which needs no cookie.
private enum VLCPlaybackConstants {
    static let controlsFadeDuration: Double = 0.2
    /// Idle time before the controls fade while playing, like AVPlayer's chrome.
    static let controlsAutoHideDelay: Duration = .seconds(3)
    static let playButtonShadowRadius: CGFloat = 8
    static let trackOpacity: Double = 0.3
    /// One VoiceOver swipe on the scrubber moves playback this far.
    static let accessibilitySeekSeconds: Double = 10
}

struct VLCPlayerView: View {
    let item: FileItem
    let url: URL
    let serverURL: URL
    let onDismiss: () -> Void
    private let onShare: (() -> Void)?
    private let onRename: (() -> Void)?
    private let onDownload: (() -> Void)?
    private let onDelete: (() -> Void)?

    @StateObject private var controller = VLCPlaybackController()
    @State private var controlsVisible = true
    @State private var autoHideTask: Task<Void, Never>?

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
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VLCVideoSurface(player: controller.player)
                    .ignoresSafeArea()

                // Transparent tap catcher above the libvlc drawable (which swallows touches of
                // its own) and below the controls, so taps in the empty area toggle the chrome
                // while the buttons/scrubber on top still get theirs first.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { toggleControls() }
                    .ignoresSafeArea()

                if controller.hasError {
                    VStack(spacing: .space12) {
                        IconKit.warning
                            .font(.system(size: .size44, weight: .regular))
                            .foregroundStyle(.white)
                        Text(L10n.Archive.openFailed)
                            .type(.body2(.regular))
                            .foregroundStyle(.white)
                    }
                } else {
                    VLCPlaybackControls(controller: controller)
                        .opacity(controlsVisible ? 1 : 0)
                        .allowsHitTesting(controlsVisible)
                        .animation(.easeInOut(duration: VLCPlaybackConstants.controlsFadeDuration), value: controlsVisible)
                }
            }
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
        .onChange(of: controller.isPlaying) { _, playing in
            if playing {
                scheduleAutoHide()
            } else {
                controlsVisible = true; autoHideTask?.cancel()
            }
        }
        #if os(macOS)
        // Space plays and pauses, as in QuickTime; the arrows keep stepping through the folder.
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            controller.togglePlayPause()
            return .handled
        }
        #endif
        .onAppear {
            if item.isVideo {
                OrientationLock.shared.unlock()
            }
            controller.start(url: url)
            scheduleAutoHide()
        }
        .onDisappear {
            if item.isVideo {
                OrientationLock.shared.lock()
            }
            autoHideTask?.cancel()
            controller.stop()
        }
    }

    private func toggleControls() {
        controlsVisible.toggle()
        if controlsVisible {
            scheduleAutoHide()
        } else {
            autoHideTask?.cancel()
        }
    }

    /// Fade the controls out after a few idle seconds, matching AVPlayer's chrome. Only while
    /// playing: a paused player keeps its controls up so the scrubber stays reachable.
    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = Task { @MainActor in
            try? await Task.sleep(for: VLCPlaybackConstants.controlsAutoHideDelay)
            guard !Task.isCancelled, controller.isPlaying else { return }
            controlsVisible = false
        }
    }
}

#if os(iOS)
    /// libvlc rendering surface: hands the player a plain `UIView` as its `drawable`.
    private struct VLCVideoSurface: UIViewRepresentable {
        let player: VLCMediaPlayer

        func makeUIView(context _: Context) -> UIView {
            let view = UIView()
            view.backgroundColor = .black
            view.isUserInteractionEnabled = false
            player.drawable = view
            return view
        }

        func updateUIView(_: UIView, context _: Context) {}
    }
#else
    /// libvlc rendering surface: hands the player a layer backed `NSView` as its `drawable`.
    private struct VLCVideoSurface: NSViewRepresentable {
        let player: VLCMediaPlayer

        func makeNSView(context _: Context) -> NSView {
            let view = PassthroughView()
            view.wantsLayer = true
            view.layer?.backgroundColor = .black
            player.drawable = view
            return view
        }

        func updateNSView(_: NSView, context _: Context) {}

        /// Lets clicks fall through to the SwiftUI tap catcher above, like `isUserInteractionEnabled = false`.
        private final class PassthroughView: NSView {
            override func hitTest(_: NSPoint) -> NSView? {
                nil
            }
        }
    }
#endif

/// Transport controls (VLCKit ships no UI of its own): a centered play/pause toggle plus a
/// bottom scrubber with elapsed / total time.
private struct VLCPlaybackControls: View {
    @ObservedObject var controller: VLCPlaybackController

    var body: some View {
        VStack {
            Spacer()

            // While buffering, the spinner stands in for the play/pause button rather than
            // stacking on top of it.
            if controller.isBuffering {
                DSSpinner()
                    .tint(Color.white)
                    .allowsHitTesting(false)
            } else {
                Button {
                    controller.togglePlayPause()
                } label: {
                    (controller.isPlaying ? IconKit.pause : IconKit.play)
                        .font(.system(size: .size44, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(radius: VLCPlaybackConstants.playButtonShadowRadius)
                }
                .accessibilityLabelWithTooltip(controller.isPlaying ? L10n.Media.pause : L10n.Media.play)
            }

            Spacer()

            HStack(spacing: .space12) {
                Text(controller.elapsedText)
                    .type(.caption(.regular))
                    .foregroundStyle(.white)
                    .monospacedDigit()

                VLCScrubBar(controller: controller)

                Text(controller.durationText)
                    .type(.caption(.regular))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            .padding(.horizontal, .space24)
            .padding(.bottom, .space24)
        }
    }
}

/// Seek bar that jumps on tap and follows a drag: `DragGesture(minimumDistance: 0)` fires on
/// both, unlike SwiftUI's `Slider` which only seeks when the thumb itself is dragged. The seek is
/// committed continuously; `setScrubbing` freezes incoming time updates so the thumb doesn't fight
/// the finger.
private struct VLCScrubBar: View {
    @ObservedObject var controller: VLCPlaybackController

    private let trackHeight: CGFloat = 3
    private let thumbSize: CGFloat = 12
    private let hitHeight: CGFloat = 44

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let progress = CGFloat(min(max(controller.position, 0), 1))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(VLCPlaybackConstants.trackOpacity))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(Color.accent)
                    .frame(width: width * progress, height: trackHeight)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: width * progress - thumbSize / 2)
            }
            .frame(height: hitHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        controller.setScrubbing(true)
                        controller.scrub(to: Float(min(max(value.location.x / width, 0), 1)))
                    }
                    .onEnded { _ in controller.setScrubbing(false) }
            )
        }
        .frame(height: hitHeight)
        // A drag only bar for the pointer; VoiceOver hears where playback is and swipes to seek.
        .accessibilityElement()
        .accessibilityLabel(L10n.Media.position)
        .accessibilityValue(L10n.Media.positionValue(controller.elapsedText, controller.durationText))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: controller.seek(by: VLCPlaybackConstants.accessibilitySeekSeconds)
            case .decrement: controller.seek(by: -VLCPlaybackConstants.accessibilitySeekSeconds)
            @unknown default: break
            }
        }
    }
}

#Preview("Controls") {
    VLCPlaybackControls(controller: VLCPlaybackController())
        .background(Color.black)
}
