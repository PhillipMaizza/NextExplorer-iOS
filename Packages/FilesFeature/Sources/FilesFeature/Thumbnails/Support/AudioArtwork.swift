import AVFoundation
import DesignSystem
import Foundation
import NetworkClient

/// The cover art inside an audio file's own tags (ID3, iTunes and the like). The server makes no
/// thumbnail of audio, so the app reads the art itself: from the kept copy when there is one, else
/// from the stream, where AVFoundation asks the server only for the byte ranges the tags sit in.
enum AudioArtwork {
    private enum Constants {
        /// A tag can hold art of any size; more than this is not loaded for a thumbnail.
        static let maxArtworkBytes = 16 * 1024 * 1024
    }

    /// The art of the file at `url`, decoded to at most `maxPixel`; `nil` when it has none.
    static func image(url: URL, fileExtension: String, maxPixel: CGFloat) async -> PlatformImage? {
        let key = url.absoluteString
        if let cached = ThumbnailMemoryCache.shared.object(forKey: url as NSURL) {
            return cached
        }
        if ThumbnailMisses.contains(key) {
            return nil
        }
        let read: PlatformImage?
        do {
            read = try await readArtwork(url: url, fileExtension: fileExtension, maxPixel: maxPixel)
        } catch {
            // The tags could not be read (offline, refused, a row that scrolled away): that says nothing
            // about the file, so nothing is remembered.
            return nil
        }
        guard let image = read else {
            ThumbnailMisses.insert(key)
            return nil
        }
        ThumbnailMemoryCache.shared.setObject(
            image,
            forKey: url as NSURL,
            cost: ThumbnailMemoryCache.decodedByteCost(of: image)
        )
        return image
    }

    /// Throws when the tags cannot be read; `nil` when they are read and hold no usable art.
    private static func readArtwork(url: URL, fileExtension: String, maxPixel: CGFloat) async throws -> PlatformImage? {
        var loader: ClientCertificateAssetLoader?
        let asset: AVURLAsset
        if url.isFileURL {
            asset = AVURLAsset(url: url)
        } else {
            // The same sources the player uses: the session cookie, or the client certificate loader.
            let cookies = HTTPCookieStorage.appSession.cookies(for: url) ?? []
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
        let metadata = try await asset.load(.commonMetadata)
        guard let artwork = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork)
            .first,
            let data = try await artwork.load(.dataValue),
            data.count <= Constants.maxArtworkBytes
        else {
            return nil
        }
        return await Task.detached(priority: .utility) {
            ImageDownsampling.image(from: data, maxPixelDimension: maxPixel)
        }.value
    }
}
