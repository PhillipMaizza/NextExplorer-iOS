import CoreModels
import Foundation

/// One shared item's name in the share sheet: what it came with and what the user typed. Only the part
/// before the extension is edited; the extension stays as the item had it.
public struct EditableItemName: Equatable, Sendable {
    public let original: SharedItemName
    public var text: String

    public init(_ original: SharedItemName) {
        self.original = original
        text = original.base
    }

    var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Changed from the name the item came with, so it uploads under the new one.
    var isEdited: Bool {
        trimmed != original.base
    }

    /// Why the typed name cannot be used; `nil` while it is fine or empty (an empty name only holds
    /// the Upload button back).
    public var problem: FileNameRule.Problem? {
        FileNameRule.problem(forTrimmed: trimmed)
    }

    var isAcceptable: Bool {
        FileNameRule.isAcceptable(trimmed: trimmed)
    }
}
