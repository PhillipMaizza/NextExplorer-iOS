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
            state.renameSheetItem = item
            return .none

        case let .deleteTapped(item):
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
            // A rename from a preview keeps the cover up: repoint it at the renamed item
            // so its title/actions follow.
            if state.previewItem?.id == result.originalID {
                state.previewItem = result.renamed
            }
            syncListingCache(state)
            // The Mac inspector follows the rename instead of showing the old path.
            if state.infoItem?.id == result.originalID {
                return loadInfo(&state, item: result.renamed)
            }
            return .none

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
            recordUndo(&state, FileUndoEntry(.madeNew(folder)))
            syncListingCache(state)
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

        case let .deleteResponse(.success(result)):
            state.isPerformingFileAction = false
            state.items.remove(id: result.itemID)
            let wasFavorited = state.favoritePaths.remove(result.itemID) != nil
            syncListingCache(state)
            return wasFavorited ? .send(.delegate(.favoritesChanged)) : .none

        case let .deleteResponse(.failure(error)):
            state.isPerformingFileAction = false
            state.fileActionErrorMessage = error.userMessage
            return refetchAfterAmbiguousFailure(&state, error)

        case let .extractZipTapped(item):
            guard !state.isPerformingFileAction else { return .none }
            state.isPerformingFileAction = true
            state.fileActionProgressMessage = L10n.Browse.progressExtracting
            let serverURL = state.serverURL
            let filesClient = filesClient
            return .run { send in
                try await send(.extractZipResponse(apiResult { try await filesClient.extractZip(serverURL, item)
                }))
            }

        case let .extractZipResponse(.success(extracted)):
            state.isPerformingFileAction = false
            state.fileActionProgressMessage = nil
            state.items.append(extracted)
            syncListingCache(state)
            return .none

        case let .extractZipResponse(.failure(error)):
            state.isPerformingFileAction = false
            state.fileActionProgressMessage = nil
            state.fileActionErrorMessage = error.userMessage
            return refetchAfterAmbiguousFailure(&state, error)

        case let .compressTapped(item):
            guard !state.isPerformingFileAction else { return .none }
            state.isPerformingFileAction = true
            state.fileActionProgressMessage = L10n.Browse.progressCompressing
            let serverURL = state.serverURL
            let filesClient = filesClient
            return .run { send in
                try await send(.compressResponse(apiResult { try await filesClient.compressItem(serverURL, item)
                }))
            }

        case let .compressResponse(.success(compressed)):
            state.isPerformingFileAction = false
            state.fileActionProgressMessage = nil
            state.items.append(compressed)
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
}
