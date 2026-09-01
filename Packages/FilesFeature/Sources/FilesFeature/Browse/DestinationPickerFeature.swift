import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Localization

/// The modal folder chooser presented for "Move" and "Upload". Navigates the same
/// `GET /api/browse` tree `BrowseFeature` uses, folders only, in place. It never performs the
/// action itself: confirming hands the chosen path back to `BrowseFeature` via
/// `delegate(.confirmed(destination:))`, which owns the transfer / upload effect.
@Reducer
public struct DestinationPickerFeature {
    private enum Constants {
        static let searchDebounce: Duration = .milliseconds(250)
        static let searchLimit = 50
    }

    public enum Purpose: Equatable, Sendable { case move, upload }

    @ObservableState
    public struct State: Equatable, Sendable {
        public var serverURL: URL
        public var purpose: Purpose
        /// The items being moved (empty for `.upload`). Held so their current parents / own
        /// paths can be ruled out as move destinations.
        public var items: [FileItem]
        /// The folder currently shown. `""` is the root location list.
        public var directoryPath: String
        /// Folders drilled through to reach `directoryPath`, oldest first. Non empty once the
        /// user has stepped into a child, which is when the leading toolbar button turns from
        /// a close button into a back button.
        public var navigationHistory: [String] = []
        public var folders: IdentifiedArrayOf<FileItem> = []
        /// Access of the folder currently shown — gates "Upload here".
        public var currentAccess: FileAccess?
        public var phase: DataPhase = .idle
        /// Searches folders recursively under `directoryPath` (`/api/search`, directories
        /// only) — cleared whenever the shown folder changes.
        public var searchQuery = ""
        /// Non nil once a search has run for the current query; folders found anywhere under
        /// `directoryPath`, not just the current level.
        public var searchResults: IdentifiedArrayOf<SearchResultItem>?
        public var isSearching = false

        public init(serverURL: URL, items: [FileItem]) {
            self.serverURL = serverURL
            self.purpose = .move
            self.items = items
            // Start in the folder the items already sit in, so the common case (moving into a
            // sibling or a nearby folder) opens right where the user is, with the breadcrumb
            // bar available to walk back up.
            self.directoryPath = items.first?.path ?? ""
        }

        public init(serverURL: URL, uploadStartingAt startPath: String) {
            self.serverURL = serverURL
            self.purpose = .upload
            self.items = []
            self.directoryPath = startPath
        }

        /// The leading toolbar button steps back up the drill path while there is one,
        /// otherwise it dismisses the sheet.
        public var canNavigateBack: Bool { !navigationHistory.isEmpty }

        /// Whether the trailing confirm button is enabled for the folder currently shown.
        /// Move: `FileClipboard.canPaste` rules (never root, never the item's own parent or a
        /// folder nested in a staged item). Upload: any non-root folder the user can upload to.
        public var canConfirm: Bool {
            switch purpose {
            case .move:
                return FileClipboard(items: items, operation: .move).canPaste(into: directoryPath, canWrite: true)
            case .upload:
                // `nil` while the folder's listing is still loading — confirm stays disabled
                // until the server says uploads are allowed here.
                return !directoryPath.isEmpty && (currentAccess?.canUpload ?? false)
            }
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case foldersResponse(Result<BrowseResult, FilesClientError>)
        case searchQueryChanged(String)
        case searchResultsResponse(Result<[SearchResultItem], FilesClientError>)
        case searchResultTapped(SearchResultItem)
        case folderTapped(FileItem)
        /// A breadcrumb segment tap — jump straight to `path` (same behavior as the bottom
        /// `BrowseBreadcrumbBar`).
        case breadcrumbTapped(path: String)
        /// Leading toolbar button while `canNavigateBack` — pops one level off the drill path.
        case backTapped
        case retryTapped
        case confirmTapped
        case cancelTapped
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case confirmed(destination: String)
            case cancelled
        }
    }

