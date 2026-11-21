import Foundation

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
