/// The set of items staged for a `copy` or `move`, held app wide so the Paste action can
/// follow the user across every folder they navigate into. Persisted only in memory
/// (`@Shared(.inMemory(FileClipboard.sharedKey))`), never to disk.
public struct FileClipboard: Equatable, Sendable {
    /// Shared in memory key. One clipboard for the whole app; cleared on sign out.
    public static let sharedKey = "fileClipboard"

    public var items: [FileItem]
    public var operation: TransferOperation

    public init(items: [FileItem], operation: TransferOperation) {
        self.items = items
        self.operation = operation
    }

    /// The parent directories the staged items currently live in. A `move` into any of
    /// these is a no op the server skips, so the paste target check hides the action rather
    /// than round trip for nothing.
    public var sourceParentPaths: Set<String> {
        Set(items.map(\.path))
    }

    /// The staged items' own full paths.
    public var sourceItemPaths: Set<String> {
        Set(items.map(\.id))
    }

    public enum Refusal: Equatable, Sendable {
        case noFolder
        case noRights
        case intoItself
        case alreadyThere
    }

    public func refusal(into directoryPath: String, canReceive: Bool) -> Refusal? {
        guard !directoryPath.isEmpty else { return .noFolder }
        if sourceItemPaths.contains(where: { directoryPath == $0 || directoryPath.hasPrefix("\($0)/") }) {
            return .intoItself
        }
        if operation == .move, sourceParentPaths.contains(directoryPath) {
            return .alreadyThere
        }
        return canReceive ? nil : .noRights
    }

    public func canPaste(into directoryPath: String, canReceive: Bool) -> Bool {
        refusal(into: directoryPath, canReceive: canReceive) == nil
    }
}
