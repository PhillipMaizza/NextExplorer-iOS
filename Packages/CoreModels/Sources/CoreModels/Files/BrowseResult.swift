/// Mirrors the response body of `GET /api/browse/*` (`backend/src/routes/browse.js`).
/// The route also returns `current`/`shareInfo`, unused by the client so far.
public struct BrowseResult: Codable, Equatable, Sendable {
    public let items: [FileItem]
    public let access: FileAccess
    public let path: String

    public init(items: [FileItem], access: FileAccess, path: String) {
        self.items = items
        self.access = access
        self.path = path
    }
}
