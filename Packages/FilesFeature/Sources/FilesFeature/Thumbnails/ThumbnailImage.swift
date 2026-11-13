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
    }
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
    let iconTint: Color
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
    @Dependency(\.date) private var date

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
            let seeded = await seededImage()
            if Task.isCancelled {
                return
            }
            uiImage = seeded
            let thumbnailURL = await thumbnailCache.resolvedURL(path, signature) {
                try? await filesClient.thumbnailURL(serverURL, path)
            }
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

    /// The seeded thumbnail of a file just shared into the app; `nil` without the file's size and
    /// date or when no seed matches them.
    private func seededImage() async -> PlatformImage? {
        guard let fileSize, let modified else { return nil }
        return await SeededThumbnail.image(
            from: localThumbnailStore, path: path, size: fileSize, modified: modified,
            maxPixel: maxPixelDimension, priority: .userInitiated, now: date.now
        )
    }

    /// Drops the seed once the server's own thumbnail is showing.
    private func dropSeed() {
        let localThumbnailStore = localThumbnailStore
        let path = path
        Task.detached(priority: .utility) { localThumbnailStore.remove(path) }
    }

    private var fallbackImage: some View {
        fallbackIcon
            .resizable()
            .scaledToFit()
            .foregroundStyle(iconTint)
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
