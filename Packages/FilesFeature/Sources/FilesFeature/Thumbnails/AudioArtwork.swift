import AVFoundation
import ComposableArchitecture
import DesignSystem
import Foundation
import NetworkClient

/// The cover art inside an audio file's own tags (ID3, iTunes and the like). The server makes no
/// thumbnail of audio, so the app reads the art itself: from the kept copy when there is one, else
/// from the stream, where AVFoundation asks the server only for the byte ranges the tags sit in.
enum AudioArtwork {
    /// Paths whose file has no art, so a folder of tagless files is not asked about again on every scroll.
    /// Kept for the session only: tags change rarely, and the answer costs one small request.
    private static let misses = LockIsolated(Set<String>())

    static func forgetMisses() {
        misses.setValue([])
    }

    /// The art of the file at `url`, decoded to at most `maxPixel`; `nil` when it has none.
    static func image(url: URL, fileExtension: String, maxPixel: CGFloat) async -> PlatformImage? {
        let key = url.absoluteString
        if let cached = ThumbnailMemoryCache.shared.object(forKey: url as NSURL) {
            return cached
        }
        if misses.value.contains(key) {
            return nil
        }
        guard let image = await readArtwork(url: url, fileExtension: fileExtension, maxPixel: maxPixel) else {
            // A cancelled read (the row scrolled away) says nothing about the file.
            if !Task.isCancelled {
                misses.withValue { _ = $0.insert(key) }
            }
            return nil
        }
        ThumbnailMemoryCache.shared.setObject(
            image,
            forKey: url as NSURL,
            cost: ThumbnailMemoryCache.decodedByteCost(of: image)
        )
        return image
    }

    private static func readArtwork(url: URL, fileExtension: String, maxPixel: CGFloat) async -> PlatformImage? {
        var loader: ClientCertificateAssetLoader?
        let asset: AVURLAsset
        if url.isFileURL {
            asset = AVURLAsset(url: url)
        } else {
            // The same sources the player uses: the session cookie, or the client certificate loader.
            let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
            if ClientIdentityStore.shared.hasCertificate(for: url),
               let made = ClientCertificateAssetLoader(remoteURL: url, cookies: cookies, fileExtension: fileExtension)
            {
                loader = made
                asset = made.asset
            } else {
                asset = AVURLAsset(url: url, options: [AVURLAssetHTTPCookiesKey: cookies])
            }
        }
        defer { loader?.invalidate() }
        guard let metadata = try? await asset.load(.commonMetadata),
              let artwork = AVMetadataItem.metadataItems(
                  from: metadata,
                  filteredByIdentifier: .commonIdentifierArtwork
              ).first,
              let data = try? await artwork.load(.dataValue)
        else {
            return nil
        }
        return await Task.detached(priority: .utility) {
            ImageDownsampling.image(from: data, maxPixelDimension: maxPixel)
        }.value
    }
}
