import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import FolderPickerFeature
import Foundation
import Localization
import SwiftUI

/// The "Downloads" tab: everything `LegacyDownloadStore` has saved into
/// `Documents/Downloads`/`Caches/Downloads`. Deleting here is local-only: it never touches
/// the server, unlike every other delete action in the app (`BrowseFeature`'s `deleteTapped`).
@Reducer
public struct OfflineTabFeature {
    public enum SortOption: String, Hashable, Sendable, CaseIterable {
        case name, size, dateAdded

        var title: String {
            switch self {
            case .name: L10n.Sort.name
            case .size: L10n.Sort.size
            case .dateAdded: L10n.Sort.dateAdded
            }
        }

        var icon: Image {
            switch self {
            case .name: IconKit.textformat
            case .size: IconKit.size
            case .dateAdded: IconKit.calendar
            }
        }
    }

    @ObservableState
    public struct State: Equatable {
        public var downloads: IdentifiedArrayOf<LocalDownload> = []
        /// The load lifecycle: `.idle` → `.loaded` / `.failed` (the initial scan is local and
        /// synchronous, so `.loading` only ever shows during an explicit refresh).
        public var phase: DataPhase = .idle
        /// A failed delete, or a refresh failure over an already populated list, surfaced as a
        /// toast rather than the full screen `phase.errorMessage`.
        public var actionErrorMessage: String?

        /// The first load's failure text, if it's still the current state.
        public var errorMessage: String? {
            phase.errorMessage
        }

        public var deleteConfirmationItem: LocalDownload?
        public var renameItem: LocalDownload?
        public var searchQuery = ""
        public var sortOption: SortOption = .name
        public var sortDirection: BrowseFeature.SortDirection = .ascending
        public var isSelecting = false
        public var selectedDownloadIDs: Set<LocalDownload.ID> = []
        public var bulkDeleteConfirmationIsPresented = false
        /// Current account's downloads scope, so the tab lists only this account's files.
        @Shared(.inMemory(DownloadAccountScope.sharedKey)) public var downloadScope = ""

        /// Where pinned folders open: the tab browses them like Browse does. Nil only in tests and
        /// previews that never open one.
        public var serverURL: URL?
        public var path = StackState<BrowseFeature.State>()
        /// A pinned file opened on its own, in a cover over the tab.
        @Presents public var previewHost: BrowseFeature.State?
        /// The account the tab belongs to, so a pinned file opens from its own kept copy.
        let cacheScope: String

        public init(serverURL: URL? = nil) {
            self.serverURL = serverURL
            @Dependency(\.cacheScope) var cacheScopeSource
            cacheScope = cacheScopeSource.current()
        }

        /// Client-side filter + sort, same shape as `BrowseFeature.displayedItems`: search
        /// only ever matches against already-downloaded file names, never the server.
        public var displayedDownloads: [LocalDownload] {
            let matches = searchQuery.isEmpty
                ? Array(downloads)
                : downloads.filter { SearchMatch.matches(query: searchQuery, in: $0.fileName) }
            let sorted = matches.sorted { lhs, rhs in
                switch sortOption {
                case .name:
                    lhs.fileName.localizedCaseInsensitiveCompare(rhs.fileName) == .orderedAscending
                case .size:
                    lhs.size < rhs.size
                case .dateAdded:
                    lhs.modifiedDate < rhs.modifiedDate
                }
            }
            return sortDirection == .ascending ? sorted : sorted.reversed()
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case refreshButtonTapped
        case downloadsResponse(Result<[LocalDownload], FilesClientError>)
        case deleteTapped(LocalDownload)
        case deleteCancelled
        case deleteConfirmed
        case deleteResponse(Result<String, FilesClientError>)
        case renameTapped(LocalDownload)
        case renameCancelled
        case renameConfirmed(String)
        case renameResponse(Result<[LocalDownload], FilesClientError>)
        case searchQueryChanged(String)
        case sortOptionChanged(SortOption)
        case sortDirectionChanged(BrowseFeature.SortDirection)
        case selectModeToggled
        case itemSelectionToggled(LocalDownload.ID)
        case selectAllTapped
        case deselectAllTapped
        case bulkDeleteTapped
        case bulkDeleteCancelled
        case bulkDeleteConfirmed
        case bulkDeleteResponse([LocalDownload.ID])
        /// A pinned row or tile was tapped: a folder opens in place, a file in a preview.
        case pinnedItemTapped(OfflinePinnedRoot)
        /// A pinned folder row was tapped.
        case openFolderTapped(path: String)
        /// A pinned file row was tapped: it opens from its kept copy, with or without a connection.
        case pinnedFileTapped(path: String)
        case previewHost(PresentationAction<BrowseFeature.Action>)
        /// The pinned file's preview asked to see its share links.
        case viewSharesFromPreviewTapped
        /// Pins changed: pushed folders recompute which of their items are offline.
        case offlineAvailabilityChanged
        case path(StackActionOf<BrowseFeature>)
        case delegate(Delegate)

        /// What a folder opened from this tab asks of the rest of the app, as from Browse.
        public enum Delegate: Equatable, Sendable {
            case offlinePinRequested([FileItem])
            case offlineUnpinRequested(path: String)
            case uploadRequested([PendingUpload])
            case downloadRequested([FileItem])
            case saveRequested([DownloadSaveRequest])
            case favoritesChanged
            case goToSharedTab
        }
    }

