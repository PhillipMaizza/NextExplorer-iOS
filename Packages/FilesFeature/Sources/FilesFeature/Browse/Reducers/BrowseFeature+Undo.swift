import ComposableArchitecture
import CoreModels
import FilesClient
import FolderPickerFeature
import Foundation

extension BrowseFeature {
    /// A confirmed copy or move: show its outcome in this listing right away (the refresh that
    /// follows confirms it), and record how to undo it.
    func applyTransfer(_ state: inout State, outcome: TransferOutcome, sources: [FileItem]) {
        let destination = Self.trimmedPath(outcome.result.destination)
        let sourcesByID = Dictionary(sources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let landed: [(source: FileItem, item: FileItem)] = outcome.result.items.compactMap { entry in
            guard !entry.skipped, let source = sourcesByID[Self.trimmedPath(entry.from)] else { return nil }
            let path = Self.trimmedPath(entry.to)
            let item = FileItem(
                name: (path as NSString).lastPathComponent,
                path: destination,
                dateModified: outcome.operation == .copy ? date.now : source.dateModified,
                size: source.size,
                kind: source.kind,
                supportsThumbnail: source.supportsThumbnail
            )
            return (source, item)
        }
        guard !landed.isEmpty else { return }

        if outcome.operation == .move {
            for pair in landed where pair.source.path == state.directoryPath {
                state.items.remove(id: pair.source.id)
            }
        }
        if destination == state.directoryPath {
            for pair in landed where state.items[id: pair.item.id] == nil {
                state.items.append(pair.item)
            }
        }

        switch outcome.operation {
        case .copy:
            recordUndo(&state, FileUndoEntry(.created(landed.map(\.item))))
        case .move:
            recordUndo(&state, FileUndoEntry(.moved(landed.map {
                FileUndoEntry.MovedItem(item: $0.item, originalParent: $0.source.path)
            })))
        }
    }

    /// Records a new operation for ⌘Z. A new operation ends the redo history, as everywhere else.
    func recordUndo(_ state: inout State, _ entry: FileUndoEntry) {
        state.$undoStack.withLock { $0.record(entry) }
        state.$redoStack.withLock { $0 = [] }
    }

    /// Reverses the most recent recorded operation on the server, then refreshes every open
    /// folder. Nothing to undo, or one already running, does nothing.
    func undo(_ state: inout State) -> Effect<Action> {
        guard !state.isPerformingFileAction, let entry = state.undoStack.last else { return .none }
        state.$undoStack.withLock { _ = $0.popLast() }
        state.isPerformingFileAction = true
        let serverURL = state.serverURL
        let filesClient = filesClient
        return .run { send in
            try await send(.undoResponse(apiResult {
                switch entry.kind {
                case let .created(items):
                    try await filesClient.deleteItems(serverURL, items)
                case let .madeNew(item):
                    try await filesClient.deleteItems(serverURL, [item])
                case let .moved(moves):
                    let byParent = Dictionary(grouping: moves, by: \.originalParent)
                    for (parent, group) in byParent {
                        _ = try await filesClient.transferItems(serverURL, group.map(\.item), parent, .move)
                    }
                case let .renamed(item, previousName):
                    _ = try await filesClient.renameItem(serverURL, item, previousName)
                }
                return entry
            }))
        }
    }

    /// Does the most recently undone move, rename or new item again, then refreshes every open folder.
    /// The entry goes back on the undo stack once the server has done it.
    func redo(_ state: inout State) -> Effect<Action> {
        guard !state.isPerformingFileAction, let entry = state.redoStack.last else { return .none }
        state.$redoStack.withLock { _ = $0.popLast() }
        state.isPerformingFileAction = true
        let serverURL = state.serverURL
        let filesClient = filesClient
        return .run { send in
            try await send(.redoResponse(apiResult {
                switch entry.kind {
                case .created:
                    return entry
                case let .madeNew(item):
                    // The server picks a free name, so the next undo deletes what it made this time.
                    let made = item.isDirectory
                        ? try await filesClient.createFolder(serverURL, item.path, item.name)
                        : try await filesClient.createFile(serverURL, item.path, item.name)
                    return FileUndoEntry(.madeNew(made))
                case let .moved(moves):
                    // Undone, each item sits in its old parent again: move it back where it went.
                    let byDestination = Dictionary(grouping: moves, by: \.item.path)
                    for (destination, group) in byDestination {
                        let items = group.map { $0.item.relocated(to: $0.originalParent) }
                        _ = try await filesClient.transferItems(serverURL, items, destination, .move)
                    }
                case let .renamed(item, previousName):
                    _ = try await filesClient.renameItem(serverURL, item.named(previousName), item.name)
                }
                return entry
            }))
        }
    }

    static func trimmedPath(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

private extension FileItem {
    func relocated(to parent: String) -> FileItem {
        FileItem(
            name: name,
            path: parent,
            dateModified: dateModified,
            size: size,
            kind: kind,
            supportsThumbnail: supportsThumbnail
        )
    }

    func named(_ newName: String) -> FileItem {
        FileItem(
            name: newName,
            path: path,
            dateModified: dateModified,
            size: size,
            kind: kind,
            supportsThumbnail: supportsThumbnail
        )
    }
}
