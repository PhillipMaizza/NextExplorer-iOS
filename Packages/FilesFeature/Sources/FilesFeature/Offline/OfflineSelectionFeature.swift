import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Localization

/// The "Download Files for Offline Use" chooser: navigates the same `GET /api/browse` tree as
/// Browse, but shows files as well as folders and lets the user multi select any mix of them. A
/// selected folder is pinned whole; its recursive size (`GET /api/usage`) is folded into the running
/// estimate so the user sees roughly how much they are about to download before confirming. Confirm
/// hands the chosen roots back to Settings, which forwards them to the `OfflineDownloadsFeature`
/// engine.
@Reducer
public struct OfflineSelectionFeature {
    @ObservableState
    public struct State: Equatable {
        public var serverURL: URL
        public var directoryPath: String
        public var navigationHistory: [String] = []
        public var items: IdentifiedArrayOf<FileItem> = []
        public var phase: DataPhase = .idle
        /// Selected roots (files or folders), keyed by `FileItem.id`, across every folder the user
        /// has drilled through.
        public var selection: [String: FileItem] = [:]
        /// Recursive byte size for each selected folder, from `fetchUsage`. Files use `item.size`
        /// directly.
        public var folderSizes: [String: Int64] = [:]
        /// Folders whose size is still being fetched, so the estimate can show "calculating".
        public var estimatingPaths: Set<String> = []
        /// Files already downloaded for offline use in the current folder. Shown pre-checked and
        /// dimmed, not selectable, and never re downloaded.
        public var alreadyOfflineIDs: Set<String> = []

        public init(serverURL: URL, startingAt path: String = "") {
            self.serverURL = serverURL
            directoryPath = path
        }

        public var canNavigateBack: Bool {
            !navigationHistory.isEmpty
        }

        public var canConfirm: Bool {
            !selection.isEmpty
        }

        public var isEstimating: Bool {
            !estimatingPaths.isEmpty
        }

        /// Total bytes the current selection would download: each selected folder's recursive size
        /// (0 until its usage lands) plus each selected file's own size.
        public var estimatedBytes: Int64 {
            selection.values.reduce(Int64(0)) { total, item in
                item.isDirectory ? total + (folderSizes[item.id] ?? 0) : total + item.size
            }
        }

        public func isSelected(_ item: FileItem) -> Bool {
            selection[item.id] != nil
        }

        public func isAlreadyOffline(_ item: FileItem) -> Bool {
            alreadyOfflineIDs.contains(item.id)
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case itemsResponse(Result<BrowseResult, FilesClientError>)
        case folderTapped(FileItem)
        case backTapped
        case breadcrumbTapped(path: String)
        case selectionToggled(FileItem)
        case usageResponse(path: String, Result<StorageUsage, FilesClientError>)
        case retryTapped
        case confirmTapped
        case cancelTapped
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case confirmed([FileItem])
            case cancelled
        }
    }

    @Dependency(\.filesClient) var filesClient
    @Dependency(\.offlineFileStore) var offlineFileStore
    private enum CancelID: Hashable { case load, usage(String) }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.items.isEmpty, state.phase.shouldLoadOnAppear else { return .none }
                return load(&state)

            case .retryTapped:
                return load(&state)

            case let .itemsResponse(.success(result)):
                state.phase = .loaded
                state.items = IdentifiedArray(
                    uniqueElements: BrowseFeature.sortedAlphabetically(result.items)
                )
                // Items already available offline are shown pre checked and dimmed, and are never re
                // downloaded: a file whose bytes are pinned, or a folder covered by a pinned root
                // (the folder itself was pinned, or an ancestor of it was).
                let pinnedPaths = offlineFileStore.pinnedRoots().map(\.path)
                state.alreadyOfflineIDs = Set(
                    result.items.compactMap { item in
                        if item.isDirectory {
                            return Self.isCovered(item.id, byPinnedRoots: pinnedPaths) ? item.id : nil
                        }
                        return offlineFileStore.localURL(item) != nil ? item.id : nil
                    }
                )
                return .none

            case let .itemsResponse(.failure(error)):
                state.phase = .failed(error == .sessionExpired ? error.userMessage : L10n.Offline.selectionLoadFailed)
                return .none

            case let .folderTapped(folder):
                guard folder.isDirectory else { return .none }
                state.navigationHistory.append(state.directoryPath)
                state.directoryPath = folder.id
                return load(&state)

            case .backTapped:
                guard let previous = state.navigationHistory.popLast() else { return .none }
                state.directoryPath = previous
                return load(&state)

            case let .breadcrumbTapped(path):
                guard path != state.directoryPath else { return .none }
                state.navigationHistory = state.navigationHistory.filter { entry in
                    entry.isEmpty ? !path.isEmpty : path.hasPrefix(entry + "/")
                }
                state.directoryPath = path
                return load(&state)

            case let .selectionToggled(item):
                // An already pinned file can't be toggled or re queued.
                guard !state.alreadyOfflineIDs.contains(item.id) else { return .none }
                if state.selection[item.id] != nil {
                    state.selection[item.id] = nil
                    state.folderSizes[item.id] = nil
                    state.estimatingPaths.remove(item.id)
                    return .cancel(id: CancelID.usage(item.id))
                }
                state.selection[item.id] = item
                guard item.isDirectory else { return .none }
                state.estimatingPaths.insert(item.id)
                let serverURL = state.serverURL
                let filesClient = filesClient
                let path = item.id
                return .run { send in
                    try await send(.usageResponse(path: path, apiResult { try await filesClient.fetchUsage(serverURL, path) }))
                }
                .cancellable(id: CancelID.usage(path), cancelInFlight: true)

            case let .usageResponse(path, .success(usage)):
                state.estimatingPaths.remove(path)
                // Ignore a size for a folder the user has since deselected.
                guard state.selection[path] != nil else { return .none }
                state.folderSizes[path] = usage.size
                return .none

            case let .usageResponse(path, .failure):
                state.estimatingPaths.remove(path)
                return .none

            case .confirmTapped:
                guard state.canConfirm else { return .none }
                return .send(.delegate(.confirmed(Array(state.selection.values))))

            case .cancelTapped:
                return .send(.delegate(.cancelled))

            case .delegate:
                return .none
            }
        }
    }

    /// Whether `path` is fully covered by an offline pin: the folder itself is a pinned root, or it
    /// sits inside one (an ancestor was pinned, so a folder wide download already includes it).
    private static func isCovered(_ path: String, byPinnedRoots roots: [String]) -> Bool {
        roots.contains { root in root == path || path.hasPrefix(root + "/") }
    }

    private func load(_ state: inout State) -> Effect<Action> {
        state.phase = .loading
        let serverURL = state.serverURL
        let directoryPath = state.directoryPath
        let filesClient = filesClient
        return .run { send in
            try await send(.itemsResponse(apiResult { try await filesClient.browse(serverURL, directoryPath) }))
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }
}
