import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import SwiftUI
import UIKit

/// Process-wide in-memory cache of decoded thumbnails, keyed by the thumbnail's own
/// (content-hashed) URL. Without it, every time a row scrolls back into view `ThumbnailImage`
/// re-reads the bytes off disk and rebuilds the `UIImage` — needless churn on a large grid.
/// `NSCache` evicts itself under memory pressure.
enum ThumbnailMemoryCache {
    nonisolated(unsafe) static let shared: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 400
        // Count alone doesn't bound bytes: 400 large decoded bitmaps is hundreds of MB. Cap
        // total decoded cost too so the cache evicts by memory, not just entry count.
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()

    static func decodedByteCost(of image: UIImage) -> Int {
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
/// is in flight, then either the image or `fallbackIcon` — on failure or once resolved to no
/// thumbnail (`GET /api/thumbnails/*` legitimately returns `{ thumbnail: "" }` for e.g. PDFs
/// or when thumbnails are disabled server-side). One request per instance — the API has no
/// bulk/listing variant, matching how the real web client also loads these per-file.
///
/// Loads through `ThumbnailCache` rather than `AsyncImage(url:)` directly, so a thumbnail
/// already seen this session (or a prior one) is read from disk instead of re-hitting the
/// server every time the row scrolls back into view.
struct ThumbnailImage: View {
    let serverURL: URL
    let path: String
    /// `FileItem.cacheSignature` — lets the resolved thumbnail URL be remembered on disk and
    /// re-checked only when the file itself changes.
    let signature: String
    let fallbackIcon: Image
    let iconTint: Color
    /// Decode ceiling in pixels. A thumbnail is only ever shown at an icon/grid size, so
    /// decoding the server bytes (which can be a full size preview fallback) at full resolution
    /// is wasted memory and a main thread decode. Downsampled to this on a background task.
    var maxPixelDimension: CGFloat = 512

    @State private var uiImage: UIImage?
    @State private var didResolve = false
    @Dependency(\.filesClient) private var filesClient
    @Dependency(\.thumbnailCache) private var thumbnailCache

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
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
            }
            uiImage = decoded
            didResolve = true
        }
    }

    private var fallbackImage: some View {
        fallbackIcon
            .resizable()
            .scaledToFit()
            .foregroundStyle(iconTint)
    }
}

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
