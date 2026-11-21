import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Foundation
import QuickLookThumbnailing
import ShareUploads
#if os(iOS)
    import UIKit
#endif

private enum Constants {
    static let cacheRootDirectory = CacheLayout.previewCacheName
    static let renderCacheDirectory = CacheLayout.pdfThumbnailsDirectoryName
    static let renderCacheFileExtension = "jpg"
    /// Thumbnails don't need lossless; JPEG is far cheaper to encode and decode and a
    /// fraction of the disk footprint.
    static let renderJPEGQuality: CGFloat = 0.8
    /// Separates the file id from its content signature in a cache key.
    static let keyFieldSeparator = "\u{0}"
    static let pdfExtension = "pdf"
    /// Quick Look draws at points times this scale; the store already asks in pixels.
    static let quickLookScale: CGFloat = 1
}

public struct DocumentThumbnailCache: Sendable {
    /// `key` uniquely identifies the source file + its content signature; `maxPixel` bounds
    /// the render's longest side; `fileURL` is the local document to draw, or `nil` to read only
    /// an earlier render. Returns `nil` when nothing can draw it.
    public var firstPageImage: @Sendable (
        _ key: String, _ maxPixel: CGFloat, _ fileURL: URL?
    ) async -> PlatformImage?

    public init(
        firstPageImage: @escaping @Sendable (
            _ key: String, _ maxPixel: CGFloat, _ fileURL: URL?
        ) async -> PlatformImage?
    ) {
        self.firstPageImage = firstPageImage
    }
}

private actor PDFPageRenderer {
    static let shared = PDFPageRenderer()

    func render(pdfAt url: URL, maxPixel: CGFloat) -> PlatformImage? {
        DocumentThumbnailCache.renderFirstPage(of: url, maxPixel: maxPixel)
    }
}

extension DocumentThumbnailCache {
    /// The cache key for a file: its id plus a content signature, so an edited file renders
    /// afresh rather than serving the stale page.
    static func cacheKey(id: String, signature: String) -> String {
        "\(id)\(Constants.keyFieldSeparator)\(signature)"
    }
}

extension DocumentThumbnailCache {
    private static func hexDigest(of string: String) -> String {
        string.sha256Hex()
    }

    /// The production render cache directory, under the shared `PreviewCache` root.
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
            .appendingPathComponent(CacheAccountScope.scopedFileName(hexDigest(of: key)))
            .appendingPathExtension(Constants.renderCacheFileExtension)
    }

    static func renderFirstPage(of url: URL, maxPixel: CGFloat) -> PlatformImage? {
        ThumbnailRendering.firstPDFPage(at: url, maxPixel: maxPixel).map { PlatformImage(cgImage: $0) }
    }

    static func renderQuickLookThumbnail(of url: URL, maxPixel: CGFloat) async -> PlatformImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: maxPixel, height: maxPixel),
            scale: Constants.quickLookScale,
            representationTypes: .thumbnail
        )
        guard let thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        else {
            return nil
        }
        return opaqueOnWhite(thumbnail.cgImage).map { PlatformImage(cgImage: $0) }
    }

    private static func opaqueOnWhite(_ image: CGImage) -> CGImage? {
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }

    /// A cache backed by an on disk render directory. `renderCacheDirectory` is a seam for
    /// tests: production uses `defaultRenderCacheDirectory`.
    static func live(renderCacheDirectory: URL?) -> DocumentThumbnailCache {
        DocumentThumbnailCache { key, maxPixel, fileURL in
            let scope = CacheAccountScope.current
            let wipeStamp = CacheAccountScope.wipeStamp(scope)
            let renderCacheURL = renderCacheDirectory.map { renderCacheFileURL(in: $0, for: key) }
            if let renderCacheURL, let data = try? Data(contentsOf: renderCacheURL) {
                // Force the decode here, off the caller's thread: `UIImage(data:)` alone
                // defers it to first draw, which would land on the main thread mid scroll.
                return PlatformImage(data: data).map { $0.preparingForDisplay() ?? $0 }
            }

            guard let fileURL else {
                return nil
            }
            let rendered = if fileURL.pathExtension.lowercased() == Constants.pdfExtension {
                await PDFPageRenderer.shared.render(pdfAt: fileURL, maxPixel: maxPixel)
            } else {
                await renderQuickLookThumbnail(of: fileURL, maxPixel: maxPixel)
            }
            // A load stopped by a logout must not write its page back after the wipe.
            guard let rendered, !Task.isCancelled else {
                return nil
            }
            if let renderCacheURL, CacheAccountScope.wipeStamp(scope) == wipeStamp,
               let jpeg = rendered.jpegData(compressionQuality: Constants.renderJPEGQuality)
            {
                try? FileManager.default.createDirectory(
                    at: renderCacheURL.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try? jpeg.write(to: renderCacheURL, options: .atomic)
                CacheTrimSchedule.shared.recordWriteAndTrimIfDue()
            }
            return rendered
        }
    }
}

extension DocumentThumbnailCache: DependencyKey {
    public static let liveValue = DocumentThumbnailCache.live(renderCacheDirectory: defaultRenderCacheDirectory)
    public static let testValue = DocumentThumbnailCache { _, _, _ in nil }
    public static let previewValue = DocumentThumbnailCache { _, _, _ in nil }
}

public extension DependencyValues {
    var documentThumbnailCache: DocumentThumbnailCache {
        get { self[DocumentThumbnailCache.self] }
        set { self[DocumentThumbnailCache.self] = newValue }
    }
}
