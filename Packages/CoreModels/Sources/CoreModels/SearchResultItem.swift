/// Mirrors one entry of `GET /api/search`'s `items` array (`backend/src/routes/search.js`).
/// `path` is the *parent directory* of the match, not the full path, same convention as
/// `FileItem`. `matchLine`/`matchLineNumber` are only present for content matches inside a file.
/// `isNameMatch`/`isContentMatch` are the server's `matchedName`/`matchedContent`, absent from
/// servers that predate them.
public struct SearchResultItem: Codable, Equatable, Identifiable, Sendable {
    public let name: String
    public let path: String
    public let kind: String
    public let matchLine: String?
    public let matchLineNumber: Int?
    public let isNameMatch: Bool?
    public let isContentMatch: Bool?

    private enum CodingKeys: String, CodingKey {
        case name, path, kind, matchLine, matchLineNumber
        case isNameMatch = "matchedName"
        case isContentMatch = "matchedContent"
    }

    public var isDirectory: Bool {
        kind == "dir"
    }

    public var id: String {
        path.isEmpty ? name : "\(path)/\(name)"
    }

    /// Which half of the search found it, as the web client labels it (`matchLabelKey` in
    /// `frontend/src/utils/searchMatch.js`). `nil` when the server said neither.
    public var matchKind: SearchMatchKind? {
        switch (isNameMatch == true, isContentMatch == true || matchLine != nil) {
        case (true, true): .both
        case (true, false): .name
        case (false, true): .contents
        case (false, false): nil
        }
    }

    public init(
        name: String,
        path: String,
        kind: String,
        matchLine: String? = nil,
        matchLineNumber: Int? = nil,
        isNameMatch: Bool? = nil,
        isContentMatch: Bool? = nil
    ) {
        self.name = name
        self.path = path
        self.kind = kind
        self.matchLine = matchLine
        self.matchLineNumber = matchLineNumber
        self.isNameMatch = isNameMatch
        self.isContentMatch = isContentMatch
    }
}

public enum SearchMatchKind: Equatable, Sendable {
    case name, contents, both
}

/// One answer from `GET /api/search`: the ranked results plus the two ways it can fall short
/// of the whole truth (`res.json({ items, truncated, limit, complete })`). The server orders
/// `items` (names first, closest first, then contents by relevance), so callers keep that order.
public struct SearchPage: Equatable, Sendable, ExpressibleByArrayLiteral {
    public var items: [SearchResultItem]
    /// The search hit its time budget before looking everywhere.
    public var isTruncated: Bool
    /// The page is full: there may be more past `limit`.
    public var isComplete: Bool
    public var limit: Int?

    public init(items: [SearchResultItem], isTruncated: Bool = false, isComplete: Bool = true, limit: Int? = nil) {
        self.items = items
        self.isTruncated = isTruncated
        self.isComplete = isComplete
        self.limit = limit
    }

    public init(arrayLiteral elements: SearchResultItem...) {
        self.init(items: elements)
    }
}
