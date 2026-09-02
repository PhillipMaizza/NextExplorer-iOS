import Foundation

/// Case-insensitive substring matching, mirroring the backend search
/// (`backend/src/routes/search.js`, `name.toLowerCase().includes(query.toLowerCase())`) so a
/// client side filter (Browse "This Folder", Favorites, Shared, Downloads) matches exactly what a
/// server side "Everywhere" search would return for the same names. A contiguous run, not a
/// scattered subsequence: "abc" matches "xabcy" but not "a_b_c".
enum SearchMatch {
    static func matches(query: String, in text: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        return text.localizedCaseInsensitiveContains(trimmed)
    }
}