    @Dependency(\.filesClient) var filesClient
    @Dependency(\.continuousClock) var clock
    private enum CancelID { case load, search }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.folders.isEmpty, state.phase.errorMessage == nil, state.phase != .loading else { return .none }
                return load(&state)

            case .retryTapped:
                return load(&state)

            case let .foldersResponse(.success(result)):
                state.phase = .loaded
                state.currentAccess = result.access
                state.folders = IdentifiedArray(
                    uniqueElements: BrowseFeature.sortedAlphabetically(result.items.filter(\.isDirectory))
                )
                return .none

            case let .foldersResponse(.failure(error)):
                state.phase = .failed(error == .sessionExpired ? error.userMessage : L10n.Browse.destinationPickerLoadFailed)
                return .none

            case let .searchQueryChanged(query):
                state.searchQuery = query
                return search(&state)

            case let .searchResultsResponse(.success(results)):
                state.isSearching = false
                state.searchResults = IdentifiedArray(
                    uniqueElements: BrowseFeature.sortedAlphabetically(results.filter(\.isDirectory))
                )
                return .none

            case .searchResultsResponse(.failure):
                state.isSearching = false
                state.searchResults = []
                return .none

            case let .searchResultTapped(result):
                state.navigationHistory.append(state.directoryPath)
                state.directoryPath = result.id
                state.searchQuery = ""
                state.searchResults = nil
                return load(&state)

            case let .folderTapped(folder):
                guard folder.isDirectory else { return .none }
                state.navigationHistory.append(state.directoryPath)
                state.directoryPath = folder.id
                state.searchQuery = ""
                state.searchResults = nil
                return load(&state)

            case let .breadcrumbTapped(path):
                guard path != state.directoryPath else { return .none }
                truncateHistory(&state, to: path)
                state.directoryPath = path
                state.searchQuery = ""
                state.searchResults = nil
                return load(&state)

            case .backTapped:
                guard let previous = state.navigationHistory.popLast() else { return .none }
                state.directoryPath = previous
                state.searchQuery = ""
                state.searchResults = nil
                return load(&state)

            case .confirmTapped:
                guard state.canConfirm else { return .none }
                return .send(.delegate(.confirmed(destination: state.directoryPath)))

            case .cancelTapped:
                return .send(.delegate(.cancelled))

            case .delegate:
                return .none
            }
        }
    }

    /// A breadcrumb jump lands on an ancestor of the current folder, so the drill path is
    /// trimmed to the folders that still sit above the tapped one.
    private func truncateHistory(_ state: inout State, to path: String) {
        state.navigationHistory = state.navigationHistory.filter { entry in
            entry.isEmpty ? !path.isEmpty : path.hasPrefix(entry + "/")
        }
    }

    private func load(_ state: inout State) -> Effect<Action> {
        state.phase = .loading
        state.isSearching = false
        // Drop the previous folder's access so an upload confirm can't fire against stale info.
        state.currentAccess = nil
        let serverURL = state.serverURL
        let directoryPath = state.directoryPath
        let filesClient = self.filesClient
        return .merge(
            .cancel(id: CancelID.search),
            .run { send in
                await send(.foldersResponse(try await apiResult { try await filesClient.browse(serverURL, directoryPath) }))
            }
            .cancellable(id: CancelID.load, cancelInFlight: true)
        )
    }

    /// Recursive folder search scoped to the subtree under `directoryPath`, debounced.
    private func search(_ state: inout State) -> Effect<Action> {
        guard !state.searchQuery.isEmpty else {
            state.searchResults = nil
            state.isSearching = false
            return .cancel(id: CancelID.search)
        }
        state.isSearching = true
        let serverURL = state.serverURL
        let scope = state.directoryPath
        let query = state.searchQuery
        let filesClient = self.filesClient
        let clock = self.clock
        return .run { send in
            try await clock.sleep(for: Constants.searchDebounce)
            await send(.searchResultsResponse(try await apiResult {
                try await filesClient.search(serverURL, scope, query, Constants.searchLimit)
            }))
        }
        .cancellable(id: CancelID.search, cancelInFlight: true)
    }
}
