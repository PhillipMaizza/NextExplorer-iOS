import CoreModels
import Foundation

/// A typed search query as `GET /api/search` reads it (`backend/src/routes/search.js`,
/// `backend/src/utils/searchTerm.js`): trimmed, and searchable only from `MIN_TERM_LENGTH`
/// characters as JavaScript counts them (UTF16 code units), so the app asks exactly when the server
/// would answer and never sends a term it refuses with 400.
///
/// Matching and ranking mirror the server too, so what the app finds on its own (the instant
/// matches, a filter over a list) agrees with what the server answers. A term holding `*` or `?` is
/// a shape for names, not text: `*.pdf` names every PDF. One holding `/` as well is a shape for a
/// path below the search's folder, which no folder answers. Both sides are compared in the composed
/// form (NFC), since a name written by a Mac and one typed on a phone can spell `é` differently.
public struct SearchTerm: Equatable, Sendable {
    public let text: String
    /// The term folded the way names are folded before comparing: composed and lowercased.
    private let needle: String
    private let glob: Glob?

    public init(_ query: String) {
        text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        needle = Self.folded(text)
        glob = Glob(text)
    }

    public static func == (lhs: SearchTerm, rhs: SearchTerm) -> Bool {
        lhs.text == rhs.text
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

    /// A shape for names (`*` or `?`) rather than text to look for.
    public var isGlob: Bool {
        glob != nil
    }

    /// Whether a name answers the term: holds it, or fits its shape. A path shape fits no single
    /// name. An empty term matches everything.
    public func matches(_ name: String) -> Bool {
        guard !isEmpty else { return true }
        guard let glob else { return Self.folded(name).contains(needle) }
        return !glob.isPathPattern && glob.fits(name)
    }

    /// Whether an item answers the term, as the server decides it: a folder by its name, a file by
    /// its name or, for a path shape, by `relativePath` (its path below the search's folder).
    public func matches(name: String, relativePath: String, isDirectory: Bool) -> Bool {
        guard !isDirectory, let glob, glob.isPathPattern else { return matches(name) }
        return glob.fits(relativePath)
    }

    /// How well a name answers: 0 the whole name, 1 a name that begins with the term, 2 one that
    /// holds it somewhere. Every name a shape fits is equally close.
    public func rank(_ name: String) -> Int {
        guard glob == nil else { return 0 }
        let folded = Self.folded(name)
        if folded == needle {
            return 0
        }
        return folded.hasPrefix(needle) ? 1 : 2
    }

    /// Results in the server's order: what was found by its name first, closest first (rank, then
    /// shorter, then by name and path), then what was found by its contents, by path. Instant
    /// matches carry no match and count as names. Used where the app builds or merges a list itself.
    public func ranked(_ results: [SearchResultItem]) -> [SearchResultItem] {
        let byName = results.filter(Self.isNameHit)
            .map { (result: $0, rank: rank($0.name), length: $0.name.utf16.count) }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank {
                    return lhs.rank < rhs.rank
                }
                if lhs.length != rhs.length {
                    return lhs.length < rhs.length
                }
                let byName = lhs.result.name.localizedCompare(rhs.result.name)
                guard byName == .orderedSame else { return byName == .orderedAscending }
                return lhs.result.id.localizedCompare(rhs.result.id) == .orderedAscending
            }
            .map(\.result)
        let byContents = results.filter { !Self.isNameHit($0) }
            .sorted { $0.id.localizedCompare($1.id) == .orderedAscending }
        return byName + byContents
    }

    private static func isNameHit(_ result: SearchResultItem) -> Bool {
        result.isNameMatch ?? (result.matchLine == nil && result.isContentMatch != true)
    }

    private static func folded(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.lowercased()
    }
}

/// A term with `*` (any run) or `?` (any one character), matched against a whole name, or against a
/// whole path when it holds `/`, case insensitively. Every other character is itself: `a+b` is three
/// characters, not an expression. The expression is compiled on the first match, once per term:
/// computed state builds terms often, and most are never matched against anything.
private final class Glob: @unchecked Sendable {
    let isPathPattern: Bool
    private let pattern: String
    private let lock = NSLock()
    private var compiled: NSRegularExpression??

    init?(_ text: String) {
        guard text.contains(where: { $0 == "*" || $0 == "?" }) else { return nil }
        pattern = text.precomposedStringWithCanonicalMapping.map { character -> String in
            switch character {
            case "*": ".*"
            case "?": "."
            default: NSRegularExpression.escapedPattern(for: String(character))
            }
        }.joined()
        isPathPattern = text.contains("/")
    }

    private var expression: NSRegularExpression? {
        lock.withLock {
            if let compiled {
                return compiled
            }
            let made = try? NSRegularExpression(
                pattern: "^\(pattern)$",
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            )
            compiled = .some(made)
            return made
        }
    }

    func fits(_ value: String) -> Bool {
        guard let expression else { return false }
        let composed = value.precomposedStringWithCanonicalMapping
        let range = NSRange(composed.startIndex..., in: composed)
        return expression.firstMatch(in: composed, range: range) != nil
    }
}
