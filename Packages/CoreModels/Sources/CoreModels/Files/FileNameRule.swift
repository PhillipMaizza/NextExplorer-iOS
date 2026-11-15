import Foundation

/// Client side mirror of the backend `ensureValidName` (`backend/src/utils/pathUtils.js`), so an
/// obviously bad file or folder name is caught before a round trip. The server stays the final
/// authority: a name that passes here can still be refused (a duplicate, a permission).
public enum FileNameRule {
    public enum Problem: Equatable, Sendable {
        /// `.` or `..`.
        case reserved
        /// A `/` or `\`.
        case separators
    }

    /// What is wrong with the trimmed name, or `nil` when it is acceptable. An empty name is `nil` on
    /// purpose: callers show that by disabling their confirm button, not with an error.
    public static func problem(forTrimmed name: String) -> Problem? {
        guard !name.isEmpty else { return nil }
        if name == "." || name == ".." {
            return .reserved
        }
        if name.contains("/") || name.contains("\\") {
            return .separators
        }
        return nil
    }

    public static func isAcceptable(trimmed name: String) -> Bool {
        !name.isEmpty && problem(forTrimmed: name) == nil
    }
}
