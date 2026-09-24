import Foundation

/// One file operation that ⌘Z can reverse, kept app wide (shared in memory under `sharedKey`,
/// cleared on every session boundary with the clipboard). Only operations with a server side
/// inverse are recorded; a delete has none (the server keeps no trash), so it is never here.
public struct FileUndoEntry: Equatable, Sendable {
    public static let sharedKey = "fileUndoStack"
    /// Older entries past this are dropped.
    public static let limit = 20

    public enum Kind: Equatable, Sendable {
        /// Copies, duplicates and new folders: undoing deletes them.
        case created([FileItem])
        /// Moves: undoing moves each item (at its new location) back to its old parent.
        case moved([MovedItem])
        /// A rename: undoing renames the item (at its new name) back.
        case renamed(FileItem, previousName: String)
    }

    public struct MovedItem: Equatable, Sendable {
        public let item: FileItem
        public let originalParent: String

        public init(item: FileItem, originalParent: String) {
            self.item = item
            self.originalParent = originalParent
        }
    }

    public let kind: Kind

    public init(_ kind: Kind) {
        self.kind = kind
    }
}

public extension [FileUndoEntry] {
    /// Pushes an entry, keeping only the most recent `FileUndoEntry.limit`.
    mutating func record(_ entry: FileUndoEntry) {
        append(entry)
        if count > FileUndoEntry.limit {
            removeFirst(count - FileUndoEntry.limit)
        }
    }
}
