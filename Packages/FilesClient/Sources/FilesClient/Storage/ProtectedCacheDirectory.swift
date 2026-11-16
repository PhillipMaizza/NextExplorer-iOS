import Foundation

/// The disk hygiene every cache store shares: a folder excluded from backup and encrypted at rest
/// (`.completeUnlessOpen`, inherited by the files written into it), whose entries are evicted
/// oldest first past a count and a byte cap. Not thread safe on its own: each store serialises
/// access with its own lock. Every operation is best effort and never throws.
public struct ProtectedCacheDirectory: Sendable {
    public let url: URL
    /// The extension of the entries the store writes; other files are never counted or evicted.
    public let fileExtension: String

    public struct Entry: Sendable {
        public let url: URL
        public let modified: Date
        public let size: Int64
    }

    /// Running totals of the entries, so a write checks the caps without listing the folder.
    /// `nil` until the first scan, and again after anything removes entries in bulk.
    /// `@unchecked Sendable`: only touched under the owning store's lock.
    private final class Usage: @unchecked Sendable {
        var totals: (entries: Int, bytes: Int64)?
    }

    private let usage = Usage()

    /// Creates `name` under `base` (Application Support when `nil`); `nil` when it cannot be made.
    public init?(name: String, base: URL? = nil, fileExtension: String) {
        let fileManager = FileManager.default
        let root: URL
        if let base {
            root = base
        } else if let appSupport = try? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) {
            root = appSupport
        } else {
            return nil
        }
        var url = root.appendingPathComponent(name, isDirectory: true)
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? url.setResourceValues(resourceValues)
        try? fileManager.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path)
        self.url = url
        self.fileExtension = fileExtension
    }

    /// The store's entries, oldest written first.
    public func entriesByAge() -> [Entry] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys))) ??
            []
        return urls
            .filter { $0.pathExtension == fileExtension }
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

    public func totalSizeBytes() -> Int64 {
        entriesByAge().reduce(0) { $0 + $1.size }
    }

    /// Writes one entry atomically, then evicts only when the running totals cross a cap: the
    /// folder is listed on the first write and when it is full, not on every write.
    public func write(_ data: Data, to fileURL: URL, maxEntries: Int, maxTotalBytes: Int64) throws {
        let previousSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
        try data.write(to: fileURL, options: .atomic)
        guard let totals = usage.totals else {
            evict(maxEntries: maxEntries, maxTotalBytes: maxTotalBytes)
            return
        }
        let entries = totals.entries + (previousSize == nil ? 1 : 0)
        let bytes = totals.bytes + Int64(data.count) - (previousSize ?? 0)
        usage.totals = (entries, bytes)
        if entries > maxEntries || bytes > maxTotalBytes {
            evict(maxEntries: maxEntries, maxTotalBytes: maxTotalBytes)
        }
    }

    /// Removes the oldest entries until at most `maxEntries` remain and they fit `maxTotalBytes`.
    public func evict(maxEntries: Int, maxTotalBytes: Int64) {
        let entries = entriesByAge()
        var totalBytes = entries.reduce(0) { $0 + $1.size }
        var index = 0
        while index < entries.count, entries.count - index > maxEntries || totalBytes > maxTotalBytes {
            try? FileManager.default.removeItem(at: entries[index].url)
            totalBytes -= entries[index].size
            index += 1
        }
        usage.totals = (entries.count - index, totalBytes)
    }

    /// Removes everything in the folder.
    public func removeAll() {
        let contents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        for item in contents {
            try? FileManager.default.removeItem(at: item)
        }
        usage.totals = nil
    }

    /// Removes the entries whose file name starts with `prefix` (one account's scope).
    public func removeEntries(withPrefix prefix: String) {
        for entry in entriesByAge() where entry.url.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: entry.url)
        }
        usage.totals = nil
    }
}
