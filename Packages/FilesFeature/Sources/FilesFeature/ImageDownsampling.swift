import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Decodes image bytes (or a file) straight to a bitmap no larger than it needs to be on
/// screen, via ImageIO's thumbnail path. `UIImage(data:)` / `AsyncImage` keep the full
/// resolution resident — a wall of 512px thumbnails, or a folder of 48MP photos in the
/// gallery, is what pushes an older device into a memory kill. `maxPixelDimension` is in
/// pixels, so callers pass `pointSize * UIScreen.main.scale`.
enum ImageDownsampling {
    static func image(from data: Data, maxPixelDimension: CGFloat) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        return image(from: source, maxPixelDimension: maxPixelDimension)
    }

    static func image(from url: URL, maxPixelDimension: CGFloat) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { return nil }
        return image(from: source, maxPixelDimension: maxPixelDimension)
    }

    private static func image(from source: CGImageSource, maxPixelDimension: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelDimension)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
