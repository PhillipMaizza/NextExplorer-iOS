import ComposableArchitecture
import CryptoKit
import Foundation
import PDFKit
import UIKit

private enum Constants {
    static let cacheRootDirectory = "PreviewCache"
    static let renderCacheDirectory = "pdf-thumbnails"
    static let renderCacheFileExtension = "jpg"
    /// Thumbnails don't need lossless; JPEG is far cheaper to encode and decode and a
    /// fraction of the disk footprint.
    static let renderJPEGQuality: CGFloat = 0.8
    /// Separates the file id from its content signature in a cache key.
    static let keyFieldSeparator = "\u{0}"
}

/// Renders and caches the first page of a PDF as a bitmap, for use as its browse thumbnail.
/// The server has no PDF thumbnail endpoint (`backend/src/routes/thumbnails.js` rejects the
/// extension), so the page is rasterized on device from a local PDF the caller supplies
/// (`PDFThumbnailStore` hands over what `previewFileLowPriority` downloaded).
///
/// Renders are cached as JPEGs under the shared `Library/Caches/PreviewCache` root, so
/// "Clear Cache" in Settings covers them. `PDFThumbnailStore` keeps the decoded images the
/// live grid needs in memory; this layer only re-reads/re-renders on a store eviction.
public struct PDFThumbnailCache: Sendable {
    /// `key` uniquely identifies the source file + its content signature; `maxPixel` bounds
    /// the render's longest side; `pdfURL` is the local PDF to rasterize. Returns `nil` when
    /// the file isn't a readable PDF.
    public var firstPageImage: @Sendable (
        _ key: String, _ maxPixel: CGFloat, _ pdfURL: URL
    ) async -> UIImage?

    public init(
        firstPageImage: @escaping @Sendable (
            _ key: String, _ maxPixel: CGFloat, _ pdfURL: URL
        ) async -> UIImage?
    ) {
        self.firstPageImage = firstPageImage
    }
}

/// Serializes PDF rasterization. `PDFDocument`/`PDFPage` and the CoreGraphics PDF stack are
/// not guaranteed safe to drive concurrently even from separate instances, and one-at-a-time
/// keeps a folder of PDFs from pegging every core on an older device. `render` has no `await`
/// inside, so the actor runs each call to completion before the next — true serialization,
/// no reentrancy. Downloads stay parallel (their own capped `URLSession`), which is the slow
/// part anyway.
private actor PDFPageRenderer {
    static let shared = PDFPageRenderer()

    func render(pdfAt url: URL, maxPixel: CGFloat) -> UIImage? {
        PDFThumbnailCache.renderFirstPage(of: url, maxPixel: maxPixel)
    }
}

extension PDFThumbnailCache {
    /// The cache key for a file: its id plus a content signature, so an edited file renders
    /// afresh rather than serving the stale page.
    static func cacheKey(id: String, signature: String) -> String {
        "\(id)\(Constants.keyFieldSeparator)\(signature)"
    }
}

extension PDFThumbnailCache {
    private static func hexDigest(of string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The production render-cache directory, under the shared `PreviewCache` root.
    static var defaultRenderCacheDirectory: URL? {
        guard let cachesDirectory = try? FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        return cachesDirectory
            .appendingPathComponent(Constants.cacheRootDirectory, isDirectory: true)
            .appendingPathComponent(Constants.renderCacheDirectory, isDirectory: true)
    }

    static func renderCacheFileURL(in directory: URL, for key: String) -> URL {
        directory
            .appendingPathComponent(hexDigest(of: key))
            .appendingPathExtension(Constants.renderCacheFileExtension)
    }

    /// Rasterizes page one of the PDF at `url`, scaled so its longest side is `maxPixel`.
    ///
    /// Renders through `UIGraphicsImageRenderer` at an explicit scale of 1 rather than
    /// `PDFPage.thumbnail(of:for:)`, which rasterizes at the main-screen scale — on a 3x
    /// device that is a 9x-area bitmap for the same `maxPixel`, i.e. megabytes per thumbnail
    /// held in memory. Opaque, white-backed: no alpha channel to carry around.
    static func renderFirstPage(of url: URL, maxPixel: CGFloat) -> UIImage? {
        guard let document = PDFDocument(url: url), let page = document.page(at: 0) else { return nil }
        let pageRect = page.bounds(for: .cropBox)
        guard pageRect.width > 0, pageRect.height > 0 else { return nil }

        let scale = maxPixel / max(pageRect.width, pageRect.height)
        let size = CGSize(
            width: (pageRect.width * scale).rounded(),
            height: (pageRect.height * scale).rounded()
        )

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cgContext = context.cgContext
            UIColor.white.setFill()
            cgContext.fill(CGRect(origin: .zero, size: size))
            cgContext.translateBy(x: 0, y: size.height)
            cgContext.scaleBy(x: scale, y: -scale)
            cgContext.translateBy(x: -pageRect.minX, y: -pageRect.minY)
            page.draw(with: .cropBox, to: cgContext)
        }
    }

    /// A cache backed by an on-disk render directory. `renderCacheDirectory` is a seam for
    /// tests — production uses `defaultRenderCacheDirectory`.
    static func live(renderCacheDirectory: URL?) -> PDFThumbnailCache {
        PDFThumbnailCache { key, maxPixel, pdfURL in
            let renderCacheURL = renderCacheDirectory.map { renderCacheFileURL(in: $0, for: key) }
            if let renderCacheURL, let data = try? Data(contentsOf: renderCacheURL) {
                // Force the decode here, off the caller's thread — `UIImage(data:)` alone
                // defers it to first draw, which would land on the main thread mid-scroll.
                return UIImage(data: data).map { $0.preparingForDisplay() ?? $0 }
            }

            guard let rendered = await PDFPageRenderer.shared.render(pdfAt: pdfURL, maxPixel: maxPixel) else {
                return nil
            }
            if let renderCacheURL, let jpeg = rendered.jpegData(compressionQuality: Constants.renderJPEGQuality) {
                try? FileManager.default.createDirectory(
                    at: renderCacheURL.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try? jpeg.write(to: renderCacheURL, options: .atomic)
            }
            return rendered
        }
    }
}

extension PDFThumbnailCache: DependencyKey {
    public static let liveValue = PDFThumbnailCache.live(renderCacheDirectory: defaultRenderCacheDirectory)
    public static let testValue = PDFThumbnailCache { _, _, _ in nil }
    public static let previewValue = PDFThumbnailCache { _, _, _ in nil }
}

public extension DependencyValues {
    var pdfThumbnailCache: PDFThumbnailCache {
        get { self[PDFThumbnailCache.self] }
        set { self[PDFThumbnailCache.self] = newValue }
    }
}
