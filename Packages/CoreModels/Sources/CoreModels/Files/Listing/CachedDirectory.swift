import Foundation

/// A directory listing persisted to disk so it can be shown while the device is offline.
/// Mirrors the fields of `GET /api/browse/*` the client actually renders (`items` + `access`),
/// plus the time it was fetched so the UI can tell the user how stale the copy is.
///
/// `/api/browse` sends a strong `ETag`; the stored one rides back as `If-None-Match` on the
/// next fetch, so an unchanged directory answers `304` (served from this cache) and a changed
/// one returns `200` and replaces the entry. Offline, the cached entry is served as is.
public struct CachedDirectory: Codable, Equatable, Sendable {
    /// Bumped whenever the stored shape changes; a mismatch on read discards the entry rather
    /// than risking a decode against stale data.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public let path: String
    public let items: [FileItem]
    public let access: FileAccess
    public let fetchedAt: Date
    /// The server's `ETag` for this listing, sent back as `If-None-Match` on the next fetch so
    /// an unchanged directory answers `304` instead of re transferring. `nil` for entries
    /// written before the server exposed one, or when the response carried no `ETag`.
    public let etag: String?

    public init(
        path: String,
        items: [FileItem],
        access: FileAccess,
        fetchedAt: Date,
        etag: String? = nil,
        schemaVersion: Int = CachedDirectory.currentSchemaVersion
    ) {
        self.path = path
        self.items = items
        self.access = access
        self.fetchedAt = fetchedAt
        self.etag = etag
        self.schemaVersion = schemaVersion
    }
}
