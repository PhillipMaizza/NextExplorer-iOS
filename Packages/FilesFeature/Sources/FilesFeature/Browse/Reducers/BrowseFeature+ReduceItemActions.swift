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
    /// Rename, delete, favorite, create, extract, compress, share and download one item.
    func reduceItemActions(_ state: inout State, _ action: Action) -> Effect<Action> {
        switch action {
        case let .renameTapped(item):
            guard state.actions(for: item).canRename else { return .none }
            state.renameSheetItem = item
            return .none

        case let .deleteTapped(item):
            guard state.actions(for: item).canDelete else { return .none }
            state.deleteConfirmationItem = item
            state.deleteImpactCheck = .checking
            return checkDeleteImpact(&state, items: [item])

        case let .favoriteToggleButtonTapped(item):
            // Mirrors the real server: `favoritesService.validatePath` 400s on anything
            // that isn't a directory, so files never get a favorites entry point.
            guard item.isDirectory, state.hasLoadedFavorites else { return .none }
            return toggleFavorite(&state, item: item)

        case let .favoriteToggleResponse(.success(result)):
            if result.isFavorite {
                state.favoritePaths.insert(result.path)
            } else {
                state.favoritePaths.remove(result.path)
            }
            return .send(.delegate(.favoritesChanged))

        case let .favoriteToggleResponse(.failure(error)):
            state.fileActionErrorMessage = error.userMessage
            return .none

        case .renameCancelled:
            state.renameSheetItem = nil
            return .none

        case let .renameConfirmed(newName):
            return confirmRename(&state, newName: newName)

        case .openDownloadsFromPreview:
            let clock = clock
            return .merge(
                .send(.previewDismissed),
                .run { send in
                    try await clock.sleep(for: Constants.previewActionSettleDelay)
                    await send(.delegate(.openDownloadsTapped))
                }
                .cancellable(id: CancelID.previewDeferredAction, cancelInFlight: true)
            )

        case .goToSharedTabFromPreview:
            let clock = clock
            return .merge(
                .send(.previewDismissed),
                .run { send in
                    try await clock.sleep(for: Constants.previewActionSettleDelay)
                    await send(.delegate(.goToSharedTab))
                }
                .cancellable(id: CancelID.previewDeferredAction, cancelInFlight: true)
            )

        case let .renameResponse(.success(result)):
            state.isPerformingFileAction = false
            state.renameSheetItem = nil
            let previousName = state.items[id: result.originalID]?.name ?? (result.originalID as NSString)
                .lastPathComponent
            recordUndo(&state, FileUndoEntry(.renamed(result.renamed, previousName: previousName)))
            if let index = state.items.index(id: result.originalID) {
                state.items.remove(at: index)
                state.items.insert(result.renamed, at: index)
            }
            if state.selectedItemIDs.remove(result.originalID) != nil {
                state.selectedItemIDs.insert(result.renamed.id)
            }
            renameInSearch(&state, from: result.originalID, to: result.renamed)
            // A rename from a preview keeps the cover up: repoint it at the renamed item
            // so its title/actions follow.
            if state.previewItem?.id == result.originalID {
                state.previewItem = result.renamed
            }
            syncListingCache(state)
            let favoritesSync: Effect<Action> = repointFavorites(
                &state,
                from: result.originalID,
                to: result.renamed.id
            ) ? .send(.delegate(.favoritesChanged)) : .none
            // The Mac inspector follows the rename instead of showing the old path.
            if state.infoItem?.id == result.originalID {
                return .merge(loadInfo(&state, item: result.renamed), favoritesSync)
            }
            return favoritesSync

        case let .renameResponse(.failure(error)):
            state.isPerformingFileAction = false
            state.fileActionErrorMessage = error.userMessage
            return refetchAfterAmbiguousFailure(&state, error)

        case .newFolderTapped:
            // The menu hides it where the folder refuses new folders; a keyboard shortcut
            // must not get past that either.
            guard state.access?.canCreateFolder ?? true else { return .none }
            state.isNewFolderSheetPresented = true
            return .none

        case .newFolderCancelled:
            state.isNewFolderSheetPresented = false
            return .none

        case let .newFolderConfirmed(name):
            return confirmNewFolder(&state, name: name)

        case let .newFolderResponse(.success(folder)):
            state.isPerformingFileAction = false
            state.isNewFolderSheetPresented = false
            state.items.append(folder)
            state.selectedItemIDs = [folder.id]
            state.scrollTargetID = folder.id
            recordUndo(&state, FileUndoEntry(.madeNew(folder)))
            syncListingCache(state)
            state.createdFolderIDs.insert(folder.id)
            return .none

        case let .newFolderResponse(.failure(error)):
            state.isPerformingFileAction = false
            // Keep the sheet open (mirrors rename) so a server rejection (a name taken, a
            // permission) leaves the typed name in place for the user to correct and retry.
            state.fileActionErrorMessage = error.userMessage
            return .none

        case .newFileTapped:
            guard state.access?.canCreateFile ?? true else { return .none }
            state.isNewFileSheetPresented = true
            let serverURL = state.serverURL
            let filesClient = filesClient
            return .run { send in
                if let extensions = try? await filesClient.serverFeatures(serverURL).editorExtensions,
                   !extensions.isEmpty
                {
                    await send(.newFileExtensionsLoaded(extensions))
                }
            }
            .cancellable(id: CancelID.newFileExtensions, cancelInFlight: true)

        case .newFileCancelled:
            state.isNewFileSheetPresented = false
            return .cancel(id: CancelID.newFileExtensions)

        case let .newFileExtensionsLoaded(extensions):
            state.newFileServerExtensions = extensions
            return .none

        case let .newFileConfirmed(name):
            return confirmNewFile(&state, name: name)

        case let .newFileResponse(.success(file)):
            state.isPerformingFileAction = false
            state.isNewFileSheetPresented = false
            state.items.append(file)
            state.selectedItemIDs = [file.id]
            state.scrollTargetID = file.id
            recordUndo(&state, FileUndoEntry(.madeNew(file)))
            syncListingCache(state)
            // Straight into the editor: an empty file is only ever made to be written in. After
            // the sheet has gone, since a cover presented mid dismissal can be dropped on iOS.
            state.newlyCreatedFileID = file.id
            let clock = clock
            return .run { send in
                try await clock.sleep(for: Constants.previewActionSettleDelay)
                await send(.rowTapped(file))
            }
            .cancellable(id: CancelID.previewDeferredAction, cancelInFlight: true)

        case let .newFileResponse(.failure(error)):
            state.isPerformingFileAction = false
            // The sheet stays open with the typed name, as for a new folder.
            state.fileActionErrorMessage = error.userMessage
            return .none

        case .deleteCancelled:
            state.deleteConfirmationItem = nil
            state.deleteImpactCheck = .idle
            return .cancel(id: CancelID.deleteImpact)

        case let .deleteImpactResponse(.success(impact)):
            state.deleteImpactCheck = .loaded(impact)
            return .none

        case .deleteImpactResponse(.failure):
            state.deleteImpactCheck = .unavailable
            return .none

        case .deleteConfirmed:
            return confirmDelete(&state)

        case .deleteConfirmedFromPreview:
            return .merge(
                .send(.previewDismissed),
                confirmDelete(&state, deferred: true)
            )

        case let .deletePermanentlyConfirmed(fromPreview):
            guard fromPreview else { return confirmDelete(&state, permanent: true) }
            return .merge(
                .send(.previewDismissed),
                confirmDelete(&state, deferred: true, permanent: true)
            )

        case .keptDeletePermanentlyConfirmed:
            return deleteKeptPermanently(&state)

        case .keptDeleteDismissed:
            state.keptDeletes = []
            return .none

        case let .deleteResponse(.success(result)):
            state.isPerformingFileAction = false
            return applyDeleteResult(&state, result)

        case let .deleteResponse(.failure(error)):
            state.isPerformingFileAction = false
            state.fileActionErrorMessage = error.userMessage
            return refetchAfterAmbiguousFailure(&state, error)

        case let .extractTapped(item, entryPaths):
            return extract(&state, item) { filesClient, serverURL in
                guard let entryPaths else { return try await [filesClient.extractZip(serverURL, item)] }
                return try await filesClient.extractArchiveEntries(serverURL, item, entryPaths)
            }

        case let .extractHereTapped(item):
            return extract(&state, item) { filesClient, serverURL in
                try await filesClient.extractZipHere(serverURL, item)
            }

        case let .extractResponse(.success(extracted)):
            state.isPerformingFileAction = false
            state.fileActionProgressMessage = nil
            let here = extracted.filter { $0.path == state.directoryPath }
            guard !here.isEmpty else { return refreshSearch(&state) }
            for item in here where state.items[id: item.id] == nil {
                state.items.append(item)
            }
            state.selectedItemIDs = Set(here.map(\.id))
            state.scrollTargetID = here.first?.id
            syncListingCache(state)
            return .none

        case let .extractResponse(.failure(error)):
            state.isPerformingFileAction = false
            state.fileActionProgressMessage = nil
            state.fileActionErrorMessage = error.userMessage
            return refetchAfterAmbiguousFailure(&state, error)

        case let .compressTapped(item):
            return compress(&state, items: [item])

        case .compressSelectionTapped:
            return compress(&state, items: state.selectedItems)

        case let .compressResponse(.success(compressed)):
            state.isPerformingFileAction = false
            state.fileActionProgressMessage = nil
            guard compressed.path == state.directoryPath else { return refreshSearch(&state) }
            state.items.append(compressed)
            state.selectedItemIDs = [compressed.id]
            state.scrollTargetID = compressed.id
            syncListingCache(state)
            // Refetch so the new archive carries the same server metadata a normal listing
            // entry does and is browsable straight away, not only after a manual refresh.
            return load(&state)

        case let .compressResponse(.failure(error)):
            state.isPerformingFileAction = false
            state.fileActionProgressMessage = nil
            state.fileActionErrorMessage = error.userMessage
            return refetchAfterAmbiguousFailure(&state, error)

        case let .keptShareTapped(items):
            // Cleared so a second tap that finds nothing again shows its message again.
            state.fileActionErrorMessage = nil
            let files = items.filter { !$0.isDirectory }
            let store = offlineFileStore.pinned(to: state.cacheScope)
            return .run { send in
                await send(.keptShareResolved(files.compactMap { store.localURLIgnoringStaleness($0) }))
            }

        case let .keptShareResolved(urls):
            // Select mode ends only once the sheet opens; files still downloading keep the
            // selection and say why nothing opened.
            guard !urls.isEmpty else {
                state.fileActionErrorMessage = L10n.Offline.shareNotKept
                return .none
            }
            state.isSelecting = false
            state.selectedItemIDs = []
            state.keptShare = KeptFilesShare(urls: urls)
            return .none

        case .keptShareDismissed:
            state.keptShare = nil
            return .none

        case let .downloadTapped(item):
            guard state.actions(for: item).canDownload else { return .none }
            #if os(macOS)
                // A Mac saves where the user says, through the save panel, then the queue saves it there.
                return startDownload(&state, item: item)
            #else
                guard !item.isDirectory else { return .none }
                if state.previewItem != nil {
                    state.downloadSuccessMessage = L10n.DownloadQueue.barTitleOne(item.name)
                }
                return .send(.delegate(.downloadRequested([item])))
            #endif

        default:
            return .none
        }
    }

    private func extract(
        _ state: inout State,
        _ item: FileItem,
        operation: @escaping @Sendable (FilesClient, URL) async throws -> [FileItem]
    ) -> Effect<Action> {
        guard !state.isPerformingFileAction, state.actions(for: item).canExtract else { return .none }
        state.isPerformingFileAction = true
        state.fileActionProgressMessage = L10n.Browse.progressExtracting
        let serverURL = state.serverURL
        let filesClient = filesClient
        return .run { send in
            try await send(.extractResponse(apiResult { try await operation(filesClient, serverURL) }))
        }
    }

    private func compress(_ state: inout State, items: [FileItem]) -> Effect<Action> {
        guard !state.isPerformingFileAction, state.actions(for: items).canCompress else { return .none }
        state.isPerformingFileAction = true
        state.fileActionProgressMessage = L10n.Browse.progressCompressing
        let serverURL = state.serverURL
        let filesClient = filesClient
        return .run { send in
            try await send(.compressResponse(apiResult { try await filesClient.compressItems(serverURL, items) }))
        }
    }
}
