import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation

extension FavoritesFeature {
    func reduceInfo(_ state: inout State, _ action: Action) -> Effect<Action> {
        switch action {
        case let .tableSelectionChanged(ids):
            state.tableSelection = ids
            guard state.infoItem != nil, ids.count == 1, let favorite = state.favorite(id: ids.first),
                  favorite.path != state.infoItem?.id
            else { return .none }
            return loadInfo(&state, favorite: favorite)

        case .infoSelectionTapped:
            guard state.tableSelection.count == 1, let favorite = state.favorite(id: state.tableSelection.first)
            else { return .none }
            guard favorite.path != state.infoItem?.id else { return closeInfo(&state) }
            return loadInfo(&state, favorite: favorite)

        case let .infoTapped(favorite):
            return loadInfo(&state, favorite: favorite)

        case .infoDismissed:
            return closeInfo(&state)

        case let .infoMetadataResponse(.success(metadata)):
            state.infoPhase = .loaded
            state.infoMetadata = metadata
            return .none

        case let .infoMetadataResponse(.failure(error)):
            state.infoPhase = .failed(error.userMessage)
            return .none

        case let .infoUsageResponse(.success(usage)):
            state.infoUsage = usage.isMeaningful ? usage : nil
            return .none

        case .infoUsageResponse(.failure):
            return .none

        default:
            return .none
        }
    }

    private func loadInfo(_ state: inout State, favorite: Favorite) -> Effect<Action> {
        let item = favorite.fileItem(modified: date.now)
        state.infoItem = item
        state.infoMetadata = nil
        state.infoUsage = nil
        state.infoPhase = .loading
        return FileInfoLoad.effect(
            for: item,
            serverURL: state.serverURL,
            metadata: Action.infoMetadataResponse,
            usage: Action.infoUsageResponse
        )
        .cancellable(id: CancelID.info, cancelInFlight: true)
    }

    func closeInfo(_ state: inout State) -> Effect<Action> {
        state.infoItem = nil
        state.infoMetadata = nil
        state.infoUsage = nil
        state.infoPhase = .idle
        return .cancel(id: CancelID.info)
    }
}

private extension FavoritesFeature.State {
    func favorite(id: Favorite.ID?) -> Favorite? {
        id.flatMap { favorites[id: $0] }
    }
}

extension Favorite {
    func fileItem(modified: Date) -> FileItem {
        let parts = path.split(separator: "/").map(String.init)
        return FileItem(
            name: folderName,
            path: parts.dropLast().joined(separator: "/"),
            dateModified: modified,
            size: 0,
            kind: FileItem.directoryKind
        )
    }
}
