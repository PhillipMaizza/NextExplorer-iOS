import DesignSystem
import Foundation

enum ThumbnailMemoryCache {
    nonisolated(unsafe) static let shared: NSCache<NSURL, PlatformImage> = {
        let cache = NSCache<NSURL, PlatformImage>()
        cache.countLimit = 400
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()

    static func decodedByteCost(of image: PlatformImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }

    static func removeAll() {
        shared.removeAllObjects()
        ThumbnailMisses.removeAll()
        TextSnippetCache.removeAll()
        Task { @MainActor in DocumentThumbnailStore.shared.removeAll() }
    }
}
