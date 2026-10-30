import ComposableArchitecture
import CoreModels
import FilesClient
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
            state.$undoStack.withLock { $0.record(FileUndoEntry(.created(landed.map(\.item)))) }
        case .move:
            state.$undoStack.withLock {
                $0.record(FileUndoEntry(.moved(landed.map {
                    FileUndoEntry.MovedItem(item: $0.item, originalParent: $0.source.path)
                })))
            }
        }
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
                case let .moved(moves):
                    let byParent = Dictionary(grouping: moves, by: \.originalParent)
                    for (parent, group) in byParent {
                        _ = try await filesClient.transferItems(serverURL, group.map(\.item), parent, .move)
                    }
                case let .renamed(item, previousName):
                    _ = try await filesClient.renameItem(serverURL, item, previousName)
                }
                return true
            }))
        }
    }

    static func trimmedPath(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
