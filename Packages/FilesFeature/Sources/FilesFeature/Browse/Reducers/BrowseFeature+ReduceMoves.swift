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
            let reveal = Effect<Action>.send(.delegate(.revealInFolder(
                path: result.path,
                title: result.enclosingFolderTitle,
                itemID: result.id
            )))
            guard result.path == state.directoryPath else { return reveal }
            state.searchQuery = ""
            return .merge(search(&state), reveal)

        #if os(macOS)
            case let .reviewUpload(source):
                return openUploadReview(source, state: &state)

        #endif

        case let .itemsDroppedFromOtherWindow(dropped, destination):
            guard state.access?.canReceive(dropped) ?? false else { return .none }
            // Not where they already are, and never into themselves or their own subfolders.
            let items = dropped.filter { item in
                item.path != destination && item.id != destination && !destination.hasPrefix(item.id + "/")
            }
            return runTransfer(&state, retry: TransferRetry(
                items: items, destination: destination, operation: .move, shouldClearClipboard: false
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
            return requestUploads(files, destination: destination, serverURL: state.serverURL)

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
            return requestUploads(Array(files), destination: destination, serverURL: state.serverURL)

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
            guard state.actions(for: item).canCopy else { return .none }
            state.$clipboard.withLock { $0 = FileClipboard(items: [item], operation: .copy) }
            state.clipboardStagedMessage = L10n.Browse.clipboardCopiedOne(item.name)
            return .none

        case let .moveTapped(item):
            guard state.actions(for: item).canMove else { return .none }
            state.destinationPicker = DestinationPickerFeature.State(serverURL: state.serverURL, items: [item])
            return .none

        case let .copyToTapped(item):
            guard state.actions(for: item).canCopy else { return .none }
            state.destinationPicker = DestinationPickerFeature.State(
                serverURL: state.serverURL,
                items: [item],
                isCopy: true
            )
            return .none

        case .copySelectionToTapped:
            let items = state.selectedItems
            guard state.actions(for: items).canCopy else { return .none }
            state.destinationPicker = DestinationPickerFeature.State(
                serverURL: state.serverURL,
                items: items,
                isCopy: true
            )
            return .none

        case .bulkCopyTapped:
            let items = state.selectedItems
            guard state.actions(for: items).canCopy else { return .none }
            state.$clipboard.withLock { $0 = FileClipboard(items: items, operation: .copy) }
            state.clipboardStagedMessage = items.count == 1
                ? L10n.Browse.clipboardCopiedOne(items[0].name)
                : L10n.Browse.clipboardCopiedMany(items.count)
            state.isSelecting = false
            state.selectedItemIDs = []
            return .none

        case .bulkMoveTapped:
            let items = state.selectedItems
            guard state.actions(for: items).canMove else { return .none }
            state.destinationPicker = DestinationPickerFeature.State(serverURL: state.serverURL, items: items)
            leaveSelectMode(&state)
            return .none

        case .clipboardCleared:
            state.$clipboard.withLock { $0 = nil }
            return .none

        case let .pasteTapped(keepItemsAfterCopy):
            return paste(&state, into: state.directoryPath, keepItemsAfterCopy: keepItemsAfterCopy)

        case let .pasteIntoTapped(folder, keepItemsAfterCopy):
            guard folder.isDirectory, state.items[id: folder.id] != nil else { return .none }
            return paste(&state, into: folder.id, keepItemsAfterCopy: keepItemsAfterCopy)

        case let .tableSelectionChanged(ids):
            guard !state.isSelecting else { return .none }
            state.selectedItemIDs = ids
            return .none

        case let .revealItemShown(id):
            guard let reveal = state.reveal, reveal.itemID == id, let item = state.items[id: id] else { return .none }
            state.reveal = nil
            state.scrollTargetID = id
            guard case .open = reveal else { return .send(.tableSelectionChanged([id])) }
            // Its folder first, then the file itself, as a double click on its row would.
            return .concatenate(.send(.tableSelectionChanged([id])), .send(.rowTapped(item)))

        case .scrollTargetShown:
            state.scrollTargetID = nil
            return .none

        case .copySelectionTapped:
            let items = state.selectedItems
            guard state.actions(for: items).canCopy else { return .none }
            state.$clipboard.withLock { $0 = FileClipboard(items: items, operation: .copy) }
            state.clipboardStagedMessage = items.count == 1
                ? L10n.Browse.clipboardCopiedOne(items[0].name)
                : L10n.Browse.clipboardCopiedMany(items.count)
            return .none

        case .cutSelectionTapped:
            let items = state.selectedItems
            guard state.actions(for: items).canMove else { return .none }
            state.$clipboard.withLock { $0 = FileClipboard(items: items, operation: .move) }
            state.clipboardStagedMessage = items.count == 1
                ? L10n.Browse.clipboardCutOne(items[0].name)
                : L10n.Browse.clipboardCutMany(items.count)
            return .none

        case .undoTapped:
            return undo(&state)

        case let .undoResponse(.success(entry)):
            state.isPerformingFileAction = false
            if entry.isRedoable {
                state.$redoStack.withLock { $0.record(entry) }
            }
            return contentsChanged(by: entry)

        case .redoTapped:
            return redo(&state)

        case let .redoResponse(.success(entry)):
            state.isPerformingFileAction = false
            state.$undoStack.withLock { $0.record(entry) }
            return contentsChanged(by: entry)

        case let .undoResponse(.failure(error)), let .redoResponse(.failure(error)):
            state.isPerformingFileAction = false
            state.fileActionErrorMessage = error.userMessage
            return .send(.delegate(.directoryContentsChanged))

        case .duplicateSelectionTapped:
            let items = state.selectedItems
            guard state.actions(for: items).canDuplicate else { return .none }
            return performTransfer(&state, retry: TransferRetry(
                items: items,
                destination: state.directoryPath,
                operation: .copy,
                shouldClearClipboard: false,
                resolution: .keepBoth
            ))

        case .deleteSelectionTapped:
            let items = state.selectedItems
            guard state.actions(for: items).canDelete else { return .none }
            return items.count == 1 ? .send(.deleteTapped(items[0])) : .send(.bulkDeleteTapped)

        case .renameSelectionTapped:
            let items = state.selectedItems
            guard state.actions(for: items).canRename else { return .none }
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
                items: Array(items), destination: folder.id, operation: .move, shouldClearClipboard: false
            ))

        case .infoSelectionTapped:
            let items = state.selectedItems
            #if os(macOS)
                guard !state.directoryPath.isEmpty else { return .none }
                if items.count > 1 {
                    return state.isInfoShowingSelection ? .send(.infoDismissed) : showSelectionInfo(&state)
                }
            #endif
            guard let item = items.count == 1 ? items.first : items.isEmpty ? state.folderItem(now: date.now) : nil
            else { return .none }
            // ⌘I toggles: pressing it again for the item already shown closes the inspector.
            if state.infoItem?.id == item.id {
                return .send(.infoDismissed)
            }
            return .send(.infoTapped(item))

        case let .destinationPicker(.presented(.delegate(.confirmed(destination)))):
            guard let picker = state.destinationPicker else { return .none }
            let items = picker.items
            state.destinationPicker = nil
            return runTransfer(&state, retry: TransferRetry(
                items: items,
                destination: destination,
                operation: picker.purpose == .copy ? .copy : .move,
                shouldClearClipboard: false
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
                // The listing failed: fall back to the server's safe auto rename rather
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

        case let .transferProgressed(fraction):
            state.transferProgress = fraction
            return .none

        case .transferCancelTapped:
            guard state.transferProgress != nil else { return .none }
            state.isPerformingFileAction = false
            state.transferProgress = nil
            state.pendingTransferRetry = nil
            // The server stops where it was: what it already copied or moved stays, so read the folder again.
            return .merge(.cancel(id: state.cancelID(.transfer)), load(&state))

        case let .transferResponse(.success(outcome)):
            let sources = state.pendingTransferRetry?.items ?? []
            state.isPerformingFileAction = false
            state.transferProgress = nil
            state.pendingTransferRetry = nil
            state.transferErrorMessage = nil
            if outcome.shouldClearClipboard {
                state.$clipboard.withLock { $0 = nil }
            }
            #if os(macOS)
                let isLandingOnScreen = Self.trimmedPath(outcome.result.destination) == state.directoryPath
            #elseif os(iOS)
                let isLandingOnScreen = false
            #endif
            if !isLandingOnScreen {
                state.transferSuccessMessage = Self.transferSuccessMessage(for: outcome)
            }
            let movedFavorites = outcome.operation == .move
                ? sources.map { repointFavorites(&state, from: $0.id, to: nil) }.contains(true)
                : false
            applyTransfer(&state, outcome: outcome, sources: sources)
            awaitArrivals(&state, from: outcome.result)
            return .merge(
                .send(.delegate(.directoryContentsChanged)),
                movedFavorites ? .send(.delegate(.favoritesChanged)) : .none
            )

        case let .transferResponse(.failure(error)):
            state.isPerformingFileAction = false
            state.transferProgress = nil
            state.transferErrorMessage = error.userMessage
            return refetchAfterAmbiguousFailure(&state, error)

        default:
            return .none
        }
    }
}

extension BrowseFeature {
    func contentsChanged(by entry: FileUndoEntry) -> Effect<Action> {
        .merge(
            .send(.delegate(.directoryContentsChanged)),
            entry.isFolderRelocation ? .send(.delegate(.favoritesChanged)) : .none
        )
    }
}

extension FileUndoEntry {
    var isFolderRelocation: Bool {
        switch kind {
        case let .moved(items): items.contains { $0.item.isDirectory }
        case let .renamed(item, _): item.isDirectory
        case .created, .madeNew: false
        }
    }
}

extension BrowseFeature.State {
    func folderItem(now: Date) -> FileItem? {
        let parts = directoryPath.split(separator: "/").map(String.init)
        guard let name = parts.last else { return nil }
        return FileItem(
            name: name,
            path: parts.dropLast().joined(separator: "/"),
            dateModified: now,
            size: 0,
            kind: FileItem.directoryKind
        )
    }
}
