import DesignSystem
import Foundation
import ShareUploads

enum ImageDownsampling {
    static func image(from data: Data, maxPixelDimension: CGFloat) -> PlatformImage? {
        ThumbnailRendering.image(from: data, maxPixel: maxPixelDimension).map { PlatformImage(cgImage: $0) }
    }

    static func image(from url: URL, maxPixelDimension: CGFloat) -> PlatformImage? {
        ThumbnailRendering.image(at: url, maxPixel: maxPixelDimension).map { PlatformImage(cgImage: $0) }
    }
}
