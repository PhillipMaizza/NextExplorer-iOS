import CoreModels
import DesignSystem
import FilesClient
import Foundation
import ImageIO

/// Loads a thumbnail from the file's own content, for the files the server makes none of: an audio file's
/// cover art, a text file's first lines, and a picture the server could not decode. Each answers `nil`
/// when there is nothing to show. Only a definite "nothing there" is remembered for the session
/// (`ThumbnailMisses`); a failed download (offline, refused) is not, so the next appearance asks again.
struct ThumbnailContentLoader {
    private enum Constants {
        /// How much of a text file is read; a thumbnail shows a few lines of it.
        static let textBytes = 4096
        /// A picture of more pixels than this is not decoded for a thumbnail: it could need gigabytes.
        static let maxSourcePixels = 100_000_000
        static let versionQueryName = "v"
    }

    let serverURL: URL
    let path: String
    let signature: String
    let maxPixel: CGFloat
    let thumbnailCache: ThumbnailCache
    let offlineFileStore: OfflineFileStore

    /// The file as far as its path says, enough to look up a kept copy or build its stream address.
    var item: FileItem {
        let name = (path as NSString).lastPathComponent
        return FileItem(
            name: name,
            path: (path as NSString).deletingLastPathComponent,
            dateModified: .distantPast,
            size: 0,
            kind: (name as NSString).pathExtension.lowercased()
        )
    }

    private var cacheKey: String {
        "\(path)\u{0}\(signature)"
    }

    /// The kept copy of the file, when it has one: nothing is fetched for it.
    private func keptCopy() async -> URL? {
        let store = offlineFileStore
        let item = item
        return await Task.detached(priority: .userInitiated) {
            store.localURLIgnoringStaleness(item)
        }.value
    }

    /// An audio file's cover art, from its kept copy when it has one, else its stream.
    func audioArtwork() async -> PlatformImage? {
        let item = item
        let local = await keptCopy()
        guard let url = local ?? FilesClient.previewURL(serverURL: serverURL, item: item) else { return nil }
        return await AudioArtwork.image(url: url, fileExtension: item.kind, maxPixel: maxPixel)
    }

    /// The first lines of a text file, from its kept copy when it has one, else the server's raw text (which
    /// it refuses above its editor limit). Cached for the session.
    func textSnippet() async -> String? {
        let key = cacheKey
        if let cached = TextSnippetCache.shared.object(forKey: key as NSString) {
            return cached as String
        }
        if ThumbnailMisses.contains(key) {
            return nil
        }
        let bytes: Data
        if let local = await keptCopy() {
            let head = await Task.detached(priority: .utility) {
                try? FileHandle(forReadingFrom: local).read(upToCount: Constants.textBytes)
            }.value
            guard let head else { return nil }
            bytes = head
        } else if let url = FilesClient.rawFileURL(serverURL: serverURL, item: item).map(versioned),
                  let downloaded = try? await thumbnailCache.data(url)
        {
            bytes = downloaded
        } else {
            return nil
        }
        if Task.isCancelled {
            return nil
        }
        guard let text = await Task.detached(priority: .utility, operation: { TextSnippet.make(from: bytes) }).value
        else {
            ThumbnailMisses.insert(key)
            return nil
        }
        TextSnippetCache.shared.setObject(text as NSString, forKey: key as NSString)
        return text
    }

    /// A picture the server has no thumbnail of, decoded on the device from its preview (the server cuts a
    /// RAW file's embedded JPEG out for that). `nil` for what ImageIO cannot read, such as SVG.
    func deviceDecodedImage() async -> PlatformImage? {
        let item = item
        guard item.isImage || item.isRawImage, !item.isSVG else { return nil }
        let key = cacheKey
        if ThumbnailMisses.contains(key) {
            return nil
        }
        guard let url = FilesClient.previewURL(serverURL: serverURL, item: item),
              let data = try? await thumbnailCache.data(url)
        else {
            return nil
        }
        let target = maxPixel
        let image = await Task.detached(priority: .utility) { () -> PlatformImage? in
            guard let pixels = Self.sourcePixelCount(of: data), pixels <= Constants.maxSourcePixels else { return nil }
            return ImageDownsampling.image(from: data, maxPixelDimension: target)
        }.value
        if image == nil, !Task.isCancelled {
            ThumbnailMisses.insert(key)
        }
        return image
    }

    /// The pixels of the picture in `data`, read from its header without decoding it.
    private static func sourcePixelCount(of data: Data) -> Int? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return nil
        }
        return width * height
    }

    /// `url` tied to this version of the file, so a cached copy is never shown for a changed file.
    private func versioned(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(
            name: Constants.versionQueryName,
            value: signature
        )]
        return components.url ?? url
    }
}
