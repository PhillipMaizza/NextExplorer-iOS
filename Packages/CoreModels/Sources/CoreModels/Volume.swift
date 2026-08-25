/// Mirrors an entry from `GET /api/volumes` (`backend/src/routes/volumes.js`), the
/// top-level roots a user can browse into. `actualPath` only appears for per-user
/// volume assignments and isn't meaningful to the client.
public struct Volume: Codable, Equatable, Identifiable, Sendable {
    public let name: String
    public let path: String
    public let accessMode: String?

    public var id: String { path }

    public init(name: String, path: String, accessMode: String? = nil) {
        self.name = name
        self.path = path
        self.accessMode = accessMode
    }
}