    @Dependency(\.localDownloadStore) var localDownloadStore
    @Dependency(\.offlineFileStore) var offlineFileStore
    @Dependency(\.date) var date

    private enum CancelID { case load }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.phase.shouldLoadOnAppear else { return .none }
                // The Downloads list is a local directory scan, cheap enough to read inline.
                // Routing it through an async effect returned a frame later and flashed the
                // loading skeleton on a tab whose data is effectively instant.
                do {
                    state.downloads = try IdentifiedArray(uniqueElements: localDownloadStore.list(state.downloadScope))
                    state.phase = .loaded
                } catch {
                    state
                        .phase = .failed(((error as? FilesClientError) ?? .network(String(describing: error)))
                            .userMessage)
                }
                return .none

            case .refreshButtonTapped:
                return load(&state)

            case let .downloadsResponse(.success(downloads)):
                state.phase = .loaded
                state.downloads = IdentifiedArray(uniqueElements: downloads)
                return .none

            case let .downloadsResponse(.failure(error)):
                // Full screen error only when there's nothing to blank; a refresh failure
                // over a populated list stays `.loaded` and toasts.
                if state.downloads.isEmpty {
                    state.phase = .failed(error.userMessage)
                } else {
                    state.phase = .loaded
                    state.actionErrorMessage = error.userMessage
                }
                return .none

            case let .deleteTapped(download):
                state.deleteConfirmationItem = download
                return .none

            case .deleteCancelled:
                state.deleteConfirmationItem = nil
                return .none

            case .deleteConfirmed:
                return confirmDelete(&state)

            case let .deleteResponse(.success(id)):
                state.downloads.remove(id: id)
                return .none

            case let .deleteResponse(.failure(error)):
                state.actionErrorMessage = error.userMessage
                return .none

            case let .renameTapped(download):
                state.renameItem = download
                return .none

            case .renameCancelled:
                state.renameItem = nil
                return .none

            case let .renameConfirmed(newName):
                return confirmRename(&state, newName: newName)

            case let .renameResponse(.success(downloads)):
                state.renameItem = nil
                state.downloads = IdentifiedArray(uniqueElements: downloads)
                return .none

            case let .renameResponse(.failure(error)):
                state.renameItem = nil
                state.actionErrorMessage = error.userMessage
                return .none

            case let .searchQueryChanged(query):
                state.searchQuery = query
                return .none

            case let .sortOptionChanged(option):
                state.sortOption = option
                return .none

            case let .sortDirectionChanged(direction):
                state.sortDirection = direction
                return .none

            case .selectModeToggled:
                state.isSelecting.toggle()
                state.selectedDownloadIDs = []
                return .none

            case let .itemSelectionToggled(id):
                if state.selectedDownloadIDs.contains(id) {
                    state.selectedDownloadIDs.remove(id)
                } else {
                    state.selectedDownloadIDs.insert(id)
                }
                return .none

            case .selectAllTapped:
                state.selectedDownloadIDs = Set(state.displayedDownloads.map(\.id))
                return .none

            case .deselectAllTapped:
                state.selectedDownloadIDs = []
                return .none

            case .bulkDeleteTapped:
                guard !state.selectedDownloadIDs.isEmpty else { return .none }
                state.bulkDeleteConfirmationIsPresented = true
                return .none

            case .bulkDeleteCancelled:
                state.bulkDeleteConfirmationIsPresented = false
                return .none

