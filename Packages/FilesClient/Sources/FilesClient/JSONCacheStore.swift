import CryptoKit
import Dependencies
import Foundation

/// A cached payload plus the moment it was fetched, so a feature can show a "saved copy · 5m ago"
/// banner while offline.
public struct CachedPayload: Equatable, Sendable {
    public let data: Data
    public let fetchedAt: Date

    public init(data: Data, fetchedAt: Date) {
        self.data = data
        self.fetchedAt = fetchedAt
    }
}

/// A small keyed disk cache for the list endpoints that have no directory of their own
/// (Favorites, Shared). Each caller owns its key namespace; the store only hashes the key, writes
/// the payload atomically, and evicts by age once it outgrows its caps. Every operation is best
/// effort: a miss, a write failure or a corrupt entry is swallowed so the caller falls back to
/// the network. Mirrors `DirectoryCacheStore`'s disk hygiene (encrypted at rest, excluded from
/// backup) since these payloads are the user's data too.
public struct JSONCacheStore: Sendable {
    public var read: @Sendable (_ key: String) -> CachedPayload?
    /// The store stamps `fetchedAt` itself (write time), so callers need no clock dependency.
    public var write: @Sendable (_ key: String, _ data: Data) -> Void
    public var remove: @Sendable (_ key: String) -> Void
    public var clearAll: @Sendable () -> Void
    public var totalSizeBytes: @Sendable () -> Int64

    public init(
        read: @escaping @Sendable (String) -> CachedPayload?,
        write: @escaping @Sendable (String, Data) -> Void,
        remove: @escaping @Sendable (String) -> Void,
        clearAll: @escaping @Sendable () -> Void,
        totalSizeBytes: @escaping @Sendable () -> Int64
    ) {
        self.read = read
        self.write = write
        self.remove = remove
        self.clearAll = clearAll
        self.totalSizeBytes = totalSizeBytes
    }

    public func read(key: String) -> CachedPayload? {
        read(key)
    }

    public func write(key: String, data: Data) {
        write(key, data)
    }

    public func remove(key: String) {
        remove(key)
    }
}

extension JSONCacheStore: DependencyKey {
    private struct Envelope: Codable {
        let fetchedAt: Double
        let payload: Data
    }

    private enum Constants {
        static let directoryName = "ListCache"
        static let fileExtension = "json"
        static let maxEntries = 200
        static let maxTotalBytes: Int64 = 8 * 1024 * 1024
        static let maxEntryBytes = 2 * 1024 * 1024
    }

    final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private let fileManager = FileManager.default
        private let rootOverride: URL?
        private let maxEntries: Int
        private let maxTotalBytes: Int64

        init(rootOverride: URL? = nil, maxEntries: Int = Constants.maxEntries, maxTotalBytes: Int64 = Constants.maxTotalBytes) {
            self.rootOverride = rootOverride
            self.maxEntries = maxEntries
            self.maxTotalBytes = maxTotalBytes
        }

