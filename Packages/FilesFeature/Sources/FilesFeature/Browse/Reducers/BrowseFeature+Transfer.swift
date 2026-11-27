import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import FolderPickerFeature
import Foundation
import Localization

extension BrowseFeature {
    func paste(_ state: inout State, into destination: String, keepItemsAfterCopy: Bool) -> Effect<Action> {
        guard let clipboard = state.clipboard, state.canPaste(into: destination) else { return .none }
        let shouldClearClipboard = clipboard.operation == .move || !keepItemsAfterCopy
        return runTransfer(&state, retry: TransferRetry(
            items: clipboard.items,
            destination: destination,
            operation: clipboard.operation,
            shouldClearClipboard: shouldClearClipboard
        ))
    }

    /// Entry point for every copy/move. Runs the name collision check first (unless the retry
    /// already carries an answer), then either prompts or hands off to `performTransfer`.
    func runTransfer(_ state: inout State, retry: TransferRetry) -> Effect<Action> {
        guard !retry.items.isEmpty, !state.isPerformingFileAction else { return .none }
        guard retry.resolution == .ask else { return performTransfer(&state, retry: retry) }

        // A paste into the folder on screen has its listing right here in `state.items`: no
        // round trip. Anywhere else asks the server for the destination listing.
        if retry.destination == state.directoryPath {
            return resolveTransfer(
                &state,
                retry: retry,
                colliding: Self.collidingItems(for: retry, in: Array(state.items))
            )
        }

        state.isPerformingFileAction = true
        state.transferProgress = 0
        state.transferErrorMessage = nil
        state.transferSuccessMessage = nil
        state.pendingTransferRetry = retry
        let serverURL = state.serverURL
        let filesClient = filesClient
        return .run { send in
            try await send(.transferConflictCheckResponse(apiResult {
                try await filesClient.browse(serverURL, retry.destination).items
            }))
        }
        .cancellable(id: state.cancelID(.transfer))
    }

    /// No collisions → straight through (server auto rename is a no op when nothing clashes).
    /// Otherwise stash the pending transfer and let `BrowseContentView` raise the prompt.
    func resolveTransfer(_ state: inout State, retry: TransferRetry, colliding: [FileItem]) -> Effect<Action> {
        guard !colliding.isEmpty else { return performTransfer(&state, retry: retry.resolved(.keepBoth)) }
        state.isPerformingFileAction = false
        state.transferProgress = nil
        state.pendingTransferRetry = retry
        state.transferConflict = TransferConflict(retry: retry, collidingItems: colliding)
        return .none
    }

    /// Actually moves the bytes: for `.replace`, deletes the clashing destination items first,
    /// then transfers. The staged clipboard is never emptied until this confirms success.
    func performTransfer(_ state: inout State, retry: TransferRetry) -> Effect<Action> {
        guard !retry.items.isEmpty else { return .none }
        state.isPerformingFileAction = true
        state.transferProgress = 0
        state.transferErrorMessage = nil
        state.transferSuccessMessage = nil
        state.transferConflict = nil
        // Kept until the transfer confirms success, so the "Retry" action on a failure toast
        // always has the exact params to rerun.
        state.pendingTransferRetry = retry
        let serverURL = state.serverURL
        let filesClient = filesClient
        return .run { send in
            try await send(.transferResponse(apiResult {
                if retry.resolution == .replace, !retry.itemsToReplace.isEmpty {
                    // What is replaced goes to the trash. One the trash refused still holds its name,
                    // so the transfer stops rather than landing beside it under another name.
                    let outcome = try await filesClient.deleteItems(serverURL, retry.itemsToReplace, false, nil)
                    if let kept = outcome.kept(of: retry.itemsToReplace).first {
                        throw FilesClientError.serverMessage(
                            statusCode: Constants.replaceRefusedStatus,
                            message: L10n.Trash.replaceKept(kept.name)
                        )
                    }
                }
                let result = try await withProgressActions(
                    send: send,
                    action: Action.transferProgressed
                ) { onProgress in
                    try await filesClient.transferItems(
                        serverURL,
                        retry.items,
                        retry.destination,
                        retry.operation,
                        onProgress
                    )
                }
                return TransferOutcome(
                    result: result,
                    operation: retry.operation,
                    shouldClearClipboard: retry.shouldClearClipboard
                )
            }), animation: DSMotion.listDiff)
        }
        .cancellable(id: state.cancelID(.transfer))
    }

    /// A copy or move into the folder on screen: note what it created, and drop the folder's
    /// saved listing so the refresh that follows is a full fetch rather than a revalidation.
    func awaitArrivals(_ state: inout State, from result: TransferResult) {
        let destination = result.destination.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        directoryCacheStore.bound(to: state.cacheScope).remove(state.serverURL, destination)
        guard destination == state.directoryPath else { return }
        state.awaitedArrivalIDs = Set(result.items.filter { !$0.isSkipped }.map {
            $0.to.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        })
        state.arrivalChecksLeft = Constants.arrivalRechecks
    }

    /// After a listing lands: stop waiting once every awaited item is there (or the rechecks run
    /// out), otherwise refetch again shortly.
    func recheckArrivals(_ state: inout State) -> Effect<Action> {
        guard !state.awaitedArrivalIDs.isEmpty else { return .none }
        state.awaitedArrivalIDs.subtract(state.items.ids)
        guard !state.awaitedArrivalIDs.isEmpty, state.arrivalChecksLeft > 0 else {
            state.awaitedArrivalIDs = []
            state.arrivalChecksLeft = 0
            return .none
        }
        state.arrivalChecksLeft -= 1
        let clock = clock
        return .run { send in
            try await clock.sleep(for: Constants.arrivalRecheckDelay)
            await send(.refreshButtonTapped)
        }
        .cancellable(id: state.cancelID(.arrivalRecheck), cancelInFlight: true)
    }

    /// Destination items that share a name with something inbound: minus any that *are* the
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

extension BrowseFeature.State {
    func canPaste(into destination: String) -> Bool {
        guard let clipboard else { return false }
        return clipboard.canPaste(into: destination, canReceive: access?.canReceive(clipboard.items) ?? false)
    }
}
