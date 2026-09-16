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

    /// Whether pasting into `directoryPath` is valid. Rejected for: the volume root; a folder
    /// without write access; a folder equal to a staged item or nested inside one (the server
    /// fails a copy *or* move into a subdirectory of itself with `EINVAL`); and, for a `move`
    /// only, a folder a staged item already sits directly in (a server no-op).
    public func canPaste(into directoryPath: String, canWrite: Bool) -> Bool {
        guard !directoryPath.isEmpty, canWrite else { return false }
        for source in sourceItemPaths where directoryPath == source || directoryPath.hasPrefix("\(source)/") {
            return false
        }
        if operation == .move, sourceParentPaths.contains(directoryPath) {
            return false
        }
        return true
    }
}
