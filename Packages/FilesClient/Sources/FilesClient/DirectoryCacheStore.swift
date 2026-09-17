import CoreModels
import CryptoKit
import Dependencies
import Foundation

/// On-disk cache of directory listings, one JSON file per `(server, path)`, so browsing keeps
/// working offline. Every operation is best effort: a read miss, a write failure or a corrupt
/// entry must never surface as a browsing error, so nothing here throws.
///
/// Entries live under `Application Support` (not `Caches`, which the OS purges under pressure
/// exactly when an offline user needs them) and are held under a size / count cap with
/// least-recently-written eviction.
public struct DirectoryCacheStore: Sendable {
    public var read: @Sendable (_ serverURL: URL, _ path: String) -> CachedDirectory?
    /// When `path` was last written, from the entry's file timestamp: a cheap freshness probe
    /// (one `stat`, no decode) for deciding whether a background prefetch is worth doing.
    public var lastWrittenAt: @Sendable (_ serverURL: URL, _ path: String) -> Date?
    /// Stores `result` as the listing for `path`, stamped `fetchedAt` and tagged `etag`, then
    /// evicts the oldest entries if the cache is over its cap.
    public var write: @Sendable (
        _ serverURL: URL, _ path: String, _ result: BrowseResult, _ etag: String?, _ fetchedAt: Date
    ) -> Void
    /// Refreshes only the freshness stamp of an existing entry after a `304 Not Modified`,
    /// and only when the stored `etag` still equals `expectedETag`. This is a compare and set:
    /// it never rewrites the items, so a stale in flight `304` handler cannot clobber a newer
    /// listing a concurrent browse just wrote (the etag will no longer match).
    public var touch: @Sendable (
        _ serverURL: URL, _ path: String, _ expectedETag: String?, _ fetchedAt: Date
    ) -> Void
    public var remove: @Sendable (_ serverURL: URL, _ path: String) -> Void
    /// Drops every entry, e.g. from a "Clear offline cache" settings action or on sign out.
    public var clearAll: @Sendable () -> Void
    /// Total bytes currently on disk, for a settings display.
    public var totalSizeBytes: @Sendable () -> Int64

    public init(
        read: @escaping @Sendable (URL, String) -> CachedDirectory?,
        lastWrittenAt: @escaping @Sendable (URL, String) -> Date?,
        write: @escaping @Sendable (URL, String, BrowseResult, String?, Date) -> Void,
        touch: @escaping @Sendable (URL, String, String?, Date) -> Void,
        remove: @escaping @Sendable (URL, String) -> Void,
        clearAll: @escaping @Sendable () -> Void,
        totalSizeBytes: @escaping @Sendable () -> Int64
    ) {
        self.read = read
        self.lastWrittenAt = lastWrittenAt
        self.write = write
        self.touch = touch
        self.remove = remove
        self.clearAll = clearAll
        self.totalSizeBytes = totalSizeBytes
    }
}

public extension DirectoryCacheStore {
    func read(serverURL: URL, path: String) -> CachedDirectory? {
        read(serverURL, path)
    }

    func lastWrittenAt(serverURL: URL, path: String) -> Date? {
        lastWrittenAt(serverURL, path)
    }

    func write(serverURL: URL, path: String, result: BrowseResult, etag: String?, fetchedAt: Date) {
        write(serverURL, path, result, etag, fetchedAt)
    }

    func touch(serverURL: URL, path: String, expectedETag: String?, fetchedAt: Date) {
        touch(serverURL, path, expectedETag, fetchedAt)
    }

    func remove(serverURL: URL, path: String) {
        remove(serverURL, path)
    }
}

extension DirectoryCacheStore: DependencyKey {
    private enum Constants {
        static let directoryName = "DirectoryCache"
        static let fileExtension = "json"
        static let maxEntries = 4000
        static let maxTotalBytes: Int64 = 40 * 1024 * 1024
        /// A single directory's JSON is capped so `read` stays a cheap synchronous decode on
        /// the browse path. ~2 MB is roughly 12k entries; a folder larger than that simply
        /// isn't cached for offline use (the server response itself is capped at 32 MB, and a
        /// listing that size is not meaningfully browsable offline anyway).
        static let maxEntryBytes = 2 * 1024 * 1024
        /// A cheap upper bound checked before encoding, so a pathologically large listing
        /// never pays the cost of a full `JSONEncoder` pass just to be rejected on byte count.
        /// Deliberately generous relative to `maxEntryBytes`; the byte check is the real gate.
        static let maxEntryItems = 20_000
    }

