/// Mirrors one entry of `GET /api/search`'s `items` array (`backend/src/routes/search.js`).
/// `path` is the *parent directory* of the match, not the full path, same convention as
/// `FileItem`. `matchLine`/`matchLineNumber` are only present for content matches inside a file.
public struct SearchResultItem: Codable, Equatable, Identifiable, Sendable {
    public let name: String
    public let path: String
    public let kind: String
    public let matchLine: String?
    public let matchLineNumber: Int?

    public var isDirectory: Bool {
        kind == "dir"
    }

    public var id: String {
        path.isEmpty ? name : "\(path)/\(name)"
    }

    public init(
        name: String,
        path: String,
        kind: String,
        matchLine: String? = nil,
        matchLineNumber: Int? = nil
    ) {
        self.name = name
        self.path = path
        self.kind = kind
        self.matchLine = matchLine
        self.matchLineNumber = matchLineNumber
    }
}
