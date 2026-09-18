import CoreModels
import DesignSystem
import Localization
import SwiftUI
import UIKit
import VLCKitSPM

/// Full-screen player for the video/audio containers and codecs AVFoundation can't decode
/// (avi, webm, mkv, wmv, flv, mpg, mpeg; ogg, opus, wma), backed by libvlc via VLCKit — parity
/// with the web client's player. `StreamingPreviewView` (AVPlayer) still handles the natively
/// decodable formats.
///
/// Streams from `GET /api/preview` (Range-seekable) so large videos play without a full download.
/// libvlc uses its own HTTP stack, not `URLSession`'s shared cookie storage, so the session cookie
/// is passed explicitly as an `:http-cookie` option or the stream 401s. Archive entries pass a
/// local file URL, which needs no cookie.
private enum VLCPlaybackConstants {
    /// libvlc network cache depth for remote streams. Deeper than the shallow default so large videos
    /// buffer and seek smoothly.
    static let networkCachingMilliseconds = 3000
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
                        .animation(.easeInOut(duration: 0.2), value: controlsVisible)
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
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, controller.isPlaying else { return }
            controlsVisible = false
        }
    }
}

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
                        .shadow(radius: 8)
                }
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

/// Seek bar that jumps on tap and follows a drag — `DragGesture(minimumDistance: 0)` fires on
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
                    .fill(Color.white.opacity(0.3))
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
    }
}

/// Bridges `VLCMediaPlayer` (delegate/KVO, ObjC) into observable SwiftUI state and owns the
/// player for the view's lifetime. `@MainActor`, so it's `Sendable`: libvlc fires its delegate
/// callbacks on a background thread, and each hops back to the main actor before touching the
/// player or published state.
@MainActor
final class VLCPlaybackController: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    let player = VLCMediaPlayer()

    @Published var isPlaying = false
    @Published var isBuffering = true
    @Published var hasError = false
    @Published var position: Float = 0
    @Published var elapsedText = "0:00"
    @Published var durationText = "0:00"

    /// While the user drags the scrubber, ignore incoming time updates so the thumb doesn't
    /// fight the drag.
    private var isScrubbing = false

    override init() {
        super.init()
        player.delegate = self
    }

    /// Point the player at the media and start playback. Remote URLs get the session cookie and a
    /// network cache so seeking/buffering behaves; local files (archive entries) need neither.
    func start(url: URL) {
        let media = VLCMedia(url: url)
        if !url.isFileURL {
            // A deeper network cache smooths playback and seeking on large remote streams, where
            // the default was too shallow and stuttered.
            media.addOption(":network-caching=\(VLCPlaybackConstants.networkCachingMilliseconds)")
            media.addOption(":http-reconnect")
            // libvlc has no `:http-cookie` option; its http access reads only the per-media
            // cookie jar, which must be populated before play(). Feed each session cookie as a
            // Set-Cookie value scoped to the request host.
            let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
            if let host = url.host {
                for cookie in cookies {
                    media.storeCookie("\(cookie.name)=\(cookie.value)", forHost: host, path: cookie.path)
                }
            }
        }
        player.media = media
        player.play()
    }

    func stop() {
        player.stop()
    }

    func togglePlayPause() {
        if player.isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }

    func setScrubbing(_ scrubbing: Bool) {
        isScrubbing = scrubbing
    }

    func scrub(to value: Float) {
        position = value
        player.position = value
    }

    // MARK: VLCMediaPlayerDelegate

    @objc nonisolated func mediaPlayerStateChanged(_: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            isPlaying = player.isPlaying
            isBuffering = player.state == .buffering || player.state == .opening
            hasError = player.state == .error
            if hasError {
                isBuffering = false
            }
            durationText = player.media?.length.stringValue ?? durationText
        }
    }

    @objc nonisolated func mediaPlayerTimeChanged(_: Notification) {
        Task { @MainActor [weak self] in
            guard let self, !isScrubbing else { return }
            position = player.position
            elapsedText = player.time.stringValue
            durationText = player.media?.length.stringValue ?? durationText
            if isBuffering {
                isBuffering = false
            }
        }
    }
}
