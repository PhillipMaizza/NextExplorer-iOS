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

    public enum Purpose: Equatable, Sendable { case move, copy, upload, restore, replaceFile }

    @ObservableState
    public struct State: Equatable, Sendable {
        public static let sidebarRecentLimit = 5

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
        /// `.replaceFile` only: the file picked in the folder on screen. Folders are never picked,
        /// they are opened; changing folder clears it.
        public var selectedFilePath: String?
        public var selectedFolderPath: String?
        /// `.replaceFile` only: a file found by search, picked once its folder has been listed.
        public var pendingFileSelection: String?
        public var phase: DataPhase = .idle
        /// Searches folders recursively under `directoryPath` (`/api/search`, directories
        /// only): cleared whenever the shown folder changes.
        public var searchQuery = ""
        /// Folders found anywhere under `directoryPath`, not just the current level.
        public var searchResults: IdentifiedArrayOf<SearchResultItem> = []
        /// The folder search for the current query: idle until a searchable term is typed.
        public var searchPhase: DataPhase = .idle
        /// Folders this user last moved or copied into, newest first. Best effort: empty until the
        /// server answers, and left empty when it can't.
        public var recents: [String] = []
        public var locations: [FileItem] = []
        public var files: [FileItem] = []
        public var shareName: String?
        public var newFolder: NewFolderDraft?

        public var crumbs: [PathCrumb] {
            PathCrumb.trail(for: directoryPath, shareName: shareName)
        }

        public var destinationTrail: String {
            PathTrail.text(destinationCrumbs.map(\.title).joined(separator: "/"))
        }

        public var destinationName: String {
            destinationCrumbs.last?.title ?? ""
        }

        private var destinationCrumbs: [PathCrumb] {
            PathCrumb.trail(for: transferDestination, shareName: shareName)
        }

        public var sidebarRecents: [String] {
            Array(recents.prefix(Self.sidebarRecentLimit))
        }

        public var activeLocation: String? {
            guard !sidebarRecents.contains(directoryPath) else { return nil }
            return locations.map(\.id).first { $0 == directoryPath || directoryPath.hasPrefix("\($0)/") }
        }

        public var canCreateFolder: Bool {
            purpose != .replaceFile && !directoryPath.isEmpty && !showsSearchResults
                && (currentAccess?.canCreateFolder ?? false)
        }

        public var refusal: FileClipboard.Refusal? {
            guard phase == .loaded else { return nil }
            switch purpose {
            case .move, .copy: return transferRefusal
            case .upload, .restore, .replaceFile: return nil
            }
        }

        private var transferRefusal: FileClipboard.Refusal? {
            FileClipboard(items: items, operation: purpose == .copy ? .copy : .move)
                .refusal(into: transferDestination, canReceive: currentAccess?.canReceive(items) ?? false)
        }

        /// The recents worth offering from here: the folder already on screen is not a shortcut.
        public var displayedRecents: [String] {
            recents.filter { $0 != directoryPath }
        }

        /// Whether the list leads with a Recent section: on the folder the picker opened on, with
        /// nothing typed, so a deep folder is not cluttered by it.
        public var showsRecentsSection: Bool {
            navigationHistory.isEmpty && searchQuery.isEmpty && !displayedRecents.isEmpty
        }

        public var showsLocationsSection: Bool {
            navigationHistory.isEmpty && searchQuery.isEmpty && !directoryPath.isEmpty && !locations.isEmpty
        }

        /// True once the term is long enough for the server: the folder search replaces the listing.
        public var showsSearchResults: Bool {
            SearchTerm(searchQuery).isSearchable
        }

        /// A newer folder search is running over results already on screen. With nothing on
        /// screen yet the whole list is a spinner instead.
        public var isRefiningSearch: Bool {
            searchPhase == .loading && !searchResults.isEmpty
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
            return folders.filter { folder in
                term.matches(PersonalSpace.displayName(forSegment: folder.name, isFirstSegment: folder.path.isEmpty))
            }
        }

        public init(serverURL: URL, items: [FileItem], isCopy: Bool = false) {
            self.serverURL = serverURL
            purpose = isCopy ? .copy : .move
            self.items = items
            // Start in the folder the items already sit in, so the common case (moving into a
            // sibling or a nearby folder) opens right where the user is, with the breadcrumb
            // bar available to walk back up.
            directoryPath = items.first?.path ?? ""
        }

        /// Picks an existing file to overwrite with a version of `file`, starting in its folder.
        /// `file` itself is left out of the choices.
        public init(serverURL: URL, replacing file: FileItem) {
            self.serverURL = serverURL
            purpose = .replaceFile
            items = [file]
            directoryPath = file.path
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

        public var transferDestination: String {
            selectedFolderPath ?? directoryPath
        }

        /// Whether the trailing confirm button is enabled for the folder currently shown.
        /// Move: `FileClipboard.canPaste` rules (never root, never the item's own parent or a
        /// folder nested in a staged item). Upload: any non-root folder the user can upload to.
        public var canConfirm: Bool {
            switch purpose {
            case .move, .copy:
                transferRefusal == nil
            case .upload:
                // `nil` while the folder's listing is still loading: confirm stays disabled
                // until the server says uploads are allowed here.
                !directoryPath.isEmpty && (currentAccess?.canUpload ?? false)
            case .restore:
                // The server checks the right to create each item; this only rules out the root.
                !directoryPath.isEmpty && currentAccess != nil
            case .replaceFile:
                selectedFilePath != nil && (currentAccess?.canWrite ?? false)
            }
        }
    }

    public struct NewFolderDraft: Equatable, Sendable {
        public var name = ""
        public var phase: DataPhase = .idle

        public var trimmedName: String {
            name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        public var problem: String? {
            FileNameRule.problem(forTrimmed: trimmedName)?.message
        }

        public var canCreate: Bool {
            FileNameRule.isAcceptable(trimmed: trimmedName) && phase != .loading
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case foldersResponse(Result<BrowseResult, FilesClientError>)
        case locationsResponse([FileItem])
        case locationTapped(String)
        case newFolderTapped
        case newFolderNameChanged(String)
        case newFolderConfirmed
        case newFolderCancelled
        case newFolderResponse(Result<FileItem, FilesClientError>)
        case personalSpaceAvailable
        case searchQueryChanged(String)
        case searchResultsResponse(Result<[SearchResultItem], FilesClientError>, term: String)
        case searchResultTapped(SearchResultItem)
        case recentsResponse([String])
        case recentTapped(String)
        case folderTapped(FileItem)
        /// `.replaceFile`: the row now highlighted, a file to pick or a folder to ignore.
        case rowSelected(String?)
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
    private enum CancelID { case load, search, recents, locations, newFolder }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.folders.isEmpty, state.phase.errorMessage == nil,
                      state.phase != .loading else { return .none }
                // One after the other: the folders are what the user is waiting for, and a fixed order
                // keeps the two answers from racing each other.
                return .concatenate(load(&state), loadRecents(state), loadLocations(state))

            case .retryTapped:
                return load(&state)

            case let .foldersResponse(.success(result)):
                state.phase = .loaded
                state.currentAccess = result.access
                state.shareName = result.shareInfo?.name
                state.folders = IdentifiedArray(uniqueElements: Self.choices(from: result.items, for: state))
                state.files = state.purpose == .replaceFile || state.directoryPath.isEmpty
                    ? []
                    : result.items.filter { !$0.isDirectory }.sorted(by: Self.byName)
                state.selectedFilePath = state.pendingFileSelection.flatMap { state.folders[id: $0] }
                    .flatMap { $0.isDirectory ? nil : $0.id }
                state.pendingFileSelection = nil
                return .none

            case .personalSpaceAvailable:
                guard state.phase == .loaded, state.directoryPath.isEmpty, state.purpose != .replaceFile,
                      state.folders[id: PersonalSpace.rootPath] == nil else { return .none }
                state.folders.insert(Self.personalSpaceFolder, at: 0)
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
                state.selectedFolderPath = nil
                return search(&state)

            case let .searchResultsResponse(_, term) where term != SearchTerm(state.searchQuery).text:
                return state.searchPhase == .loading ? search(&state, isDebounced: false) : .none

            case let .searchResultsResponse(.success(results), _):
                state.searchPhase = .loaded
                let source = state.purpose == .replaceFile ? state.items.first?.id : nil
                state.searchResults = IdentifiedArray(
                    uniqueElements: results
                        .filter { ($0.isDirectory || state.purpose == .replaceFile) && $0.id != source }
                        .sorted(by: Self.byName)
                )
                return .none

            case let .searchResultsResponse(.failure(error), _):
                state.searchResults = []
                state.searchPhase = .failed(error == .sessionExpired
                    ? L10n.Error.sessionExpired
                    : L10n.Browse.searchFailed)
                return .none

            case let .searchResultTapped(result):
                guard result.isDirectory else {
                    // A file found while replacing one: open its folder and pick it once listed.
                    let effect = drill(&state, into: result.path)
                    state.pendingFileSelection = result.id
                    return effect
                }
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

            case let .locationsResponse(locations):
                state.locations = locations
                return .none

            case let .locationTapped(path):
                guard path != state.directoryPath else { return .none }
                return drill(&state, into: path)

            case .newFolderTapped:
                guard state.canCreateFolder else { return .none }
                state.newFolder = NewFolderDraft()
                return .none

            case let .newFolderNameChanged(name):
                state.newFolder?.name = name
                if state.newFolder?.phase.errorMessage != nil {
                    state.newFolder?.phase = .idle
                }
                return .none

            case .newFolderCancelled:
                state.newFolder = nil
                return .cancel(id: CancelID.newFolder)

            case .newFolderConfirmed:
                guard let draft = state.newFolder, draft.canCreate else { return .none }
                state.newFolder?.phase = .loading
                let serverURL = state.serverURL
                let path = state.directoryPath
                let name = draft.trimmedName
                let filesClient = filesClient
                return .run { send in
                    try await send(.newFolderResponse(apiResult { try await filesClient.createFolder(
                        serverURL,
                        path,
                        name
                    ) }))
                }
                .cancellable(id: CancelID.newFolder, cancelInFlight: true)

            case let .newFolderResponse(.success(folder)):
                state.newFolder = nil
                guard folder.path == state.directoryPath else { return .none }
                #if os(iOS)
                    return drill(&state, into: folder.id)
                #else
                    state.folders[id: folder.id] = folder
                    state.folders.sort(by: Self.byName)
                    state.searchQuery = ""
                    state.selectedFolderPath = folder.id
                    return .none
                #endif

            case let .newFolderResponse(.failure(error)):
                state.newFolder?.phase = .failed(error.userMessage)
                return .none

            case let .recentTapped(path):
                guard path != state.directoryPath else { return .none }
                return drill(&state, into: path)

            case let .breadcrumbTapped(path):
                guard path != state.directoryPath else { return .none }
                truncateHistory(&state, to: path)
                state.directoryPath = path
                state.searchQuery = ""
                state.searchResults = []
                return load(&state)

            case .backTapped:
                guard let previous = state.navigationHistory.popLast() else { return .none }
                state.directoryPath = previous
                state.searchQuery = ""
                state.searchResults = []
                return load(&state)

            case let .rowSelected(id):
                switch state.purpose {
                case .replaceFile:
                    state.selectedFilePath = id.flatMap { state.folders[id: $0] }
                        .flatMap { $0.isDirectory ? nil : $0.id }
                case .move, .copy:
                    state.selectedFolderPath = id.flatMap { path in
                        let isFolder = state.folders[id: path]?.isDirectory ?? state.searchResults[id: path]?
                            .isDirectory
                        return isFolder == true ? path : nil
                    }
                case .upload, .restore:
                    break
                }
                return .none

            case .confirmTapped:
                guard state.canConfirm else { return .none }
                if state.purpose == .replaceFile {
                    guard let file = state.selectedFilePath else { return .none }
                    return .send(.delegate(.confirmed(destination: file)))
                }
                switch state.purpose {
                case .move, .copy:
                    return .send(.delegate(.confirmed(destination: state.transferDestination)))
                case .upload, .restore, .replaceFile:
                    return .send(.delegate(.confirmed(destination: state.directoryPath)))
                }

            case .cancelTapped:
                return .send(.delegate(.cancelled))

            case .delegate:
                return .none
            }
        }
    }

    /// Steps into `path`, remembering where it came from so Back returns there.
    private func drill(_ state: inout State, into path: String) -> Effect<Action> {
        state.pendingFileSelection = nil
        state.navigationHistory.append(state.directoryPath)
        state.directoryPath = path
        state.searchQuery = ""
        state.searchResults = []
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

    private func loadLocations(_ state: State) -> Effect<Action> {
        guard state.purpose != .replaceFile else { return .none }
        let serverURL = state.serverURL
        let filesClient = filesClient
        return .run { send in
            let volumes = await (try? filesClient.browse(serverURL, ""))?.items.filter(\.isDirectory) ?? []
            let hasPersonal = await (try? filesClient.serverFeatures(serverURL))?.isPersonalEnabled == true
            let personal = hasPersonal ? [Self.personalSpaceFolder] : []
            await send(.locationsResponse(personal + volumes.sorted(by: Self.byName)))
        }
        .cancellable(id: CancelID.locations, cancelInFlight: true)
    }

    /// A breadcrumb jump lands on an ancestor of the current folder, so the drill path is
    /// trimmed to the folders that still sit above the tapped one.
    private func truncateHistory(_ state: inout State, to path: String) {
        state.navigationHistory = state.navigationHistory.filter { entry in
            entry.isEmpty ? !path.isEmpty : path.hasPrefix(entry + "/")
        }
    }

    /// What a listing offers: folders to open, plus the files that can be picked when replacing one.
    private static func choices(from items: [FileItem], for state: State) -> [FileItem] {
        guard state.purpose == .replaceFile else {
            return items.filter(\.isDirectory).sorted(by: byName)
        }
        let source = state.items.first?.id
        return items
            .filter { $0.id != source }
            .sorted { $0.isDirectory == $1.isDirectory ? byName($0, $1) : $0.isDirectory }
    }

    private static func byName(_ lhs: some FolderNamed, _ rhs: some FolderNamed) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    static let personalSpaceFolder = FileItem(
        name: PersonalSpace.rootPath,
        path: "",
        dateModified: .distantPast,
        size: 0,
        kind: FileItem.directoryKind
    )

    private func load(_ state: inout State) -> Effect<Action> {
        state.phase = .loading
        state.searchPhase = .idle
        // Drop the previous folder's access so an upload confirm can't fire against stale info.
        state.currentAccess = nil
        state.selectedFilePath = nil
        state.selectedFolderPath = nil
        state.files = []
        state.newFolder = nil
        let serverURL = state.serverURL
        let directoryPath = state.directoryPath
        let filesClient = filesClient
        return .merge(
            .cancel(id: CancelID.search),
            .run { send in
                try await send(.foldersResponse(apiResult { try await filesClient.browse(serverURL, directoryPath) }))
                guard directoryPath.isEmpty,
                      await (try? filesClient.serverFeatures(serverURL))?.isPersonalEnabled == true else { return }
                await send(.personalSpaceAvailable)
            }
            .cancellable(id: CancelID.load, cancelInFlight: true)
        )
    }

    /// Recursive folder search scoped to the subtree under `directoryPath`, debounced.
    private func search(_ state: inout State, isDebounced: Bool = true) -> Effect<Action> {
        let term = SearchTerm(state.searchQuery)
        // A term too short to search is never sent.
        guard term.isSearchable else {
            state.searchResults = []
            state.searchPhase = .idle
            return .cancel(id: CancelID.search)
        }
        state.searchPhase = .loading
        let serverURL = state.serverURL
        let scope = state.directoryPath
        let query = term.text
        let filesClient = filesClient
        let clock = clock
        return .run { send in
            if isDebounced {
                try await clock.sleep(for: FilesClient.searchDebounce)
            }
            try await send(.searchResultsResponse(
                apiResult { try await filesClient.search(serverURL, scope, query, Constants.searchLimit).items },
                term: query
            ))
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
