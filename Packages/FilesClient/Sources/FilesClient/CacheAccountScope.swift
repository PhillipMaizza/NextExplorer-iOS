import Foundation

/// Process-wide identifier of the account whose cached data the disk stores read and write, so
/// several signed-in accounts (multiple servers, or two users on one server) never share cache
/// entries. Folded into every cache key by `DirectoryCacheStore`, `JSONCacheStore` and the preview
/// cache, so switching the active account transparently reads that account's own cache instead of
/// the previous one's — no wipe, both accounts' caches survive a switch.
///
/// Set from `AppFeature` whenever a session begins or the active account changes (mirroring
/// `DownloadAccountScope`), and reset to empty on full teardown. An empty value is the legacy
/// unscoped namespace, used before any session and by tests that do not set a scope.
public enum CacheAccountScope {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var _value = ""

    public static var current: String {
        lock.withLock { _value }
    }

    public static func set(_ value: String) {
        lock.withLock { _value = value }
    }
}
