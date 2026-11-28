import Foundation

public enum FileNameRule {
    public enum Problem: Equatable, Sendable {
        /// `.`, `..`, the trash zone's `.nextexplorer`, or a name holding a NUL.
        case reserved
        /// A `/` or `\`.
        case separators
    }

    /// What is wrong with the trimmed name, or `nil` when it is acceptable. An empty name is `nil` on
    /// purpose: callers show that by disabling their confirm button, not with an error.
    public static func problem(forTrimmed name: String) -> Problem? {
        guard !name.isEmpty else { return nil }
        if reservedNames.contains(name) || name.contains("\0") {
            return .reserved
        }
        if name.contains("/") || name.contains("\\") {
            return .separators
        }
        return nil
    }

    private static let reservedNames: Set<String> = [".", "..", ".nextexplorer"]

    public static func isAcceptable(trimmed name: String) -> Bool {
        !name.isEmpty && problem(forTrimmed: name) == nil
    }
}
