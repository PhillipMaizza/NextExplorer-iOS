import Foundation

/// Case-insensitive subsequence matching: every character of `query`, in order (not
/// necessarily contiguous), must appear in `text`. Tolerates skipped/out-of-order typing
/// the way command-palette-style fuzzy finders do, rather than requiring an exact
/// contiguous substring.
enum FuzzyMatch {
    static func matches(query: String, in text: String) -> Bool {
        guard !query.isEmpty else { return true }
        var remaining = Substring(text.lowercased())
        for character in query.lowercased() {
            guard let index = remaining.firstIndex(of: character) else { return false }
            remaining = remaining[remaining.index(after: index)...]
        }
        return true
    }
}
