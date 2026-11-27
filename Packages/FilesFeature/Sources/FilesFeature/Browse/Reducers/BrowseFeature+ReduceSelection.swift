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
    /// Selecting rows and the bulk actions on the selection.
    func reduceSelection(_ state: inout State, _ action: Action) -> Effect<Action> {
        switch action {
        case .selectModeToggled:
            state.isSelecting.toggle()
            if !state.isSelecting {
                state.selectedItemIDs = []
            }
            return .none

        case let .itemSelectionToggled(id):
            if state.selectedItemIDs.contains(id) {
                state.selectedItemIDs.remove(id)
            } else {
                state.selectedItemIDs.insert(id)
            }
            return .none

        case let .selectionSwept(ids):
            guard state.isSelecting else { return .none }
            state.selectedItemIDs = ids.intersection(state.items.ids)
            return .none

        case .selectAllTapped:
            state.selectedItemIDs = Set(state.displayedItems.map(\.id))
            return .none

        case .deselectAllTapped:
            state.selectedItemIDs = []
            return .none

        case .bulkDeleteTapped:
            let selected = state.selectedItems
            guard state.actions(for: selected).canDelete else { return .none }
            state.bulkDeletePhase = .confirming
            state.deleteImpactCheck = .checking
            return checkDeleteImpact(&state, items: selected)

        case .bulkDeleteCancelled:
            state.bulkDeletePhase = .idle
            state.deleteImpactCheck = .idle
            return .cancel(id: state.cancelID(.deleteImpact))

        case .bulkDeleteConfirmed:
            return confirmBulkDelete(&state)

        case .bulkDeletePermanentlyConfirmed:
            return confirmBulkDelete(&state, permanent: true)

        case let .bulkDeleteProgressed(fraction):
            state.bulkDeleteProgress = fraction
            return .none

        case .bulkDeleteCancelTapped:
            guard state.bulkDeleteProgress != nil else { return .none }
            state.isBulkActionInFlight = false
            state.bulkDeleteProgress = nil
            // The server stops where it was: what it already removed is gone, so read the folder again.
            return .merge(.cancel(id: state.cancelID(.bulkDelete)), load(&state))

        case let .bulkDeleteResponse(.success(result)):
            state.isBulkActionInFlight = false
            state.bulkDeleteProgress = nil
            state.isSelecting = false
            state.selectedItemIDs = []
            return applyDeleteResult(&state, result)

        case let .bulkDeleteResponse(.failure(error)):
            state.isBulkActionInFlight = false
            state.bulkDeleteProgress = nil
            state.fileActionErrorMessage = error.userMessage
            return refetchAfterAmbiguousFailure(&state, error)

        case .bulkFavoriteTapped:
            guard state.hasLoadedFavorites else { return .none }
            return startBulkFavorite(&state)

        case let .bulkFavoriteResponse(result):
            state.isBulkActionInFlight = false
            state.favoritePaths.formUnion(result.added)
            state.favoritePaths.subtract(result.removed)
            leaveSelectMode(&state)
            if result.failedCount > 0 {
                state.fileActionErrorMessage = L10n.Browse.bulkFavoriteFailed(result.failedCount, result.totalCount)
            }
            let didChangeAnything = !result.added.isEmpty || !result.removed.isEmpty
            return didChangeAnything ? .send(.delegate(.favoritesChanged)) : .none

        case .bulkDownloadTapped:
            let targets = state.selectedItems
            guard state.actions(for: targets).canDownload else { return .none }
            leaveSelectMode(&state)
            #if os(macOS)
                if targets.contains(where: \.isDirectory), targets.contains(where: { !$0.isDirectory }) {
                    state.bulkDownloadChoice = Array(targets)
                    return .none
                }
                return startBulkDownload(&state, targets: Array(targets))
            #else
                // Save to Device takes files only; folders in the selection are left out.
                let files = targets.filter { !$0.isDirectory }
                return files.isEmpty ? .none : .send(.delegate(.downloadRequested(Array(files))))
            #endif

        case let .bulkDownloadChoiceMade(choice):
            guard let targets = state.bulkDownloadChoice else { return .none }
            state.bulkDownloadChoice = nil
            #if os(macOS)
                switch choice {
                case .oneArchive: return startArchiveDownload(&state, targets: targets)
                case .separateFiles: return startBulkDownload(&state, targets: targets)
                case nil: return .none
                }
            #else
                return .none
            #endif

        case .bulkOfflineTapped:
            let targets = state.selectedItems
            guard !targets.isEmpty else { return .none }
            leaveSelectMode(&state)
            let toPin = state.actions(for: targets).canDownload
                ? targets.filter { !state.offlineItemIDs.contains($0.id) }
                : []
            if !toPin.isEmpty {
                state.offlineItemIDs.formUnion(toPin.map(\.id))
                state.offlinePinnedItemIDs.formUnion(toPin.map(\.id))
                return .send(.delegate(.offlinePinRequested(Array(toPin))))
            }
            state.offlineRemoval = offlineRemoval(of: Array(targets), state: state)
            return .none

        default:
            return .none
        }
    }

    func leaveSelectMode(_ state: inout State) {
        if state.isSelecting {
            state.selectedItemIDs = []
        }
        state.isSelecting = false
    }
}
