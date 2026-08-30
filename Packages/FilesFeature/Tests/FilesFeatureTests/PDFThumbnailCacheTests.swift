import Foundation
import Testing
import UIKit

@testable import FilesFeature

/// Covers the two pieces of `PDFThumbnailCache` that run without a live server: rasterizing
/// page one of a real PDF, and the short circuit that skips re-rendering on a hit.
@Suite
struct PDFThumbnailCacheTests {
    /// An isolated render-cache directory per test, so nothing lands in the shared
    /// `PreviewCache` root the `PreviewCacheStoreTests` size/clear assertions depend on.
    private func makeCacheDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdf-thumb-cache-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makePDF(pageSize: CGSize) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdf-thumb-test-\(UUID().uuidString).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        try? renderer.writePDF(to: url) { context in
            context.beginPage()
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: pageSize))
        }
        return url
    }

    // MARK: Happy path

    @Test
    func renderFirstPageProducesABitmapBoundedByMaxPixelAtScaleOne() throws {
        let url = makePDF(pageSize: CGSize(width: 200, height: 400))
        defer { try? FileManager.default.removeItem(at: url) }

        let image = try #require(PDFThumbnailCache.renderFirstPage(of: url, maxPixel: 512))

        // Longest side scaled to maxPixel, aspect kept (portrait: 256 x 512).
        #expect(abs(image.size.height - 512) < 1)
        #expect(abs(image.size.width - 256) < 1)
        // Rendered at an explicit scale of 1 — not the main-screen scale — so the pixel
        // buffer is exactly the point size, not 4x/9x it.
        #expect(image.scale == 1)
        #expect(image.cgImage?.height == 512)

        // The page (a solid blue fill) actually landed on the canvas: sample the centre.
        #expect(centrePixelIsBlue(image))
    }

    private func centrePixelIsBlue(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(
            cgImage,
            in: CGRect(
                x: -CGFloat(cgImage.width) / 2, y: -CGFloat(cgImage.height) / 2,
                width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)
            )
        )
        // systemBlue is dominated by the blue channel.
        return pixel[2] > pixel[0] && pixel[2] > 100
    }

    @Test
    func firstPageImageRendersOnceThenServesTheCachedResult() async throws {
        let key = PDFThumbnailCache.cacheKey(id: "Documents/\(UUID().uuidString).pdf", signature: "1.0|2048")
        let cacheDirectory = makeCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        let cache = PDFThumbnailCache.live(renderCacheDirectory: cacheDirectory)
        let pdfURL = makePDF(pageSize: CGSize(width: 200, height: 300))

        let first = await cache.firstPageImage(key, 256, pdfURL)
        // Same key, but pointed at a file that no longer exists: a re-render would fail, so a
        // non-nil result proves the first render was cached (memory, or the isolated disk dir).
        try FileManager.default.removeItem(at: pdfURL)
        let second = await cache.firstPageImage(key, 256, pdfURL)

        #expect(first != nil)
        #expect(second != nil)
        #expect(FileManager.default.fileExists(atPath: PDFThumbnailCache.renderCacheFileURL(in: cacheDirectory, for: key).path))
    }

    // MARK: Edge cases

    @Test
    func renderFirstPageReturnsNilForBytesThatAreNotAPDF() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-a-pdf-\(UUID().uuidString).pdf")
        try? Data("plain text".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(PDFThumbnailCache.renderFirstPage(of: url, maxPixel: 512) == nil)
    }
}
