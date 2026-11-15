import CoreModels
import FolderPickerFeature

/// `FileNameRule` with its reasons worded for the user. Validates the trimmed name, which is what the
/// reducer actually sends.
enum FileNameValidation {
    /// A readable reason the trimmed name is invalid, or `nil` when it is acceptable (an empty name
    /// included, see `FileNameRule.problem(forTrimmed:)`).
    static func errorMessage(forTrimmed name: String) -> String? {
        FileNameRule.problem(forTrimmed: name)?.message
    }

    static func isAcceptable(trimmed name: String) -> Bool {
        FileNameRule.isAcceptable(trimmed: name)
    }
}