    /// Serialises filesystem access so concurrent browse effects can't race on the same file
    /// or on eviction. The work itself is fast (KB-scale JSON), so a lock is simpler than a
    /// queue and keeps the API synchronous.
    final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private let fileManager = FileManager.default
        private let rootOverride: URL?
        private let maxEntries: Int
        private let maxTotalBytes: Int64

        init(
            rootOverride: URL? = nil,
            maxEntries: Int = Constants.maxEntries,
            maxTotalBytes: Int64 = Constants.maxTotalBytes
        ) {
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
            var url = base.appendingPathComponent(Constants.directoryName, isDirectory: true)
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                return nil
            }
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? url.setResourceValues(resourceValues)
            // Directory listings carry every file/folder name, path and access rule; keep them
            // encrypted at rest. New JSON files written into this directory inherit the class.
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path
            )
            return url
        }()

        private func fileURL(serverURL: URL, path: String) -> URL? {
            guard let directory else { return nil }
            let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            // The active account is folded into the key so several signed-in accounts keep
            // separate entries and a switch reads the right account's cache without a wipe.
            let key = "\(CacheAccountScope.current)\n\(serverURL.absoluteString)\n\(normalizedPath)"
            let digest = SHA256.hash(data: Data(key.utf8))
            let name = digest.map { String(format: "%02x", $0) }.joined()
            return directory.appendingPathComponent(name).appendingPathExtension(Constants.fileExtension)
        }

        func read(serverURL: URL, path: String) -> CachedDirectory? {
            lock.lock()
            defer { lock.unlock() }
            guard
                let fileURL = fileURL(serverURL: serverURL, path: path),
                let data = try? Data(contentsOf: fileURL),
                let cached = try? JSONDecoder.cache.decode(CachedDirectory.self, from: data)
            else { return nil }
            guard cached.schemaVersion == CachedDirectory.currentSchemaVersion else {
                try? fileManager.removeItem(at: fileURL)
                return nil
            }
            return cached
        }

        func lastWrittenAt(serverURL: URL, path: String) -> Date? {
            lock.lock()
            defer { lock.unlock() }
            guard let fileURL = fileURL(serverURL: serverURL, path: path) else { return nil }
            return try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }

        func write(serverURL: URL, path: String, result: BrowseResult, etag: String?, fetchedAt: Date) {
            lock.lock()
            defer { lock.unlock() }
            guard let fileURL = fileURL(serverURL: serverURL, path: path) else { return }
            // A folder too large to cache cheaply: drop any earlier copy so a stale listing
            // can't linger, and skip the write. Checked on item count first (free) then on
            // encoded size (the real gate, since name lengths vary).
            guard result.items.count <= Constants.maxEntryItems else {
                try? fileManager.removeItem(at: fileURL)
                return
            }
            let cached = CachedDirectory(
                path: result.path,
                items: result.items,
                access: result.access,
                fetchedAt: fetchedAt,
                etag: etag
            )
            guard let data = try? JSONEncoder.cache.encode(cached) else { return }
            guard data.count <= Constants.maxEntryBytes else {
                try? fileManager.removeItem(at: fileURL)
                return
            }
            try? data.write(to: fileURL, options: .atomic)
            evictIfNeeded()
        }

        func touch(serverURL: URL, path: String, expectedETag: String?, fetchedAt: Date) {
            lock.lock()
            defer { lock.unlock() }
            guard
                let fileURL = fileURL(serverURL: serverURL, path: path),
                let data = try? Data(contentsOf: fileURL),
                let current = try? JSONDecoder.cache.decode(CachedDirectory.self, from: data),
                current.etag == expectedETag
            else { return }
            let refreshed = CachedDirectory(
                path: current.path,
                items: current.items,
                access: current.access,
                fetchedAt: fetchedAt,
                etag: current.etag
            )
            guard let encoded = try? JSONEncoder.cache.encode(refreshed) else { return }
            try? encoded.write(to: fileURL, options: .atomic)
        }

        func remove(serverURL: URL, path: String) {
            lock.lock()
            defer { lock.unlock() }
            guard let fileURL = fileURL(serverURL: serverURL, path: path) else { return }
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
            let urls = (try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: Array(keys)
            )) ?? []
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

        func asStore() -> DirectoryCacheStore {
            DirectoryCacheStore(
                read: { self.read(serverURL: $0, path: $1) },
                lastWrittenAt: { self.lastWrittenAt(serverURL: $0, path: $1) },
                write: { self.write(serverURL: $0, path: $1, result: $2, etag: $3, fetchedAt: $4) },
                touch: { self.touch(serverURL: $0, path: $1, expectedETag: $2, fetchedAt: $3) },
                remove: { self.remove(serverURL: $0, path: $1) },
                clearAll: { self.clearAll() },
                totalSizeBytes: { self.totalSizeBytes() }
            )
        }
    }

    /// A real on-disk store rooted under `rootDirectory` instead of Application Support, so
    /// tests can exercise persistence and eviction in a temp directory.
    static func onDisk(
        rootDirectory: URL? = nil,
        maxEntries: Int = Constants.maxEntries,
        maxTotalBytes: Int64 = Constants.maxTotalBytes
    ) -> DirectoryCacheStore {
        let storage = Storage(rootOverride: rootDirectory, maxEntries: maxEntries, maxTotalBytes: maxTotalBytes)
        return storage.asStore()
    }

    public static let liveValue: DirectoryCacheStore = Storage().asStore()

    public static let previewValue = DirectoryCacheStore.testValue

    /// A store that never returns cached content and drops every write. `lastWrittenAt`
    /// reports "just now" so a background prefetch treats everything as fresh and stays out
    /// of a test's way; tests that exercise caching or prefetch override the closures they
    /// care about.
    public static let testValue = DirectoryCacheStore(
        read: { _, _ in nil },
        lastWrittenAt: { _, _ in Date() },
        write: { _, _, _, _, _ in },
        touch: { _, _, _, _ in },
        remove: { _, _ in },
        clearAll: {},
        totalSizeBytes: { 0 }
    )

    /// An in-memory store for tests: reads see prior writes, keyed on `(server, normalized path)`.
    public static func inMemory() -> DirectoryCacheStore {
        let box = InMemoryBox()
        return DirectoryCacheStore(
            read: { box.read(serverURL: $0, path: $1) },
            lastWrittenAt: { box.read(serverURL: $0, path: $1)?.fetchedAt },
            write: { box.write(serverURL: $0, path: $1, result: $2, etag: $3, fetchedAt: $4) },
            touch: { box.touch(serverURL: $0, path: $1, expectedETag: $2, fetchedAt: $3) },
            remove: { box.remove(serverURL: $0, path: $1) },
            clearAll: { box.clearAll() },
            totalSizeBytes: { 0 }
        )
    }

    private final class InMemoryBox: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String: CachedDirectory] = [:]

        private func key(_ serverURL: URL, _ path: String) -> String {
            "\(serverURL.absoluteString)\n\(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
        }

        func read(serverURL: URL, path: String) -> CachedDirectory? {
            lock.lock(); defer { lock.unlock() }
            return entries[key(serverURL, path)]
        }

        func write(serverURL: URL, path: String, result: BrowseResult, etag: String?, fetchedAt: Date) {
            lock.lock(); defer { lock.unlock() }
            entries[key(serverURL, path)] = CachedDirectory(
                path: result.path, items: result.items, access: result.access, fetchedAt: fetchedAt, etag: etag
            )
        }

        func touch(serverURL: URL, path: String, expectedETag: String?, fetchedAt: Date) {
            lock.lock(); defer { lock.unlock() }
            let entryKey = key(serverURL, path)
            guard let current = entries[entryKey], current.etag == expectedETag else { return }
            entries[entryKey] = CachedDirectory(
                path: current.path, items: current.items, access: current.access, fetchedAt: fetchedAt, etag: current.etag
            )
        }

        func remove(serverURL: URL, path: String) {
            lock.lock(); defer { lock.unlock() }
            entries[key(serverURL, path)] = nil
        }

        func clearAll() {
            lock.lock(); defer { lock.unlock() }
            entries.removeAll()
        }
    }
}

public extension DependencyValues {
    var directoryCacheStore: DirectoryCacheStore {
        get { self[DirectoryCacheStore.self] }
        set { self[DirectoryCacheStore.self] = newValue }
    }
}

private extension JSONDecoder {
    static var cache: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var cache: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
