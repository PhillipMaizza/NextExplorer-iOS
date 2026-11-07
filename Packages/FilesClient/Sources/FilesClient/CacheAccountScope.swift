import CryptoKit
import Foundation

/// Process-wide identifier of the account whose cached data the disk stores read and write, so
/// several signed-in accounts (multiple servers, or two users on one server) never share cache
/// entries. Folded into every cache key by `DirectoryCacheStore`, `JSONCacheStore` and the preview
/// cache, so switching the active account transparently reads that account's own cache instead of
/// the previous one's: no wipe, both accounts' caches survive a switch.
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

    /// Removes one account's preview and raw download slots from `Library/Caches/PreviewCache`.
    public static func clearPreviewCache(scope: String) {
        FilesService.clearPreviewCache(scope: scope)
    }

    static let prefixByteCount = 8
    static let hexDigitsPerByte = 2
    static let prefixSeparator: Character = "-"

    /// `name` carrying the active account's prefix, for cache files that are not keyed by account
    /// themselves (thumbnails), so `clearPreviewCache(scope:)` can remove just that account's.
    public static func scopedFileName(_ name: String, scope: String = CacheAccountScope.current) -> String {
        "\(filePrefix(for: scope))\(prefixSeparator)\(name)"
    }

    /// Stable filename prefix for one account's cache files, so a single account's entries can be
    /// removed without touching another's.
    static func filePrefix(for scope: String) -> String {
        SHA256.hash(data: Data(scope.utf8)).prefix(prefixByteCount).map { String(format: "%02x", $0) }.joined()
    }
}
