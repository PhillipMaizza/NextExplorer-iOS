import CoreModels
import FolderPickerFeature
import Localization

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

    static func takenMessage(
        _ name: String,
        in items: some Collection<FileItem>,
        except id: FileItem.ID? = nil
    ) -> String? {
        items.contains { $0.name == name && $0.id != id } ? L10n.Browse.transferConflictMessageOne(name) : nil
    }
}
