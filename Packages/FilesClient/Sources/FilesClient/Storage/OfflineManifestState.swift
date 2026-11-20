import Foundation

/// Each account's pinned roots and run markers, kept in memory once read, so a reducer asking for
/// them never waits on the disk. A change lands in memory at once and is written behind it on one
/// serial queue, in the order the changes were made.
final class OfflineManifestState: @unchecked Sendable {
    struct Entry {
        var roots: [OfflinePinnedRoot]?
        var isInterrupted: Bool?
        var lastSync: Date??
    }

    static let shared = OfflineManifestState()

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private let writes = DispatchQueue(label: "OfflineManifestState.writes", qos: .utility)

    /// The cached value, or what `load` reads from disk the first time a scope is asked.
    /// shortcut: that first read per scope still runs on the calling thread; preload at account
    /// activation if it ever shows up in a trace.
    func value<Value>(_ key: WritableKeyPath<Entry, Value?>, scope: String, load: () -> Value) -> Value {
        lock.withLock {
            if let cached = entries[scope, default: Entry()][keyPath: key] {
                return cached
            }
            let loaded = load()
            entries[scope, default: Entry()][keyPath: key] = loaded
            return loaded
        }
    }

    /// Records `value` and queues `persist` while holding the lock, so disk order matches memory order.
    func set<Value>(
        _ key: WritableKeyPath<Entry, Value?>,
        _ value: Value,
        scope: String,
        persist: @escaping @Sendable () -> Void
    ) {
        lock.withLock {
            entries[scope, default: Entry()][keyPath: key] = value
            writes.async(execute: persist)
        }
    }

    /// Runs `remove` after every queued write, so none lands after it, and forgets the cached values
    /// of `scope`, or of every scope when nil, under the same lock so no read sees them in between.
    /// A queued `persist` must never take `lock`, or this would deadlock.
    func remove(scope: String?, _ remove: () -> Void) {
        lock.withLock {
            writes.sync(execute: remove)
            if let scope {
                entries[scope] = nil
            } else {
                entries = [:]
            }
        }
    }

    /// Waits for every queued write.
    func flush() {
        writes.sync {}
    }
}
