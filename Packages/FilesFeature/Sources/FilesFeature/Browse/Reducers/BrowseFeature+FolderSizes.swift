import ComposableArchitecture
import CoreModels
import FilesClient
import FolderPickerFeature
import Foundation

private extension FilesClientError {
    /// The folder size routes answer 404 while the server has the feature off.
    var isMissingRoute: Bool {
        switch self {
        case let .server(statusCode), let .serverMessage(statusCode, _): statusCode == 404
        default: false
        }
    }
}

extension BrowseFeature {
    /// The waits between reads of a size the server is still working on (a copied folder, a rescan):
    /// a bounded backoff on the folders in view, so a large tree is never polled for long.
    static let folderSizeRetryDelays: [Duration] = [.seconds(2), .seconds(4), .seconds(8), .seconds(15), .seconds(15)]

    /// Keeps the server's folder size mode for the folders pushed later, which never ask for it.
    /// Turning it off also drops every figure on screen.
    func rememberFolderSizeMode(_ state: inout State, _ mode: FolderSizeMode) -> Effect<Action> {
        state.folderSizeMode = mode
        if mode == .off {
            state.folderSizes = [:]
            state.refreshingFolderSizeIDs = []
        }
        let jsonCacheStore = jsonCacheStore
        let serverURL = state.serverURL
        let cacheScope = state.cacheScope
        return .run { _ in
            ListCache.save(
                jsonCacheStore,
                Self.folderSizeModeCacheNamespace,
                serverURL: serverURL,
                scope: cacheScope,
                value: mode
            )
        }
    }

    /// Reads the indexed size of the folders in the listing (the first 500). Sizes only add to the
    /// rows, so a failed read leaves them as they were; a 404 means the server turned the feature off.
    func loadFolderSizes(_ state: State, attempt: Int = 0) -> Effect<Action> {
        guard state.folderSizeMode != .off, state.phase == .loaded else { return .none }
        let paths = state.items.filter(\.isDirectory).map(\.id)
        guard !paths.isEmpty else { return .none }
        let serverURL = state.serverURL
        let filesClient = filesClient
        return .run { send in
            do {
                let sizes = try await filesClient.folderSizes(serverURL, paths)
                guard !Task.isCancelled else { return }
                await send(.folderSizesResponse(attempt: attempt, sizes))
            } catch let error as FilesClientError where error.isMissingRoute {
                await send(.folderSizesUnavailable)
            } catch {}
        }
        .cancellable(id: CancelID.folderSizes, cancelInFlight: true)
    }

    func reduceFolderSizes(_ state: inout State, _ action: Action) -> Effect<Action> {
        switch action {
        case let .folderSizesResponse(attempt, sizes):
            for (id, entry) in sizes {
                state.folderSizes[id] = entry.shownBytes
            }
            let isSettling = sizes.values.contains(where: \.dirty) || !state.refreshingFolderSizeIDs.isEmpty
            guard isSettling, attempt < Self.folderSizeRetryDelays.count else {
                state.refreshingFolderSizeIDs = []
                return .none
            }
            let delay = Self.folderSizeRetryDelays[attempt]
            let clock = clock
            return .run { send in
                try await clock.sleep(for: delay)
                await send(.folderSizesDue(attempt: attempt + 1))
            }
            .cancellable(id: CancelID.folderSizes, cancelInFlight: true)

        case let .folderSizesDue(attempt):
            return loadFolderSizes(state, attempt: attempt)

        case .folderSizesUnavailable:
            return rememberFolderSizeMode(&state, .off)

        case let .folderSizeRefreshTapped(id):
            guard state.folderSizeMode != .off, state.items[id: id]?.isDirectory == true else { return .none }
            state.refreshingFolderSizeIDs.insert(id)
            let serverURL = state.serverURL
            let filesClient = filesClient
            return .run { send in
                try await send(.folderSizeRefreshResponse(id, apiResult {
                    try await filesClient.refreshFolderSize(serverURL, id)
                }))
            }

        case .folderSizeRefreshResponse(_, .success):
            return loadFolderSizes(state)

        case let .folderSizeRefreshResponse(id, .failure(error)):
            state.refreshingFolderSizeIDs.remove(id)
            state.fileActionErrorMessage = error.userMessage
            return .none

        case .delegate(.directoryContentsChanged):
            // A copy, move or undo into a folder on screen changes its size without reloading the listing.
            return loadFolderSizes(state)

        default:
            return .none
        }
    }
}
