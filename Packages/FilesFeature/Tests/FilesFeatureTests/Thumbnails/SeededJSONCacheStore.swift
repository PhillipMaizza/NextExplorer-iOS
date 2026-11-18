import FilesClient
import Foundation

extension JSONCacheStore {
    /// A cache that holds one saved entry, stamped with `fetchedAt` the way a real store stamps the
    /// write time, so a test can assert the offline "saved copy" date without reading the clock.
    static func seeded(_ value: some Encodable, forKey key: String, fetchedAt: Date) throws -> JSONCacheStore {
        let payload = try CachedPayload(data: JSONEncoder().encode(value), fetchedAt: fetchedAt)
        return JSONCacheStore(
            read: { $0 == key ? payload : nil },
            write: { _, _ in },
            remove: { _ in },
            clearAll: {},
            totalSizeBytes: { 0 }
        )
    }
}