            case .bulkDeleteConfirmed:
                return confirmBulkDelete(&state)

            case let .bulkDeleteResponse(deletedIDs):
                for id in deletedIDs {
                    state.downloads.remove(id: id)
                }
                state.isSelecting = false
                state.selectedDownloadIDs = []
                return .none

            case let .pinnedItemTapped(root):
                return .send(root.isDirectory ? .openFolderTapped(path: root.path) : .pinnedFileTapped(path: root.path))

            case let .openFolderTapped(path):
                guard let serverURL = state.serverURL else { return .none }
                let name = (path as NSString).lastPathComponent
                BrowseNavigation.jump(
                    to: path,
                    title: name.isEmpty ? path : name,
                    serverURL: serverURL,
                    stack: &state.path
                )
                return .none

            case let .pinnedFileTapped(path):
                guard let serverURL = state.serverURL else { return .none }
                let name = (path as NSString).lastPathComponent
                let parent = (path as NSString).deletingLastPathComponent
                // The size and date the copy was kept with, so the preview knows it is complete.
                let item = offlineFileStore.pinned(to: state.cacheScope).matchingPinnedCopy(FileItem(
                    name: name,
                    path: parent,
                    dateModified: date.now,
                    size: 0,
                    kind: (name as NSString).pathExtension.lowercased()
                ))
                let folderName = (parent as NSString).lastPathComponent
                state.previewHost = .previewHost(
                    for: item,
                    serverURL: serverURL,
                    folderTitle: folderName.isEmpty ? L10n.Browse.navigationTitle : folderName
                )
                return .send(.previewHost(.presented(.rowTapped(item))))

            case let .previewHost(.presented(.delegate(.offlinePinRequested(items)))):
                return .send(.delegate(.offlinePinRequested(items)))

            case let .previewHost(.presented(.delegate(.offlineUnpinRequested(path)))):
                return .send(.delegate(.offlineUnpinRequested(path: path)))

            case let .previewHost(.presented(.delegate(.downloadRequested(items)))):
                return .send(.delegate(.downloadRequested(items)))

            case let .previewHost(.presented(.delegate(.saveRequested(requests)))):
                return .send(.delegate(.saveRequested(requests)))

            case .previewHost(.presented(.delegate(.goToSharedTab))), .viewSharesFromPreviewTapped:
                state.previewHost = nil
                return .send(.delegate(.goToSharedTab))

            case .previewHost(.presented(.previewDismissed)),
                 .previewHost(.presented(.deleteResponse(.success))):
                // Closing the preview, or deleting its file, returns to the tab.
                state.previewHost = nil
                return .none

            case .previewHost:
                return .none

            case let .path(.element(id: _, action: .delegate(.openFolder(item)))):
                guard let serverURL = state.serverURL else { return .none }
                state.path.append(BrowseNavigation.screen(for: item, serverURL: serverURL))
                return .none

            case let .path(.element(id: _, action: .delegate(.openPath(path, title)))):
                guard let serverURL = state.serverURL else { return .none }
                BrowseNavigation.jump(to: path, title: title, serverURL: serverURL, stack: &state.path)
                return .none

            case let .path(.element(id: _, action: .delegate(.offlinePinRequested(items)))):
                return .send(.delegate(.offlinePinRequested(items)))

            case let .path(.element(id: _, action: .delegate(.offlineUnpinRequested(path)))):
                return .send(.delegate(.offlineUnpinRequested(path: path)))

            case let .path(.element(id: _, action: .delegate(.uploadRequested(files)))):
                return .send(.delegate(.uploadRequested(files)))

            case let .path(.element(id: _, action: .delegate(.downloadRequested(items)))):
                return .send(.delegate(.downloadRequested(items)))

            case let .path(.element(id: _, action: .delegate(.saveRequested(requests)))):
                return .send(.delegate(.saveRequested(requests)))

            case .path(.element(id: _, action: .delegate(.favoritesChanged))):
                return .send(.delegate(.favoritesChanged))

            case .path(.element(id: _, action: .delegate(.goToSharedTab))):
                return .send(.delegate(.goToSharedTab))

            case .path(.element(id: _, action: .delegate(.directoryContentsChanged))):
                return .merge(state.path.ids.map { .send(.path(.element(id: $0, action: .refreshButtonTapped))) })

            case .offlineAvailabilityChanged:
                return .merge(state.path.ids
                    .map { .send(.path(.element(id: $0, action: .computeOfflineAvailability))) })

