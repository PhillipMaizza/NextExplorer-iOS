import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import FolderPickerFeature
import Foundation
import Localization
import NetworkClient
import ShareUploads
import SwiftUI

extension BrowseFeature {
    /// Uploads, drops, copy, move, paste, undo and the transfer conflict flow.
    func reduceMoves(_ state: inout State, _ action: Action) -> Effect<Action> {
        switch action {
        case let .beginUpload(source):
            guard source.count > 0 else { return .none }
            #if os(macOS)
                // A Mac drop or file pick already says where the files go (the folder on
                // screen), so they upload straight away instead of through the review sheet.
                if case let .documents(urls) = source, !state.directoryPath.isEmpty {
                    return stageDirectUpload(urls, destination: state.directoryPath)
                }
            #endif
            return openUploadReview(source, state: &state)

        case let .searchResultEnclosingFolderTapped(result):
            state.searchQuery = ""
            return .merge(
                search(&state),
                .send(.delegate(.openPath(path: result.path, title: result.enclosingFolderTitle)))
            )

        #if os(macOS)
            case let .reviewUpload(source):
                return openUploadReview(source, state: &state)

        #endif

        case let .itemsDroppedFromOtherWindow(dropped, destination):
            // The source folder lives in another window, so the backend enforces its canDelete. This window
            // is the destination: canWrite is the client side guard, as the web client's paste check.
            guard state.access?.canWrite ?? false else { return .none }
            // Not where they already are, and never into themselves or their own subfolders.
            let items = dropped.filter { item in
                item.path != destination && item.id != destination && !destination.hasPrefix(item.id + "/")
            }
            return runTransfer(&state, retry: TransferRetry(
                items: items, destination: destination, operation: .move, clearClipboard: false
            ))

        case let .filesDroppedOnFolder(urls, folder):
            // Finder files dropped on a folder row go into that folder, as in Finder.
            guard folder.isDirectory, !urls.isEmpty, state.access?.canUpload ?? false else {
                return BrowseDropHandler.discardStagedFiles(urls)
            }
            return stageDirectUpload(urls, destination: folder.id)

        case let .directUploadStaged(files, destination, _):
            guard !files.isEmpty else {
                state.fileActionErrorMessage = L10n.Uploads.stagingFailed
                return .none
            }
            return .send(.delegate(.uploadRequested(files.map {
                PendingUpload(id: $0.id, fileURL: $0.fileURL, fileName: $0.fileName, destination: destination)
            })))

        case let .receiveSharedFiles(urls):
            guard !urls.isEmpty else { return .none }
            // Settings > Shared Files: a default folder with Upload Without Asking takes them
            // straight there, no sheet.
            let defaults = uploadDefaults.loadActive()
            if let folder = defaults.directFolder {
                return stageDirectUpload(urls, destination: folder)
            }
            if state.uploadReview != nil {
                return .send(.uploadReview(.presented(.stage(.documents(urls)))))
            }
            let review = Action.reviewSharedFiles(urls, startingAt: defaults.folderPath)
            // An open preview would cover the review sheet.
            if state.previewItem != nil {
                return .concatenate(.send(.previewDismissed), .send(review))
            }
            return .send(review)

        case let .reviewSharedFiles(urls, startingAt):
            return openUploadReview(.documents(urls), startingAt: startingAt, state: &state)

        case let .uploadReview(.presented(.delegate(.confirmed(files, destination)))):
            state.uploadReview = nil
            guard !files.isEmpty, !destination.isEmpty else { return .none }
            return .send(.delegate(.uploadRequested(files.map {
                PendingUpload(id: $0.id, fileURL: $0.fileURL, fileName: $0.fileName, destination: destination)
            })))

        case .uploadReview(.presented(.delegate(.cancelled))):
            // Discard whatever staging already copied: those files are never uploaded now.
            let staged = state.uploadReview?.files.map(\.fileURL) ?? []
            state.uploadReview = nil
            guard !staged.isEmpty else { return .none }
            let uploadStaging = uploadStaging
            return .run { _ in await uploadStaging.discard(staged) }

        case .uploadReview:
            return .none

        case let .copyTapped(item):
            state.$clipboard.withLock { $0 = FileClipboard(items: [item], operation: .copy) }
            state.clipboardStagedMessage = L10n.Browse.clipboardCopiedOne(item.name)
            return .none

        case let .moveTapped(item):
            state.destinationPicker = DestinationPickerFeature.State(serverURL: state.serverURL, items: [item])
            return .none

        case .bulkCopyTapped:
            let items = Array(state.items.filter { state.selectedItemIDs.contains($0.id) })
            guard !items.isEmpty else { return .none }
            state.$clipboard.withLock { $0 = FileClipboard(items: items, operation: .copy) }
            state.clipboardStagedMessage = items.count == 1
                ? L10n.Browse.clipboardCopiedOne(items[0].name)
                : L10n.Browse.clipboardCopiedMany(items.count)
            state.isSelecting = false
            state.selectedItemIDs = []
            return .none

        case .bulkMoveTapped:
            let items = Array(state.items.filter { state.selectedItemIDs.contains($0.id) })
            guard !items.isEmpty else { return .none }
            state.destinationPicker = DestinationPickerFeature.State(serverURL: state.serverURL, items: items)
            state.isSelecting = false
            state.selectedItemIDs = []
            return .none

        case .clipboardCleared:
            state.$clipboard.withLock { $0 = nil }
            return .none

        case let .pasteTapped(keepItemsAfterCopy):
            return paste(&state, keepItemsAfterCopy: keepItemsAfterCopy)

        case let .tableSelectionChanged(ids):
            guard !state.isSelecting else { return .none }
            state.selectedItemIDs = ids
            // An open inspector follows the selection to the newly picked row.
            guard state.infoItem != nil, ids.count == 1,
                  let item = state.selectedItems.first, item.id != state.infoItem?.id
            else { return .none }
            return loadInfo(&state, item: item, settle: Constants.inspectorFollowDelay)

        case .copySelectionTapped:
            let items = state.selectedItems
            guard !items.isEmpty else { return .none }
            state.$clipboard.withLock { $0 = FileClipboard(items: items, operation: .copy) }
            state.clipboardStagedMessage = items.count == 1
                ? L10n.Browse.clipboardCopiedOne(items[0].name)
                : L10n.Browse.clipboardCopiedMany(items.count)
            return .none

        case .cutSelectionTapped:
            let items = state.selectedItems
            guard !items.isEmpty, state.access?.canDelete ?? false else { return .none }
            state.$clipboard.withLock { $0 = FileClipboard(items: items, operation: .move) }
            state.clipboardStagedMessage = items.count == 1
                ? L10n.Browse.clipboardCutOne(items[0].name)
                : L10n.Browse.clipboardCutMany(items.count)
            return .none

        case .undoTapped:
            return undo(&state)

        case .undoResponse(.success):
            state.isPerformingFileAction = false
            return .send(.delegate(.directoryContentsChanged))

        case let .undoResponse(.failure(error)):
            state.isPerformingFileAction = false
            state.fileActionErrorMessage = error.userMessage
            return .send(.delegate(.directoryContentsChanged))

        case .duplicateSelectionTapped:
            let items = state.selectedItems
            guard !items.isEmpty, !state.directoryPath.isEmpty, state.access?.canWrite ?? false else { return .none }
            return performTransfer(&state, retry: TransferRetry(
                items: items,
                destination: state.directoryPath,
                operation: .copy,
                clearClipboard: false,
                resolution: .keepBoth
            ))

        case .deleteSelectionTapped:
            let items = state.selectedItems
            guard !items.isEmpty, state.access?.canDelete ?? false else { return .none }
            return items.count == 1 ? .send(.deleteTapped(items[0])) : .send(.bulkDeleteTapped)

        case .renameSelectionTapped:
            let items = state.selectedItems
            guard items.count == 1, state.access?.canWrite ?? false else { return .none }
            return .send(.renameTapped(items[0]))

        case let .itemsDroppedOnFolder(ids, folder):
            // A move deletes the original from this folder, so the backend (prepareTransfer) asks for
            // canDelete on the source and only read on the destination.
            guard folder.isDirectory, state.access?.canDelete ?? false else { return .none }
            // Never into itself or one of its own subfolders.
            let items = state.items.filter { item in
                ids.contains(item.id) && item.id != folder.id && !folder.id.hasPrefix(item.id + "/")
            }
            return runTransfer(&state, retry: TransferRetry(
                items: Array(items), destination: folder.id, operation: .move, clearClipboard: false
            ))

        case .infoSelectionTapped:
            // ⌘I toggles: pressing it again for the item already shown closes the inspector.
            if state.infoItem != nil, state.infoItem?.id == state.selectedItems.first?.id {
                return .send(.infoDismissed)
            }
            let items = state.selectedItems
            guard items.count == 1 else { return .none }
            return .send(.infoTapped(items[0]))

        case let .destinationPicker(.presented(.delegate(.confirmed(destination)))):
            guard let picker = state.destinationPicker else { return .none }
            let items = picker.items
            state.destinationPicker = nil
            return runTransfer(&state, retry: TransferRetry(
                items: items, destination: destination, operation: .move, clearClipboard: false
            ))

        case .destinationPicker(.presented(.delegate(.cancelled))):
            state.destinationPicker = nil
            return .none

        case .destinationPicker:
            return .none

        case .retryTransferTapped:
            guard let retry = state.pendingTransferRetry else { return .none }
            return runTransfer(&state, retry: retry)

        case let .transferConflictCheckResponse(result):
            guard let retry = state.pendingTransferRetry else { return .none }
            switch result {
            case let .success(destinationItems):
                return resolveTransfer(
                    &state,
                    retry: retry,
                    colliding: Self.collidingItems(for: retry, in: destinationItems)
                )
            case .failure:
                // The listing failed: fall back to the server's safe auto-rename rather
                // than blocking the transfer on a check we couldn't run.
                return performTransfer(&state, retry: retry.resolved(.keepBoth))
            }

        case let .transferConflictResolved(choice):
            guard let conflict = state.transferConflict else { return .none }
            state.transferConflict = nil
            switch choice {
            case .replace:
                return performTransfer(
                    &state,
                    retry: conflict.retry.resolved(.replace, replacing: conflict.collidingItems)
                )
            case .keepBoth:
                return performTransfer(&state, retry: conflict.retry.resolved(.keepBoth))
            case .none:
                state.pendingTransferRetry = nil
                return .none
            }

        case let .transferResponse(.success(outcome)):
            let sources = state.pendingTransferRetry?.items ?? []
            state.isPerformingFileAction = false
            state.fileActionProgressMessage = nil
            state.pendingTransferRetry = nil
            state.transferErrorMessage = nil
            if outcome.clearClipboard {
                state.$clipboard.withLock { $0 = nil }
            }
            state.transferSuccessMessage = Self.transferSuccessMessage(for: outcome)
            applyTransfer(&state, outcome: outcome, sources: sources)
            awaitArrivals(&state, from: outcome.result)
            return .send(.delegate(.directoryContentsChanged))

        case let .transferResponse(.failure(error)):
            state.isPerformingFileAction = false
            state.fileActionProgressMessage = nil
            state.transferErrorMessage = error.userMessage
            return refetchAfterAmbiguousFailure(&state, error)

        default:
            return .none
        }
    }
}
