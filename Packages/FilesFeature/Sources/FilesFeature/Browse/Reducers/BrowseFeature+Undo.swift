import ComposableArchitecture
import CoreModels
import FilesClient
import FolderPickerFeature
import Foundation
import NetworkClient

extension BrowseFeature {
    /// A confirmed copy or move: show its outcome in this listing right away (the refresh that
    /// follows confirms it), and record how to undo it.
    func applyTransfer(_ state: inout State, outcome: TransferOutcome, sources: [FileItem]) {
        let destination = Self.trimmedPath(outcome.result.destination)
        let sourcesByID = Dictionary(sources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let landed: [(source: FileItem, item: FileItem)] = outcome.result.items.compactMap { entry in
            guard !entry.isSkipped, let source = sourcesByID[Self.trimmedPath(entry.from)] else { return nil }
            let path = Self.trimmedPath(entry.to)
            let item = source.changing(
                name: (path as NSString).lastPathComponent,
                path: destination,
                dateModified: outcome.operation == .copy ? date.now : nil
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
            state.selectedItemIDs = Set(landed.map(\.item.id))
            state.scrollTargetID = landed.first?.item.id
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
                    _ = try await filesClient.deleteItems(serverURL, items, false, nil)
                case let .madeNew(item):
                    _ = try await filesClient.deleteItems(serverURL, [item], false, nil)
                case let .moved(moves):
                    let byParent = Dictionary(grouping: moves, by: \.originalParent)
                    for (parent, group) in byParent {
                        _ = try await filesClient.transferItems(serverURL, group.map(\.item), parent, .move, nil)
                    }
                case let .renamed(item, previousName):
                    _ = try await filesClient.renameItem(serverURL, item, previousName)
                case let .trashed(items):
                    let result = try await filesClient
                        .restoreTrash(serverURL, .items(items.map(\.trashID)), nil, .restore) { _ in }
                    return try Self.restored(items, by: result)
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
                        let items = group.map { $0.item.changing(path: $0.originalParent) }
                        _ = try await filesClient.transferItems(serverURL, items, destination, .move, nil)
                    }
                case let .renamed(item, previousName):
                    _ = try await filesClient.renameItem(serverURL, item.changing(name: previousName), item.name)
                case let .trashed(trashed):
                    let items = trashed.map(\.item)
                    let outcome = try await filesClient.deleteItems(serverURL, items, false, nil)
                    return FileUndoEntry(.trashed(outcome.trashed(of: items)))
                }
                return entry
            }))
        }
    }

    static func restored(
        _ trashed: [FileUndoEntry.TrashedItem],
        by result: TrashActionResult
    ) throws -> FileUndoEntry {
        let restored = trashed.compactMap { trashedItem -> FileUndoEntry.TrashedItem? in
            guard let entry = result.items.first(where: { $0.key == trashedItem.trashID }),
                  entry.status == .restored else { return nil }
            let name = entry.restoredName ?? trashedItem.item.name
            return FileUndoEntry.TrashedItem(item: trashedItem.item.changing(name: name), trashID: trashedItem.trashID)
        }
        guard !restored.isEmpty else {
            throw FilesClientError.serverMessage(
                statusCode: HTTPStatus.conflict.rawValue,
                message: (result.failed.first?.status ?? .unknown).reason
            )
        }
        return FileUndoEntry(.trashed(restored))
    }

    static func trimmedPath(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