            case .path, .delegate:
                return .none
            }
        }
        .forEach(\.path, action: \.path) {
            BrowseFeature()
        }
        .ifLet(\.$previewHost, action: \.previewHost) {
            BrowseFeature()
        }
    }

    /// The pinned items the tab shows: filtered by the search text, then ordered like the downloads.
    /// A pin has no date of its own, so "date added" keeps the order they were pinned in.
    static func displayedPinned(
        _ usages: IdentifiedArrayOf<OfflinePinnedRootUsage>,
        searchQuery: String,
        sortOption: SortOption,
        sortDirection: BrowseFeature.SortDirection
    ) -> [OfflinePinnedRootUsage] {
        let matches = usages.enumerated().filter {
            searchQuery.isEmpty || SearchMatch.matches(query: searchQuery, in: $0.element.displayName)
        }
        let sorted = matches.sorted { lhs, rhs in
            switch sortOption {
            case .name:
                lhs.element.displayName.localizedCaseInsensitiveCompare(rhs.element.displayName) == .orderedAscending
            case .size:
                lhs.element.sizeBytes < rhs.element.sizeBytes
            case .dateAdded:
                lhs.offset < rhs.offset
            }
        }
        return (sortDirection == .ascending ? sorted : sorted.reversed()).map(\.element)
    }

    private func load(_ state: inout State) -> Effect<Action> {
        state.phase = .loading
        let localDownloadStore = localDownloadStore
        let downloadScope = state.downloadScope
        return .run { send in
            try await send(.downloadsResponse(apiResult { try localDownloadStore.list(downloadScope) }))
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }

    private func confirmDelete(_ state: inout State) -> Effect<Action> {
        guard let download = state.deleteConfirmationItem else { return .none }
        state.deleteConfirmationItem = nil
        let localDownloadStore = localDownloadStore
        return .run { send in
            do {
                try localDownloadStore.delete(download.url)
                await send(.deleteResponse(.success(download.id)))
            } catch {
                guard !Task.isCancelled else { return }
                await send(.deleteResponse(.failure(Self.localStoreError(error))))
            }
        }
    }

    private func confirmRename(_ state: inout State, newName: String) -> Effect<Action> {
        guard let download = state.renameItem else { return .none }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != download.fileName else {
            state.renameItem = nil
            return .none
        }
        let localDownloadStore = localDownloadStore
        let downloadScope = state.downloadScope
        return .run { send in
            do {
                _ = try localDownloadStore.rename(download.url, trimmed)
                let list = try localDownloadStore.list(downloadScope)
                await send(.renameResponse(.success(list)))
            } catch {
                guard !Task.isCancelled else { return }
                await send(.renameResponse(.failure(Self.localStoreError(error))))
            }
        }
    }

    /// Rename/delete here are local filesystem operations, so a failure is a `CocoaError`, not a
    /// network fault. Surface the actual reason instead of the generic "network error" the
    /// shared `apiResult` boxing would produce. `serverMessage`'s `userMessage` is exactly the
    /// carried string; the status code is unused for that case.
    private static func localStoreError(_ error: Error) -> FilesClientError {
        if let filesError = error as? FilesClientError {
            return filesError
        }
        let message: String = switch (error as? CocoaError)?.code {
        case .fileWriteFileExists:
            L10n.Downloads.errorNameExists
        case .fileWriteInvalidFileName:
            L10n.Downloads.errorInvalidName
        case .fileNoSuchFile, .fileReadNoSuchFile:
            L10n.Downloads.errorMissing
        default:
            L10n.Downloads.errorGeneric
        }
        return .serverMessage(statusCode: 0, message: message)
    }

    /// Best-effort, matching the sign-out flow's philosophy: one file refusing to delete
    /// shouldn't block removing the rest of the selection.
    private func confirmBulkDelete(_ state: inout State) -> Effect<Action> {
        state.bulkDeleteConfirmationIsPresented = false
        let targets = state.downloads.filter { state.selectedDownloadIDs.contains($0.id) }
        guard !targets.isEmpty else { return .none }
        let localDownloadStore = localDownloadStore
        return .run { send in
            var deletedIDs: [LocalDownload.ID] = []
            for download in targets where (try? localDownloadStore.delete(download.url)) != nil {
                deletedIDs.append(download.id)
            }
            await send(.bulkDeleteResponse(deletedIDs), animation: .default)
        }
    }
}
