import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import ShareUploads
import SwiftUI
#if os(iOS)
    import UIKit
#endif

/// Process-wide in-memory cache of decoded thumbnails, keyed by the thumbnail's own
/// (content-hashed) URL. Without it, every time a row scrolls back into view `ThumbnailImage`
/// re-reads the bytes off disk and rebuilds the `UIImage`: needless churn on a large grid.
/// `NSCache` evicts itself under memory pressure.
enum ThumbnailMemoryCache {
    nonisolated(unsafe) static let shared: NSCache<NSURL, PlatformImage> = {
        let cache = NSCache<NSURL, PlatformImage>()
        cache.countLimit = 400
        // Count alone doesn't bound bytes: 400 large decoded bitmaps is hundreds of MB. Cap
        // total decoded cost too so the cache evicts by memory, not just entry count.
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()

    static func decodedByteCost(of image: PlatformImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }

    /// Drops every decoded thumbnail. The disk layer is content hashed and cleared with the
    /// preview cache at each session boundary; this in memory copy is not user scoped, so it
    /// is emptied at the same points so no decoded image outlives a sign out (rule #11).
    static func removeAll() {
        shared.removeAllObjects()
        AudioArtwork.forgetMisses()
    }
}

private enum Constants {
    /// How often a thumbnail the server is still making is asked for, and how long to wait between
    /// asks when the server doesn't say. About 40 seconds in all, enough for a long video.
    static let pendingAttempts = 20
    static let pendingRetryDelay = Duration.seconds(2)
}

/// Lazily resolves and displays a thumbnail for one file: a small spinner while the request
/// is in flight, then either the image or `fallbackIcon`: on failure or once resolved to no
/// thumbnail (`GET /api/thumbnails/*` legitimately returns `{ thumbnail: "" }` for e.g. PDFs
/// or when thumbnails are disabled server-side). One request per instance: the API has no
/// bulk/listing variant, matching how the real web client also loads these per-file.
///
/// Loads through `ThumbnailCache` rather than `AsyncImage(url:)` directly, so a thumbnail
/// already seen this session (or a prior one) is read from disk instead of re-hitting the
/// server every time the row scrolls back into view.
struct ThumbnailImage: View {
    let serverURL: URL
    let path: String
    /// `FileItem.cacheSignature`: lets the resolved thumbnail URL be remembered on disk and
    /// re-checked only when the file itself changes.
    let signature: String
    let fallbackIcon: Image
    /// When set, a file with no thumbnail shows its typed page icon (like every other file row and
    /// tile) instead of the generic `fallbackIcon` glyph.
    var fallbackKind: String?
    let iconTint: Color
    /// The fallback's side when the image would fill a large frame (a video poster), so a missing
    /// thumbnail shows an icon at icon size rather than one stretched across the screen.
    var fallbackSize: CGFloat?
    /// Decode ceiling in pixels. A thumbnail is only ever shown at an icon/grid size, so
    /// decoding the server bytes (which can be a full size preview fallback) at full resolution
    /// is wasted memory and a main thread decode. Downsampled to this on a background task.
    var maxPixelDimension: CGFloat = 512
    /// The file's size and modification date, when the caller has the file: a picture just
    /// shared into the app shows its seeded thumbnail (`LocalThumbnailStore`) until the server's
    /// own is in, but only if these say it is the file that was uploaded.
    var fileSize: Int64?
    var modified: Date?

    @State private var uiImage: PlatformImage?
    @State private var didResolve = false
    @Dependency(\.filesClient) private var filesClient
    @Dependency(\.thumbnailCache) private var thumbnailCache
    @Dependency(\.localThumbnailStore) private var localThumbnailStore
    @Dependency(\.offlineFileStore) private var offlineFileStore
    @Dependency(\.date) private var date
    @Dependency(\.continuousClock) private var clock

