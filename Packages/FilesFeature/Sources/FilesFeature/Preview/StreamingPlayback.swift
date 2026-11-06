import AVFoundation
import Foundation
import NetworkClient

/// The player behind `StreamingPreviewView`, built once on first use. SwiftUI creates the view
/// struct (and evaluates its `@State` initial value) on every parent update but keeps only the
/// first, so anything made in the view's init is made again and thrown away each time. An
/// `AVPlayer` starts loading its item the moment it exists, and on an mTLS server that meant a
/// loader opening its own connection and session that nothing ever closed. This holder is cheap to
/// throw away: the player, the certificate check and the loader only come into being when the
/// kept view first reads `player`.
@MainActor
final class StreamingPlayback {
    private let url: URL
    private let fileExtension: String
    private var loader: ClientCertificateAssetLoader?

    init(url: URL, fileExtension: String) {
        self.url = url
        self.fileExtension = fileExtension
    }

    private(set) lazy var player: AVPlayer = makePlayer()

    /// Ends the loader's transfers and session when the player goes away.
    func tearDown() {
        loader?.invalidate()
    }

    private func makePlayer() -> AVPlayer {
        let player: AVPlayer
        if url.isFileURL {
            player = AVPlayer(url: url)
        } else {
            // `AVPlayer(url:)` does NOT send cookies from `HTTPCookieStorage.shared`, so the session
            // cookie `GET /api/preview` is authorized by would never go out and the stream 401s.
            let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
            if ClientIdentityStore.shared.hasCertificate(for: url),
               let loader = ClientCertificateAssetLoader(remoteURL: url, cookies: cookies, fileExtension: fileExtension)
            {
                self.loader = loader
                player = AVPlayer(playerItem: AVPlayerItem(asset: loader.asset))
            } else {
                let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPCookiesKey: cookies])
                player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            }
        }
        // Let AVFoundation manage rebuffering so playback resumes automatically after a stall
        // instead of sitting paused, which is the main "buggy" symptom on a large stream.
        player.automaticallyWaitsToMinimizeStalling = true
        return player
    }
}
