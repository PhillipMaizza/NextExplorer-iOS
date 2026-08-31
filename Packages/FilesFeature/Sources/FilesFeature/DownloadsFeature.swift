import ComposableArchitecture
import DesignSystem
import FilesClient
import Foundation
import Localization
import SwiftUI

/// The "Downloads" tab: everything `LocalDownloadStore` has saved into
/// `Documents/Downloads`/`Caches/Downloads`. Deleting here is local-only — it never touches
/// the server, unlike every other delete action in the app (`BrowseFeature`'s `deleteTapped`).
@Reducer
public struct DownloadsFeature {
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
        public var errorMessage: String? { phase.errorMessage }
        public var deleteConfirmationItem: LocalDownload?
        public var renameItem: LocalDownload?
        public var searchQuery = ""
        public var sortOption: SortOption = .name
        public var sortDirection: BrowseFeature.SortDirection = .ascending
        public var isSelecting = false
        public var selectedDownloadIDs: Set<LocalDownload.ID> = []
        public var bulkDeleteConfirmationIsPresented = false

        public init() {}

        /// Client-side filter + sort, same shape as `BrowseFeature.displayedItems` — search
        /// only ever matches against already-downloaded file names, never the server.
        public var displayedDownloads: [LocalDownload] {
            let matches = searchQuery.isEmpty
                ? Array(downloads)
                : downloads.filter { FuzzyMatch.matches(query: searchQuery, in: $0.fileName) }
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
    }

    @Dependency(\.localDownloadStore) var localDownloadStore

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
                    state.downloads = IdentifiedArray(uniqueElements: try localDownloadStore.list())
                    state.phase = .loaded
                } catch {
                    state.phase = .failed(((error as? FilesClientError) ?? .network(String(describing: error))).userMessage)
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
            }
        }
    }

    private func load(_ state: inout State) -> Effect<Action> {
        state.phase = .loading
        let localDownloadStore = self.localDownloadStore
        return .run { send in
            await send(.downloadsResponse(try await apiResult { try localDownloadStore.list() }))
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }

    private func confirmDelete(_ state: inout State) -> Effect<Action> {
        guard let download = state.deleteConfirmationItem else { return .none }
        state.deleteConfirmationItem = nil
        let localDownloadStore = self.localDownloadStore
        return .run { send in
            await send(.deleteResponse(try await apiResult {
                try localDownloadStore.delete(download.url)
                return download.id
            }))
        }
    }

    private func confirmRename(_ state: inout State, newName: String) -> Effect<Action> {
        guard let download = state.renameItem else { return .none }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != download.fileName else {
            state.renameItem = nil
            return .none
        }
        let localDownloadStore = self.localDownloadStore
        return .run { send in
            await send(.renameResponse(try await apiResult {
                _ = try localDownloadStore.rename(download.url, trimmed)
                return try localDownloadStore.list()
            }))
        }
    }

    /// Best-effort, matching the sign-out flow's philosophy: one file refusing to delete
    /// shouldn't block removing the rest of the selection.
    private func confirmBulkDelete(_ state: inout State) -> Effect<Action> {
        state.bulkDeleteConfirmationIsPresented = false
        let targets = state.downloads.filter { state.selectedDownloadIDs.contains($0.id) }
        guard !targets.isEmpty else { return .none }
        let localDownloadStore = self.localDownloadStore
        return .run { send in
            var deletedIDs: [LocalDownload.ID] = []
            for download in targets {
                if (try? localDownloadStore.delete(download.url)) != nil {
                    deletedIDs.append(download.id)
                }
            }
            await send(.bulkDeleteResponse(deletedIDs), animation: .default)
        }
    }
}
