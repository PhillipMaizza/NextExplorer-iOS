import ComposableArchitecture
import CoreModels
import DesignSystem
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
        static let searchLimit = 50
    }

    public enum Purpose: Equatable, Sendable { case move, upload, restore }

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
        /// Access of the folder currently shown: gates "Upload here".
        public var currentAccess: FileAccess?
        public var phase: DataPhase = .idle
        /// Searches folders recursively under `directoryPath` (`/api/search`, directories
        /// only): cleared whenever the shown folder changes.
        public var searchQuery = ""
        /// Non nil once a search has run for the current query; folders found anywhere under
        /// `directoryPath`, not just the current level.
        public var searchResults: IdentifiedArrayOf<SearchResultItem>?
        public var isSearching = false
        /// Folders this user last moved or copied into, newest first. Best effort: empty until the
        /// server answers, and left empty when it can't.
        public var recents: [String] = []

        /// The recents worth offering from here: the folder already on screen is not a shortcut.
        public var displayedRecents: [String] {
            recents.filter { $0 != directoryPath }
        }

        /// Whether the list leads with a Recent section: on the folder the picker opened on, with
        /// nothing typed, so a deep folder is not cluttered by it.
        public var showsRecentsSection: Bool {
            navigationHistory.isEmpty && searchQuery.isEmpty && !displayedRecents.isEmpty
        }

        /// True once the term is long enough for the server: the folder search replaces the listing.
        public var showsSearchResults: Bool {
            SearchTerm(searchQuery).isSearchable
        }

        /// A newer folder search is running over results already on screen. With nothing on
        /// screen yet the whole list is a spinner instead.
        public var isRefiningSearch: Bool {
            isSearching && searchResults?.isEmpty == false
        }

        /// Typed, but too short for the server: this level's folders are filtered by name and a
        /// hint says how many characters the search needs.
        public var isSearchTermTooShort: Bool {
            SearchTerm(searchQuery).isTooShort
        }

        /// This level's folders, narrowed by name while the term is too short for the server.
        public var displayedFolders: IdentifiedArrayOf<FileItem> {
            let term = SearchTerm(searchQuery)
            guard term.isTooShort else { return folders }
            return folders.filter { term.matches($0.name) }
        }

        public init(serverURL: URL, items: [FileItem]) {
            self.serverURL = serverURL
            purpose = .move
            self.items = items
            // Start in the folder the items already sit in, so the common case (moving into a
            // sibling or a nearby folder) opens right where the user is, with the breadcrumb
            // bar available to walk back up.
            directoryPath = items.first?.path ?? ""
        }

        public init(serverURL: URL, uploadStartingAt startPath: String) {
            self.serverURL = serverURL
            purpose = .upload
            items = []
            directoryPath = startPath
        }

        /// A folder to restore trashed items into, starting at the root location list.
        public init(serverURL: URL, restoringFrom startPath: String) {
            self.serverURL = serverURL
            purpose = .restore
            items = []
            directoryPath = startPath
        }

        /// The leading toolbar button steps back up the drill path while there is one,
        /// otherwise it dismisses the sheet.
        public var canNavigateBack: Bool {
            !navigationHistory.isEmpty
        }

        /// Whether the trailing confirm button is enabled for the folder currently shown.
        /// Move: `FileClipboard.canPaste` rules (never root, never the item's own parent or a
        /// folder nested in a staged item). Upload: any non-root folder the user can upload to.
        public var canConfirm: Bool {
            switch purpose {
            case .move:
                FileClipboard(items: items, operation: .move).canPaste(into: directoryPath, canWrite: true)
            case .upload:
                // `nil` while the folder's listing is still loading: confirm stays disabled
                // until the server says uploads are allowed here.
                !directoryPath.isEmpty && (currentAccess?.canUpload ?? false)
            case .restore:
                // The server checks the right to create each item; this only rules out the root.
                !directoryPath.isEmpty && currentAccess != nil
            }
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case foldersResponse(Result<BrowseResult, FilesClientError>)
        case searchQueryChanged(String)
        case searchResultsResponse(Result<[SearchResultItem], FilesClientError>)
        case searchResultTapped(SearchResultItem)
        case recentsResponse([String])
        case recentTapped(String)
        case folderTapped(FileItem)
        /// A breadcrumb segment tap: jump straight to `path` (same behavior as the bottom
        /// `BrowseBreadcrumbBar`).
        case breadcrumbTapped(path: String)
        /// Leading toolbar button while `canNavigateBack`: pops one level off the drill path.
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
    private enum CancelID { case load, search, recents }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.folders.isEmpty, state.phase.errorMessage == nil,
                      state.phase != .loading else { return .none }
                // One after the other: the folders are what the user is waiting for, and a fixed order
                // keeps the two answers from racing each other.
                return .concatenate(load(&state), loadRecents(state))

            case .retryTapped:
                return load(&state)

            case let .foldersResponse(.success(result)):
                state.phase = .loaded
                state.currentAccess = result.access
                state.folders = IdentifiedArray(
                    uniqueElements: result.items.filter(\.isDirectory).sorted(by: Self.byName)
                )
                return .none

            case let .foldersResponse(.failure(error)):
                state
                    .phase = .failed(error == .sessionExpired
                        ? L10n.Error.sessionExpired
                        : L10n.Browse.destinationPickerLoadFailed)
                return .none

            case let .searchQueryChanged(query):
                // A typed space or a resent binding leaves the term unchanged: the pending
                // search keeps its debounce instead of starting over.
                let isNewTerm = SearchTerm(query) != SearchTerm(state.searchQuery)
                state.searchQuery = query
                guard isNewTerm else { return .none }
                return search(&state)

            case let .searchResultsResponse(.success(results)):
                state.isSearching = false
                state.searchResults = IdentifiedArray(
                    uniqueElements: results.filter(\.isDirectory).sorted(by: Self.byName)
                )
                return .none

            case .searchResultsResponse(.failure):
                state.isSearching = false
                state.searchResults = []
                return .none

            case let .searchResultTapped(result):
                return drill(&state, into: result.id)

            case let .folderTapped(folder):
                guard folder.isDirectory else { return .none }
                return drill(&state, into: folder.id)

            case let .recentsResponse(paths):
                // Paths come from the server; a blank or repeated one would only break the list.
                state.recents = paths.reduce(into: []) { result, path in
                    if !path.isEmpty, !result.contains(path) {
                        result.append(path)
                    }
                }
                return .none

            case let .recentTapped(path):
                guard path != state.directoryPath else { return .none }
                return drill(&state, into: path)

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

    /// Steps into `path`, remembering where it came from so Back returns there.
    private func drill(_ state: inout State, into path: String) -> Effect<Action> {
        state.navigationHistory.append(state.directoryPath)
        state.directoryPath = path
        state.searchQuery = ""
        state.searchResults = nil
        return load(&state)
    }

    /// The recent destinations are a convenience: a failed load leaves the list empty without a word.
    private func loadRecents(_ state: State) -> Effect<Action> {
        let serverURL = state.serverURL
        let filesClient = filesClient
        return .run { send in
            await send(.recentsResponse((try? filesClient.recentDestinations(serverURL)) ?? []))
        }
        .cancellable(id: CancelID.recents, cancelInFlight: true)
    }

    /// A breadcrumb jump lands on an ancestor of the current folder, so the drill path is
    /// trimmed to the folders that still sit above the tapped one.
    private func truncateHistory(_ state: inout State, to path: String) {
        state.navigationHistory = state.navigationHistory.filter { entry in
            entry.isEmpty ? !path.isEmpty : path.hasPrefix(entry + "/")
        }
    }

    private static func byName(_ lhs: some FolderNamed, _ rhs: some FolderNamed) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func load(_ state: inout State) -> Effect<Action> {
        state.phase = .loading
        state.isSearching = false
        // Drop the previous folder's access so an upload confirm can't fire against stale info.
        state.currentAccess = nil
        let serverURL = state.serverURL
        let directoryPath = state.directoryPath
        let filesClient = filesClient
        return .merge(
            .cancel(id: CancelID.search),
            .run { send in
                try await send(.foldersResponse(apiResult { try await filesClient.browse(serverURL, directoryPath) }))
            }
            .cancellable(id: CancelID.load, cancelInFlight: true)
        )
    }

    /// Recursive folder search scoped to the subtree under `directoryPath`, debounced.
    private func search(_ state: inout State) -> Effect<Action> {
        let term = SearchTerm(state.searchQuery)
        // The server only searches from three characters on.
        guard term.isSearchable else {
            state.searchResults = nil
            state.isSearching = false
            return .cancel(id: CancelID.search)
        }
        state.isSearching = true
        let serverURL = state.serverURL
        let scope = state.directoryPath
        let query = term.text
        let filesClient = filesClient
        let clock = clock
        return .run { send in
            try await clock.sleep(for: FilesClient.searchDebounce)
            try await send(.searchResultsResponse(apiResult {
                try await filesClient.search(serverURL, scope, query, Constants.searchLimit).items
            }))
        }
        .cancellable(id: CancelID.search, cancelInFlight: true)
    }
}

/// Folder listings and folder search results, both sorted by name in the picker.
protocol FolderNamed {
    var name: String { get }
}

extension FileItem: FolderNamed {}
extension SearchResultItem: FolderNamed {}
