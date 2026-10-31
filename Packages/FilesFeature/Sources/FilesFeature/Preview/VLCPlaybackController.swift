import Combine
import Foundation
import VLCKitSPM

private enum Constants {
    /// libvlc network cache depth for remote streams. Deeper than the shallow default so large videos
    /// buffer and seek smoothly.
    static let networkCachingMilliseconds = 3000
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
            media.addOption(":network-caching=\(Constants.networkCachingMilliseconds)")
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

    /// Moves playback by `seconds` (negative goes back), clamped to the media.
    func seek(by seconds: Double) {
        guard let length = player.media?.length.intValue, length > 0 else { return }
        let delta = Float(seconds * 1000 / Double(length))
        scrub(to: min(max(position + delta, 0), 1))
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
