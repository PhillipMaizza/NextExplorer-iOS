import DesignSystem
import Foundation
import ShareUploads

/// The seeded thumbnail of a file just shared into the app (`LocalThumbnailStore`), read and
/// decoded off the main actor. A file too old to have a seed returns `nil` without touching the
/// disk, so a folder of older files scrolls exactly as before.
enum SeededThumbnail {
    static func image(
        from store: LocalThumbnailStore,
        path: String,
        size: Int64,
        modified: Date,
        maxPixel: CGFloat,
        priority: TaskPriority,
        now: Date
    ) async -> PlatformImage? {
        guard LocalThumbnailStore.canHaveSeed(modified: modified, now: now) else { return nil }
        return await Task.detached(priority: priority) {
            store.thumbnail(path, size, modified).flatMap { ImageDownsampling.image(
                from: $0,
                maxPixelDimension: maxPixel
            ) }
        }.value
    }
}
