import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Localization

extension BrowseFeature {
    func toggleFavorite(_ state: inout State, item: FileItem) -> Effect<Action> {
        let serverURL = state.serverURL
        let path = item.id
        let isCurrentlyFavorite = state.favoritePaths.contains(path)
        let filesClient = filesClient
        return .run { send in
            try await send(.favoriteToggleResponse(apiResult {
                if isCurrentlyFavorite {
                    try await filesClient.removeFavorite(serverURL, path)
                } else {
                    _ = try await filesClient.addFavorite(serverURL, path)
                }
                return FavoriteToggleResult(path: path, isFavorite: !isCurrentlyFavorite)
            }))
        }
        // A second tap on the same star before the first resolves supersedes it, so a rapid
        // double tap can never fire two competing add/remove requests for one path.
        .cancellable(id: CancelID.favorite(path), cancelInFlight: true)
    }

    func confirmRename(_ state: inout State, newName: String) -> Effect<Action> {
        guard !state.isPerformingFileAction, let item = state.renameSheetItem else { return .none }
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName != item.name else {
            state.renameSheetItem = nil
            return .none
        }
        state.isPerformingFileAction = true
        let serverURL = state.serverURL
        let filesClient = filesClient
        let originalID = item.id
        return .run { send in
            try await send(.renameResponse(apiResult {
                try await RenameResult(originalID: originalID, renamed: filesClient.renameItem(serverURL, item, trimmedName))
            }))
        }
    }

    func confirmNewFolder(_ state: inout State, name: String) -> Effect<Action> {
        guard !state.isPerformingFileAction else { return .none }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            state.isNewFolderSheetPresented = false
            return .none
        }
        state.isPerformingFileAction = true
        let serverURL = state.serverURL
        let directoryPath = state.directoryPath
        let filesClient = filesClient
        return .run { send in
            try await send(.newFolderResponse(apiResult {
                try await filesClient.createFolder(serverURL, directoryPath, trimmedName)
            }))
        }
    }

    func checkDeleteImpact(_ state: inout State, items: [FileItem]) -> Effect<Action> {
        guard !items.isEmpty else { return .none }
        let serverURL = state.serverURL
        let filesClient = filesClient
        return .run { send in
            try await send(.deleteImpactResponse(apiResult {
                try await filesClient.deleteImpact(serverURL, items)
            }))
        }
        .cancellable(id: CancelID.deleteImpact, cancelInFlight: true)
    }

    func confirmDelete(_ state: inout State, deferred: Bool = false) -> Effect<Action> {
        guard let item = state.deleteConfirmationItem else { return .none }
        state.deleteConfirmationItem = nil
        state.deleteImpactCheck = .idle
        state.isPerformingFileAction = true
        let serverURL = state.serverURL
        let filesClient = filesClient
        let clock = clock
        let itemID = item.id
        return .run { send in
            // `deferred`: let the preview cover finish dismissing first, so the row-removal
            // animation plays on the list the user is now looking at.
            if deferred {
                try await clock.sleep(for: Constants.previewActionSettleDelay)
            }
            // Animated so the row visibly slides out of the list rather than popping,
            // since removal happens on the server round trip, not the confirm tap itself.
            try await send(.deleteResponse(apiResult {
                try await filesClient.deleteItems(serverURL, [item])
                return DeleteResult(itemID: itemID)
            }), animation: .default)
        }
    }

    func confirmBulkDelete(_ state: inout State) -> Effect<Action> {
        state.bulkDeleteConfirmationIsPresented = false
        state.deleteImpactCheck = .idle
        guard !state.isBulkActionInFlight else { return .none }
        let itemsToDelete = state.selectedItemIDs.compactMap { state.items[id: $0] }
        guard !itemsToDelete.isEmpty else { return .none }
        state.isBulkActionInFlight = true
        let serverURL = state.serverURL
        let filesClient = filesClient
        let itemIDs = itemsToDelete.map(\.id)
        return .run { send in
            // Animated so the rows visibly slide out of the list rather than popping,
            // since removal happens on the server round trip, not the confirm tap itself.
            try await send(.bulkDeleteResponse(apiResult {
                try await filesClient.deleteItems(serverURL, itemsToDelete)
                return BulkDeleteResult(itemIDs: itemIDs)
            }), animation: .default)
        }
    }

    /// Every selected directory is toggled, mirroring the single-item context-menu action:
    /// already-favorited directories are removed, the rest are added. Best-effort per item,
    /// matching the same philosophy the sign-out flow already uses elsewhere: one failure
    /// shouldn't block toggling the rest.
    func startBulkFavorite(_ state: inout State) -> Effect<Action> {
        guard !state.isBulkActionInFlight else { return .none }
        let targets = state.selectedItemIDs
            .compactMap { state.items[id: $0] }
            .filter(\.isDirectory)
        guard !targets.isEmpty else { return .none }
        state.isBulkActionInFlight = true
        let serverURL = state.serverURL
        let favoritePaths = state.favoritePaths
        let filesClient = filesClient
        return .run { send in
            var added: [String] = []
            var removed: [String] = []
            for item in targets {
                let isCurrentlyFavorite = favoritePaths.contains(item.id)
                if isCurrentlyFavorite {
                    if await (try? filesClient.removeFavorite(serverURL, item.id)) != nil {
                        removed.append(item.id)
                    }
                } else {
                    if await (try? filesClient.addFavorite(serverURL, item.id)) != nil {
                        added.append(item.id)
                    }
                }
            }
            await send(.bulkFavoriteResponse(BulkFavoriteToggleResult(added: added, removed: removed)))
        }
    }
}
