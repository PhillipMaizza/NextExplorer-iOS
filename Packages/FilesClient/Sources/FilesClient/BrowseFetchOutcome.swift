import CoreModels

/// The result of a conditional `GET /api/browse/*`.
enum BrowseFetchOutcome: Sendable {
    /// `200` — a fresh listing, plus the server's `ETag` for it (absent if the server sent none).
    case modified(BrowseResult, etag: String?)
    /// `304` — the directory is unchanged since the `If-None-Match` the client sent. The cached
    /// listing stands; `etag` echoes it back when the server included it on the `304`.
    case notModified(etag: String?)
}
