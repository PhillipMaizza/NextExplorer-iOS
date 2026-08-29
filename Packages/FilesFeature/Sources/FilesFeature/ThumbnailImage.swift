import ComposableArchitecture
import CoreModels
import DesignSystem
import SwiftUI
import FilesClient
import UIKit

/// Process-wide in-memory cache of decoded thumbnails, keyed by the thumbnail's own
/// (content-hashed) URL. Without it, every time a row scrolls back into view `ThumbnailImage`
/// re-reads the bytes off disk and rebuilds the `UIImage` — needless churn on a large grid.
/// `NSCache` evicts itself under memory pressure.
private enum ThumbnailMemoryCache {
    nonisolated(unsafe) static let shared: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 400
        return cache
    }()
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

    @State private var uiImage: UIImage?
    @State private var didResolve = false
    @Dependency(\.filesClient) private var filesClient
    @Dependency(\.thumbnailCache) private var thumbnailCache

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
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
            guard let thumbnailURL else {
                didResolve = true
                return
            }
            if let cached = ThumbnailMemoryCache.shared.object(forKey: thumbnailURL as NSURL) {
                uiImage = cached
                return
            }
            guard let data = try? await thumbnailCache.data(thumbnailURL) else {
                didResolve = true
                return
            }
            let decoded = UIImage(data: data)
            if let decoded {
                ThumbnailMemoryCache.shared.setObject(decoded, forKey: thumbnailURL as NSURL)
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
