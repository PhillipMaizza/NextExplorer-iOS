import CoreModels
import Foundation

/// Process wide identifier of the account whose cached data the disk stores read and write, so
/// several signed in accounts (multiple servers, or two users on one server) never share cache
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
    private nonisolated(unsafe) static var accountWipes: [String: Int] = [:]
    private nonisolated(unsafe) static var everyAccountWipes = 0
    @TaskLocal private static var pinnedScope: String?

    /// The scope pinned to the running task by `withPinned`, else the process wide one.
    public static var current: String {
        pinnedScope ?? lock.withLock { _value }
    }

    /// Synchronous variant of `withPinned`.
    public static func withPinned<T>(_ scope: String, operation: () throws -> T) rethrows -> T {
        try $pinnedScope.withValue(scope, operation: operation)
    }

    /// Runs `operation` (and every child task it starts) under `scope`, so work that began for one
    /// account keeps reading and writing that account's caches after the active account changes.
    public nonisolated(nonsending) static func withPinned<T>(
        _ scope: String, operation: nonisolated(nonsending) () async throws -> T
    ) async rethrows -> T {
        try await $pinnedScope.withValue(scope, operation: operation)
    }

    public static func set(_ value: String) {
        lock.withLock { _value = value }
    }

    /// Changes whenever `scope`'s caches, or every account's, are wiped. A writer stamps its work when
    /// it starts and drops the write if the stamp moved, so nothing lands after the wipe.
    public static func wipeStamp(_ scope: String) -> Int {
        lock.withLock { accountWipes[scope, default: 0] + everyAccountWipes }
    }

    /// Call before wiping one account's caches.
    public static func markWiped(_ scope: String) {
        lock.withLock { accountWipes[scope, default: 0] += 1 }
    }

    /// Call before wiping every account's caches.
    public static func markEveryAccountWiped() {
        lock.withLock { everyAccountWipes += 1 }
    }

    /// Removes one account's preview and raw download slots from `Library/Caches/PreviewCache`.
    public static func clearPreviewCache(scope: String) {
        FilesService.clearPreviewCache(scope: scope)
    }

    /// Brings `Library/Caches/PreviewCache` back under its byte cap, oldest entries first, for
    /// writers that never trigger the eviction a preview download runs (thumbnails, PDF pages).
    public static func trimPreviewCache() {
        FilesService.evictPreviewCacheIfNeeded()
    }

    static let prefixByteCount = 8
    static let hexDigitsPerByte = 2
    static let prefixSeparator: Character = "-"

    /// The leading part of every file name written for `scope`, for removing just that account's.
    public static func namePrefix(for scope: String) -> String {
        "\(filePrefix(for: scope))\(prefixSeparator)"
    }

    /// `name` carrying the active account's prefix, for cache files that are not keyed by account
    /// themselves (thumbnails), so `clearPreviewCache(scope:)` can remove just that account's.
    public static func scopedFileName(_ name: String, scope: String = CacheAccountScope.current) -> String {
        "\(namePrefix(for: scope))\(name)"
    }

    /// Stable filename prefix for one account's cache files, so a single account's entries can be
    /// removed without touching another's.
    static func filePrefix(for scope: String) -> String {
        scope.sha256Hex(byteCount: prefixByteCount)
    }
}
