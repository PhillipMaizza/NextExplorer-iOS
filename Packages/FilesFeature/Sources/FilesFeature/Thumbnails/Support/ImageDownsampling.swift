import DesignSystem
import Foundation
import ShareUploads

/// Decodes image bytes (or a file) straight to a bitmap no larger than it needs to be on
/// screen, via ImageIO's thumbnail path. `UIImage(data:)` / `AsyncImage` keep the full
/// resolution resident: a wall of 512px thumbnails, or a folder of 48MP photos in the
/// gallery, is what pushes an older device into a memory kill. `maxPixelDimension` is in
/// pixels, so callers pass `pointSize * displayScale`.
enum ImageDownsampling {
    static func image(from data: Data, maxPixelDimension: CGFloat) -> PlatformImage? {
        ThumbnailRendering.image(from: data, maxPixel: maxPixelDimension).map { PlatformImage(cgImage: $0) }
    }

    static func image(from url: URL, maxPixelDimension: CGFloat) -> PlatformImage? {
        ThumbnailRendering.image(at: url, maxPixel: maxPixelDimension).map { PlatformImage(cgImage: $0) }
    }
}