    var body: some View {
        Group {
            if let uiImage {
                Image(platformImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else if didResolve {
                fallbackImage
            } else {
                ThumbnailLoadingPlaceholder()
            }
        }
        .task(id: "\(path)\u{0}\(signature)") {
            guard uiImage == nil else { return }
            // Audio has no server thumbnail: its cover art is read from the file's own tags.
            if fileItem.isAudio {
                uiImage = await audioArtwork()
                if !Task.isCancelled {
                    didResolve = true
                }
                return
            }
            let seeded = await seededImage()
            if Task.isCancelled {
                return
            }
            uiImage = seeded
            // A file kept offline is already on this device: draw it from that copy, whether or not
            // its folder was ever opened, instead of waiting on the server for a thumbnail.
            if seeded == nil, let local = await offlineImage() {
                if !Task.isCancelled {
                    uiImage = local
                }
                return
            }
            let thumbnailURL = await resolveThumbnailURL()
            // A cancelled task (the row scrolled away, or the tab was switched mid load) is not
            // a failure: leave the loading placeholder so re-appearing retries, instead of
            // marking it resolved and dropping to the generic fallback icon.
            if Task.isCancelled {
                return
            }
            guard let thumbnailURL else {
                didResolve = true
                return
            }
            if let cached = ThumbnailMemoryCache.shared.object(forKey: thumbnailURL as NSURL) {
                uiImage = cached
                if seeded != nil {
                    dropSeed()
                }
                return
            }
            let data: Data
            do {
                data = try await thumbnailCache.data(thumbnailURL)
            } catch {
                if !Task.isCancelled {
                    didResolve = true
                }
                return
            }
            if Task.isCancelled {
                return
            }
            let target = maxPixelDimension
            let decoded = await Task.detached(priority: .utility) {
                ImageDownsampling.image(from: data, maxPixelDimension: target)
            }.value
            if Task.isCancelled {
                return
            }
            if let decoded {
                ThumbnailMemoryCache.shared.setObject(
                    decoded,
                    forKey: thumbnailURL as NSURL,
                    cost: ThumbnailMemoryCache.decodedByteCost(of: decoded)
                )
                if seeded != nil {
                    dropSeed()
                }
            }
            uiImage = decoded ?? seeded
            didResolve = true
        }
    }

    /// The server's thumbnail URL for this file. While the server still makes it (a video's first
    /// frame takes a moment) this asks again, so the thumbnail appears by itself; a failed request
    /// leaves the placeholder icon without being remembered, so the next appearance asks again.
    private func resolveThumbnailURL() async -> URL? {
        let serverURL = serverURL
        let path = path
        let filesClient = filesClient
        for _ in 0 ..< Constants.pendingAttempts {
            do {
                return try await thumbnailCache.resolvedURL(path, signature) {
                    try await filesClient.thumbnailURL(serverURL, path)
                }
            } catch let pending as ThumbnailPendingError {
                try? await clock.sleep(for: pending.retryAfter ?? Constants.pendingRetryDelay)
                if Task.isCancelled {
                    return nil
                }
            } catch {
                return nil
            }
        }
        return nil
    }

    /// The seeded thumbnail of a file just shared into the app; `nil` without the file's size and
    /// date or when no seed matches them.
    private func seededImage() async -> PlatformImage? {
        guard let fileSize, let modified else { return nil }
        return await SeededThumbnail.image(
            from: localThumbnailStore, path: path, size: fileSize, modified: modified,
            maxPixel: maxPixelDimension, priority: .userInitiated, now: date.now
        )
    }

    /// The file as far as its path says, enough to look up a kept copy or build its stream address.
    private var fileItem: FileItem {
        let name = (path as NSString).lastPathComponent
        return FileItem(
            name: name,
            path: (path as NSString).deletingLastPathComponent,
            dateModified: .distantPast,
            size: 0,
            kind: (name as NSString).pathExtension.lowercased()
        )
    }

    /// An audio file's cover art, from its kept copy when it has one (no network), else its stream.
    private func audioArtwork() async -> PlatformImage? {
        let item = fileItem
        let store = offlineFileStore
        let local = await Task.detached(priority: .userInitiated) {
            store.localURLIgnoringStaleness(item)
        }.value
        guard let url = local ?? FilesClient.previewURL(serverURL: serverURL, item: item) else { return nil }
        return await AudioArtwork.image(url: url, fileExtension: item.kind, maxPixel: maxPixelDimension)
    }

    /// A picture is decoded from the kept copy and a video gives its first frame, so both show with
    /// no network and need nothing saved besides the file itself.
    private func offlineImage() async -> PlatformImage? {
        let store = offlineFileStore
        let target = maxPixelDimension
        let item = fileItem
        let local = await Task.detached(priority: .userInitiated) {
            store.localURLIgnoringStaleness(item)
        }.value
        guard let local else { return nil }
        // Kept in memory like a server thumbnail, so scrolling back does not decode or frame it again.
        let key = local.appendingPathComponent(String(Int(target))) as NSURL
        if let cached = ThumbnailMemoryCache.shared.object(forKey: key) {
            return cached
        }
        let image: PlatformImage? = if item.isVideo {
            await VideoThumbnailView.firstFrame(of: local, maxPixelSize: target)
        } else {
            await Task.detached(priority: .userInitiated) {
                ImageDownsampling.image(from: local, maxPixelDimension: target)
            }.value
        }
        if let image {
            ThumbnailMemoryCache.shared.setObject(
                image, forKey: key, cost: ThumbnailMemoryCache.decodedByteCost(of: image)
            )
        }
        return image
    }

    /// Drops the seed once the server's own thumbnail is showing.
    private func dropSeed() {
        let localThumbnailStore = localThumbnailStore
        let path = path
        Task.detached(priority: .utility) { localThumbnailStore.remove(path) }
    }

    private var fallbackImage: some View {
        Group {
            if let fallbackKind {
                FileTypeIcon(kind: fallbackKind)
            } else {
                fallbackIcon
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(iconTint)
            }
        }
        .frame(maxWidth: fallbackSize, maxHeight: fallbackSize)
    }
}

#if DEBUG
    /// A small striped JPEG standing in for a seeded thumbnail in previews.
    private enum PreviewSeed {
        static let jpeg: Data? = {
            let side = 64
            guard let context = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return nil }
            let colors = [
                CGColor(red: 0.94, green: 0.55, blue: 0.12, alpha: 1),
                CGColor(red: 0.12, green: 0.59, blue: 0.86, alpha: 1),
            ]
            for band in 0 ..< 8 {
                context.setFillColor(colors[band % colors.count])
                context.fill(CGRect(x: 0, y: band * side / 8, width: side, height: side / 8))
            }
            return context.makeImage().flatMap { ThumbnailRendering.jpegData($0, quality: 0.8) }
        }()
    }

    #Preview("Seeded from a file just shared into the app") {
        withDependencies {
            $0.localThumbnailStore.thumbnail = { _, _, _ in PreviewSeed.jpeg }
        } operation: {
            ThumbnailImage(
                serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
                path: "Photos/beach.jpg",
                signature: "0|0",
                fallbackIcon: IconKit.document,
                iconTint: .secondaryDS,
                fileSize: 2048,
                modified: Date()
            )
            .frame(width: .iconMedium, height: .iconMedium)
            .padding(.space16)
        }
    }
#endif

#Preview("Falls back to icon (previewValue has no thumbnails)") {
    ThumbnailImage(
        serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
        path: "Photos/vacation.jpg",
        signature: "0|0",
        fallbackIcon: IconKit.document,
        iconTint: .secondaryDS
    )
    .frame(width: .iconMedium, height: .iconMedium)
    .padding(.space16)
}
