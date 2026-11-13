import Foundation

/// A typed search query as `GET /api/search` reads it (`backend/src/routes/search.js`): trimmed,
/// and searchable only from `MIN_TERM_LENGTH` characters as JavaScript counts them (UTF16 code
/// units), so the app asks exactly when the server would answer and never sends a term it
/// refuses with 400.
public struct SearchTerm: Equatable, Sendable {
    public let text: String

    public init(_ query: String) {
        text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isEmpty: Bool {
        text.isEmpty
    }

    /// Long enough for the server to search.
    public var isSearchable: Bool {
        text.utf16.count >= FilesClient.minimumSearchTermLength
    }

    /// Typed, but too short for the server to search.
    public var isTooShort: Bool {
        !isEmpty && !isSearchable
    }

    /// Whether `name` holds the term, case insensitively, as the server matches a plain term
    /// against a name. An empty term matches everything.
    public func matches(_ name: String) -> Bool {
        isEmpty || name.localizedCaseInsensitiveContains(text)
    }
}
