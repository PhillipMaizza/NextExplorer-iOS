import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Small images for thumbnails, with CoreGraphics only, so the app and the share extension (which
/// has no UIKit image renderer budget to spare) draw them the same way. Every function is
/// synchronous and does real work: call it off the main actor.
public enum ThumbnailRendering {
    /// An image file or bytes decoded straight to at most `maxPixel` on its longest side, through
    /// ImageIO's thumbnail path, so a 48MP photo never sits in memory at full size.
    public static func image(at url: URL, maxPixel: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        return thumbnail(of: source, maxPixel: maxPixel)
    }

    public static func image(from data: Data, maxPixel: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        return thumbnail(of: source, maxPixel: maxPixel)
    }

    /// The first page of a PDF on white, at most `maxPixel` on its longest side.
    public static func firstPDFPage(at url: URL, maxPixel: CGFloat) -> CGImage? {
        guard let document = PDFDocument(url: url), let page = document.page(at: 0) else { return nil }
        let pageRect = page.bounds(for: .cropBox)
        guard pageRect.width > 0, pageRect.height > 0 else { return nil }
        let scale = maxPixel / max(pageRect.width, pageRect.height)
        let width = Int((pageRect.width * scale).rounded())
        let height = Int((pageRect.height * scale).rounded())
        guard width > 0, height > 0, let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -pageRect.minX, y: -pageRect.minY)
        page.draw(with: .cropBox, to: context)
        return context.makeImage()
    }

    /// A thumbnail for a file of `type`: a decoded image for images, the first page for PDFs,
    /// `nil` for anything else or anything that fails to decode.
    public static func thumbnail(of url: URL, type: UTType?, maxPixel: CGFloat) -> CGImage? {
        guard let type else { return nil }
        if type.conforms(to: .pdf) {
            return firstPDFPage(at: url, maxPixel: maxPixel)
        }
        if type.conforms(to: .image) {
            return image(at: url, maxPixel: maxPixel)
        }
        return nil
    }

    public static func jpegData(_ image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static var sourceOptions: CFDictionary {
        [kCGImageSourceShouldCache: false] as CFDictionary
    }

    private static func thumbnail(of source: CGImageSource, maxPixel: CGFloat) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
