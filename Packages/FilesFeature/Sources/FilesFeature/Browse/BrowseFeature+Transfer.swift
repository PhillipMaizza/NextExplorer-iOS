import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Localization

extension BrowseFeature {
    func paste(_ state: inout State, keepItemsAfterCopy: Bool) -> Effect<Action> {
        guard let clipboard = state.clipboard,
              clipboard.canPaste(into: state.directoryPath, canWrite: state.access?.canWrite ?? false)
        else { return .none }
        let clearClipboard = clipboard.operation == .move || !keepItemsAfterCopy
        return runTransfer(&state, retry: TransferRetry(
            items: clipboard.items,
            destination: state.directoryPath,
            operation: clipboard.operation,
            clearClipboard: clearClipboard
        ))
    }

    /// Entry point for every copy/move. Runs the name-collision check first (unless the retry
    /// already carries an answer), then either prompts or hands off to `performTransfer`.
    func runTransfer(_ state: inout State, retry: TransferRetry) -> Effect<Action> {
        guard !retry.items.isEmpty, !state.isPerformingFileAction else { return .none }
        guard retry.resolution == .ask else { return performTransfer(&state, retry: retry) }

        // Paste always targets the folder that's already on screen, so its listing is right
        // here in `state.items` — no round trip. A picker move can land anywhere else, so
        // that case asks the server for the destination listing.
        if retry.destination == state.directoryPath {
            return resolveTransfer(&state, retry: retry, colliding: Self.collidingItems(for: retry, in: Array(state.items)))
        }

        state.isPerformingFileAction = true
        state.fileActionProgressMessage = retry.operation == .move ? L10n.Browse.progressMoving : L10n.Browse.progressCopying
        state.transferErrorMessage = nil
        state.pendingTransferRetry = retry
        let serverURL = state.serverURL
        let filesClient = filesClient
        return .run { send in
            try await send(.transferConflictCheckResponse(apiResult {
                try await filesClient.browse(serverURL, retry.destination).items
            }))
        }
        .cancellable(id: CancelID.transfer)
    }

    /// No collisions → straight through (server auto-rename is a no-op when nothing clashes).
    /// Otherwise stash the pending transfer and let `BrowseContentView` raise the prompt.
    func resolveTransfer(_ state: inout State, retry: TransferRetry, colliding: [FileItem]) -> Effect<Action> {
        guard !colliding.isEmpty else { return performTransfer(&state, retry: retry.resolved(.keepBoth)) }
        state.isPerformingFileAction = false
        state.fileActionProgressMessage = nil
        state.pendingTransferRetry = retry
        state.transferConflict = TransferConflict(retry: retry, collidingItems: colliding)
        return .none
    }

    /// Actually moves the bytes: for `.replace`, deletes the clashing destination items first,
    /// then transfers. The staged clipboard is never emptied until this confirms success.
    func performTransfer(_ state: inout State, retry: TransferRetry) -> Effect<Action> {
        guard !retry.items.isEmpty else { return .none }
        state.isPerformingFileAction = true
        state.fileActionProgressMessage = retry.operation == .move ? L10n.Browse.progressMoving : L10n.Browse.progressCopying
        state.transferErrorMessage = nil
        state.transferConflict = nil
        // Kept until the transfer confirms success, so the "Retry" action on a failure toast
        // always has the exact params to re-run.
        state.pendingTransferRetry = retry
        let serverURL = state.serverURL
        let filesClient = filesClient
        return .run { send in
            try await send(.transferResponse(apiResult {
                if retry.resolution == .replace, !retry.itemsToReplace.isEmpty {
                    try await filesClient.deleteItems(serverURL, retry.itemsToReplace)
                }
                let result = try await filesClient.transferItems(serverURL, retry.items, retry.destination, retry.operation)
                return TransferOutcome(result: result, operation: retry.operation, clearClipboard: retry.clearClipboard)
            }), animation: .default)
        }
        .cancellable(id: CancelID.transfer)
    }

    /// Destination items that share a name with something inbound — minus any that *are* the
    /// inbound item (copying a file into its own folder isn't a real collision; the server
    /// just makes a numbered duplicate).
    static func collidingItems(for retry: TransferRetry, in destinationItems: [FileItem]) -> [FileItem] {
        let incomingNames = Set(retry.items.map(\.name))
        let sourceIDs = Set(retry.items.map(\.id))
        return destinationItems.filter { incomingNames.contains($0.name) && !sourceIDs.contains($0.id) }
    }

    static func transferSuccessMessage(for outcome: TransferOutcome) -> String {
        let moved = outcome.result.movedCount
        let skipped = outcome.result.skippedCount
        switch outcome.operation {
        case .move:
            return skipped > 0
                ? L10n.Browse.transferMovedWithSkipped(moved, skipped)
                : L10n.Browse.transferMoved(moved)
        case .copy:
            return skipped > 0
                ? L10n.Browse.transferCopiedWithSkipped(moved, skipped)
                : L10n.Browse.transferCopied(moved)
        }
    }
}