        private lazy var directory: URL? = {
            let base: URL
            if let rootOverride {
                base = rootOverride
            } else if let appSupport = try? fileManager.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            ) {
                base = appSupport
            } else {
                return nil
            }
            let url = base.appendingPathComponent(Constants.directoryName, isDirectory: true)
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                return nil
            }
            var mutableURL = url
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? mutableURL.setResourceValues(resourceValues)
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path
            )
            return url
        }()

        private func fileURL(key: String) -> URL? {
            guard let directory else { return nil }
            // The caller's key (favorites, shares.byMe, ...) carries no server, so fold the active
            // account in: two servers' Favorites/Shared lists must not share one cache entry.
            let digest = SHA256.hash(data: Data("\(CacheAccountScope.current)\n\(key)".utf8))
            let name = digest.map { String(format: "%02x", $0) }.joined()
            return directory.appendingPathComponent(name).appendingPathExtension(Constants.fileExtension)
        }

        func read(key: String) -> CachedPayload? {
            lock.lock()
            defer { lock.unlock() }
            guard
                let fileURL = fileURL(key: key),
                let data = try? Data(contentsOf: fileURL),
                let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
            else { return nil }
            return CachedPayload(data: envelope.payload, fetchedAt: Date(timeIntervalSince1970: envelope.fetchedAt))
        }

        func write(key: String, data: Data) {
            lock.lock()
            defer { lock.unlock() }
            guard let fileURL = fileURL(key: key) else { return }
            let envelope = Envelope(fetchedAt: Date().timeIntervalSince1970, payload: data)
            guard let encoded = try? JSONEncoder().encode(envelope) else { return }
            guard encoded.count <= Constants.maxEntryBytes else {
                try? fileManager.removeItem(at: fileURL)
                return
            }
            try? encoded.write(to: fileURL, options: .atomic)
            evictIfNeeded()
        }

        func remove(key: String) {
            lock.lock()
            defer { lock.unlock() }
            guard let fileURL = fileURL(key: key) else { return }
            try? fileManager.removeItem(at: fileURL)
        }

        func clearAll() {
            lock.lock()
            defer { lock.unlock() }
            guard let directory else { return }
            let entries = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for entry in entries {
                try? fileManager.removeItem(at: entry)
            }
        }

        func totalSizeBytes() -> Int64 {
            lock.lock()
            defer { lock.unlock() }
            return entriesByAge().reduce(0) { $0 + $1.size }
        }

        private struct Entry {
            let url: URL
            let modified: Date
            let size: Int64
        }

        private func entriesByAge() -> [Entry] {
            guard let directory else { return [] }
            let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
            let urls = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))) ?? []
            return urls
                .filter { $0.pathExtension == Constants.fileExtension }
                .map { url in
                    let values = try? url.resourceValues(forKeys: keys)
                    return Entry(
                        url: url,
                        modified: values?.contentModificationDate ?? .distantPast,
                        size: Int64(values?.fileSize ?? 0)
                    )
                }
                .sorted { $0.modified < $1.modified }
        }

        private func evictIfNeeded() {
            let entries = entriesByAge()
            var totalBytes = entries.reduce(0) { $0 + $1.size }
            var index = 0
            while index < entries.count, entries.count - index > maxEntries || totalBytes > maxTotalBytes {
                try? fileManager.removeItem(at: entries[index].url)
                totalBytes -= entries[index].size
                index += 1
            }
        }

        func asStore() -> JSONCacheStore {
            JSONCacheStore(
                read: { self.read(key: $0) },
                write: { self.write(key: $0, data: $1) },
                remove: { self.remove(key: $0) },
                clearAll: { self.clearAll() },
                totalSizeBytes: { self.totalSizeBytes() }
            )
        }
    }

    /// A real on-disk store rooted under `rootDirectory` instead of Application Support, so tests
    /// can exercise persistence and eviction in a temp directory.
    static func onDisk(rootDirectory: URL? = nil, maxEntries: Int = Constants.maxEntries, maxTotalBytes: Int64 = Constants.maxTotalBytes) -> JSONCacheStore {
        Storage(rootOverride: rootDirectory, maxEntries: maxEntries, maxTotalBytes: maxTotalBytes).asStore()
    }

    public static let liveValue: JSONCacheStore = Storage().asStore()
    public static let previewValue = JSONCacheStore.testValue

    /// A store that never returns cached content and drops every write.
    public static let testValue = JSONCacheStore(
        read: { _ in nil },
        write: { _, _ in },
        remove: { _ in },
        clearAll: {},
        totalSizeBytes: { 0 }
    )

    /// An in-memory store for tests: reads see prior writes.
    public static func inMemory() -> JSONCacheStore {
        let box = InMemoryBox()
        return JSONCacheStore(
            read: { box.read(key: $0) },
            write: { box.write(key: $0, data: $1) },
            remove: { box.remove(key: $0) },
            clearAll: { box.clearAll() },
            totalSizeBytes: { 0 }
        )
    }

    private final class InMemoryBox: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String: CachedPayload] = [:]

        func read(key: String) -> CachedPayload? {
            lock.lock(); defer { lock.unlock() }
            return entries[key]
        }

        func write(key: String, data: Data) {
            lock.lock(); defer { lock.unlock() }
            entries[key] = CachedPayload(data: data, fetchedAt: Date())
        }

        func remove(key: String) {
            lock.lock(); defer { lock.unlock() }
            entries[key] = nil
        }

        func clearAll() {
            lock.lock(); defer { lock.unlock() }
            entries.removeAll()
        }
    }
}

public extension DependencyValues {
    var jsonCacheStore: JSONCacheStore {
        get { self[JSONCacheStore.self] }
        set { self[JSONCacheStore.self] = newValue }
    }
}
