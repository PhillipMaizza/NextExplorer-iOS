import ComposableArchitecture
import Foundation

/// Files the app tried to draw a thumbnail of itself (cover art, first lines, a decoded picture) and
/// found nothing in, so a folder of such files is not read again on every scroll. Kept for the session
/// only, and emptied with the decoded thumbnails at every session boundary.
enum ThumbnailMisses {
    private static let keys = LockIsolated(Set<String>())

    static func contains(_ key: String) -> Bool {
        keys.value.contains(key)
    }

    static func insert(_ key: String) {
        keys.withValue { _ = $0.insert(key) }
    }

    static func removeAll() {
        keys.setValue([])
    }
}

/// The first lines of text files already read this session, by file and version.
enum TextSnippetCache {
    nonisolated(unsafe) static let shared: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 600
        return cache
    }()

    static func removeAll() {
        shared.removeAllObjects()
    }
}
