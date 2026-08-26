import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import DesignSystem
import SwiftUI

private enum Constants {
    static let searchDebounce: Duration = .milliseconds(150)
    static let searchLimit = 50
    /// Not a network debounce (this-folder search has no round trip) — just a brief settle
    /// so a fast backspace/retype doesn't flash intermediate result sets.
    static let localSearchSettleDelay: Duration = .milliseconds(50)
}

/// One directory listing. The root browse screen and every pushed subfolder are the
/// same feature, scoped to a different `directoryPath`. Drilling into a folder is
/// signaled via `delegate(.openFolder)`/`delegate(.openPath)` rather than owning its own
/// navigation stack: `BrowseTabFeature` owns the single flat `StackState` all pushes land on.
@Reducer
public struct BrowseFeature {
    /// Where `.searchable`'s scope bar points the search request. "This Folder" is
    /// answered instantly from `items`, already loaded client-side, so no network round
    /// trip or debounce is needed. "Everywhere" mirrors the web client's own root search
    /// (`backend/src/routes/search.js`) and still needs one.
    public enum SearchScope: Hashable, Sendable, CaseIterable {
        case thisFolder, everywhere

        var title: String {
            switch self {
            case .thisFolder: "This Folder"
            case .everywhere: "Everywhere"
            }
        }
    }

    /// How `displayedItems` orders a folder's contents. Folders always sort before files
    /// regardless of option; this only decides the order within each of those two groups.
    public enum SortOption: String, Hashable, Sendable, CaseIterable {
        case name, size, dateModified, kind

        var title: String {
            switch self {
            case .name: "Name"
            case .size: "Size"
            case .dateModified: "Date Modified"
            case .kind: "Kind"
            }
        }

        var icon: Image {
            switch self {
            case .name: IconKit.textformat
            case .size: IconKit.internalDrive
            case .dateModified: IconKit.calendar
            case .kind: IconKit.tag
            }
        }
    }

    /// Which way `sortOption` orders each group. Applies uniformly regardless of option:
    /// e.g. `.size` + `.ascending` is smallest first, `.size` + `.descending` is largest first.
    public enum SortDirection: String, Hashable, Sendable, CaseIterable {
        case ascending, descending

        var title: String {
            switch self {
            case .ascending: "Ascending"
            case .descending: "Descending"
            }
        }

        var icon: Image {
            switch self {
            case .ascending: IconKit.arrowUp
            case .descending: IconKit.arrowDown
            }
        }
    }

    public struct FavoriteToggleResult: Equatable, Sendable {
        public let path: String
        public let isFavorite: Bool
    }

    public struct RenameResult: Equatable, Sendable {
        public let originalID: String
        public let renamed: FileItem
    }

    public struct DeleteResult: Equatable, Sendable {
        public let itemID: String
    }

    @ObservableState
    public struct State: Equatable, Sendable {
        public var serverURL: URL
        public var directoryPath: String
        public var title: String
        public var items: IdentifiedArrayOf<FileItem> = []
        public var favoritePaths: Set<String> = []
        public var access: FileAccess?
        public var isLoading = false
        public var errorMessage: String?
        public var searchQuery = ""
        public var searchScope: SearchScope = .thisFolder
        public var searchResults: IdentifiedArrayOf<SearchResultItem>?
        public var isSearchingEverywhere = false
        public var sortOption: SortOption = .name
        public var sortDirection: SortDirection = .ascending
        /// Read live from the same in-memory key `SettingsFeature` writes, so toggling
        /// "Show Hidden Files" is reflected here immediately, even in an already-open folder,
        /// with no manual refresh needed.
        @Shared(.inMemory("userPreferences")) public var preferences = UserPreferences()
        /// Item currently being renamed via the native rename alert. The in-progress text
        /// itself lives in `BrowseContentView`'s own `@State`, not here — a `.alert`'s
        /// `TextField` bound through a TCA `.sending` binding didn't reliably propagate
        /// keystrokes back out, so `renameConfirmed` is sent the final text directly instead.
        public var renameSheetItem: FileItem?
        /// Item awaiting a destructive confirmation before `deleteConfirmed` actually deletes it.
        public var deleteConfirmationItem: FileItem?
        public var isPerformingFileAction = false
        public var fileActionErrorMessage: String?
        /// Drives a persistent progress toast — `nil` when no extract/compress is running.
        /// Rename/delete don't set this: they're fast enough, and already have their own
        /// alert-driven confirm flow, that a progress indicator would just flicker.
        public var fileActionProgressMessage: String?
        /// Item the "Get Info" sheet is showing, alongside its fetched metadata (or the
        /// still-loading/error state while `GET /api/metadata/*` is in flight).
        public var infoItem: FileItem?
        public var infoMetadata: FileMetadata?
        public var isLoadingInfoMetadata = false
        public var infoErrorMessage: String?
        /// Item being downloaded for the QuickLook viewer (tapping a file), alongside the
        /// local temp file `previewFile` produces once `GET /api/preview` finishes. Only
        /// used for PDFs — images/RAW load themselves per-page in the gallery view, and
        /// video/audio stream directly, neither going through this at all.
        public var previewItem: FileItem?
        public var previewFileURL: URL?
        public var isLoadingPreview = false
        public var previewErrorMessage: String?
        /// Text content for `previewItem` when it's neither previewable-via-download nor
        /// streamable (anything `GET /api/preview` 415s on) — fetched/saved via the real
        /// `/api/editor` endpoint, the server's actual text view+edit path.
        public var textContent: String?
        public var isLoadingTextContent = false
        public var isSavingTextContent = false
        public var textEditorErrorMessage: String?

        public var isSearching: Bool { !searchQuery.isEmpty }

        /// `items`, folders first, with hidden entries dropped unless the preference is on
        /// and sorted by `sortOption`.
        public var displayedItems: IdentifiedArrayOf<FileItem> {
            let visible = preferences.showHiddenFiles ? items : items.filter { !isHiddenFileName($0.name) }
            return IdentifiedArray(uniqueElements: BrowseFeature.sorted(visible, by: sortOption, direction: sortDirection))
        }

        /// `searchResults`, with hidden entries dropped unless the preference is on.
        public var displayedSearchResults: IdentifiedArrayOf<SearchResultItem>? {
            guard let searchResults else { return nil }
            return preferences.showHiddenFiles ? searchResults : searchResults.filter { !isHiddenFileName($0.name) }
        }

        public init(serverURL: URL, directoryPath: String, title: String) {
            self.serverURL = serverURL
            self.directoryPath = directoryPath
            self.title = title
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case refreshButtonTapped
        case itemsResponse(Result<BrowseResult, FilesClientError>)
        case favoritesResponse([Favorite])
        case rowTapped(FileItem)
        case searchQueryChanged(String)
        case searchScopeChanged(SearchScope)
        case searchResultTapped(SearchResultItem)
        case searchResultsResponse(Result<[SearchResultItem], FilesClientError>)
        case sortOptionChanged(SortOption)
        case sortDirectionChanged(SortDirection)
        case renameTapped(FileItem)
        case deleteTapped(FileItem)
        case favoriteToggleButtonTapped(FileItem)
        case favoriteToggleResponse(Result<FavoriteToggleResult, FilesClientError>)
        case renameCancelled
        case renameConfirmed(String)
        case renameResponse(Result<RenameResult, FilesClientError>)
        case deleteCancelled
        case deleteConfirmed
        case deleteResponse(Result<DeleteResult, FilesClientError>)
        case extractZipTapped(FileItem)
        case extractZipResponse(Result<FileItem, FilesClientError>)
        case compressTapped(FileItem)
        case compressResponse(Result<FileItem, FilesClientError>)
        case infoTapped(FileItem)
        case infoDismissed
        case infoMetadataResponse(Result<FileMetadata, FilesClientError>)
        case previewDismissed
        case previewFileResponse(Result<URL, FilesClientError>)
        case textContentResponse(Result<String, FilesClientError>)
        case textSaveTapped(String)
        case textSaveResponse(Result<String, FilesClientError>)
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case openFolder(FileItem)
            case openPath(path: String, title: String)
            case favoritesChanged
        }
    }

    @Dependency(\.filesClient) var filesClient
    @Dependency(\.continuousClock) var clock
    private enum CancelID { case search }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.items.isEmpty, state.errorMessage == nil, !state.isLoading else { return .none }
                return load(&state)

            case .refreshButtonTapped:
                return load(&state)

            case let .itemsResponse(.success(result)):
                state.isLoading = false
                state.items = IdentifiedArray(uniqueElements: Self.sortedAlphabetically(result.items))
                state.access = result.access
                state.errorMessage = nil
                return search(&state)

            case let .itemsResponse(.failure(error)):
                state.isLoading = false
                state.errorMessage = error.userMessage
                return .none

            case let .favoritesResponse(favorites):
                state.favoritePaths = Set(favorites.map(\.path))
                return .none

            case let .rowTapped(item):
                guard item.isDirectory else {
                    // Archives, known binary formats (`.exe`, `.dmg`, fonts, ...), and video
                    // containers `AVFoundation` can't decode (e.g. `.webm`) have nothing to
                    // preview — bail before touching any preview state, rather than opening a
                    // full-screen cover just to show an error. (The view layer pre-filters
                    // these with a toast before ever sending `rowTapped`; this guard is a
                    // defensive backstop, not the primary gate — it has to use the exact same
                    // `isUnsupportedForPreview` check, not a hand-rolled approximation of it,
                    // or the two can drift and this "backstop" stops backstopping anything.)
                    guard !item.isUnsupportedForPreview else { return .none }
                    // Sets `previewItem` unconditionally so the viewer presents immediately.
                    // - Streamable media (video/audio) plays live from `FilesClient.previewURL`.
                    // - Images/RAW load themselves per-page in the gallery view.
                    // - Browsable archives (.zip/.rar) list themselves in `ArchiveBrowserView`.
                    // None of these download anything here — only PDFs (the one other
                    // download-previewable kind) and plain-text files need a fetch.
                    state.previewItem = item
                    if item.isBrowsableArchive || item.isStreamableMedia || ((item.isImage || item.isRawImage) && !item.isSVG) {
                        return .none
                    } else if item.isPreviewableViaDownload {
                        return loadPreview(&state, item: item)
                    } else {
                        return loadTextContent(&state, item: item)
                    }
                }
                return .send(.delegate(.openFolder(item)))

            case let .searchQueryChanged(query):
                state.searchQuery = query
                return search(&state)

            case let .searchScopeChanged(scope):
                state.searchScope = scope
                return search(&state)

            case let .searchResultTapped(result):
                guard result.isDirectory else { return .none }
                return .send(.delegate(.openPath(path: result.id, title: result.name)))

            case let .searchResultsResponse(.success(results)):
                state.isSearchingEverywhere = false
                state.searchResults = IdentifiedArray(uniqueElements: Self.sortedAlphabetically(results))
                return .none

            case .searchResultsResponse(.failure):
                state.isSearchingEverywhere = false
                state.searchResults = []
                return .none

            case let .sortOptionChanged(option):
                state.sortOption = option
                return .none

            case let .sortDirectionChanged(direction):
                state.sortDirection = direction
                return .none

            case let .renameTapped(item):
                state.renameSheetItem = item
                return .none

            case let .deleteTapped(item):
                state.deleteConfirmationItem = item
                return .none

            case let .favoriteToggleButtonTapped(item):
                // Mirrors the real server: `favoritesService.validatePath` 400s on anything
                // that isn't a directory, so files never get a favorites entry point.
                guard item.isDirectory else { return .none }
                return toggleFavorite(&state, item: item)

            case let .favoriteToggleResponse(.success(result)):
                if result.isFavorite {
                    state.favoritePaths.insert(result.path)
                } else {
                    state.favoritePaths.remove(result.path)
                }
                return .send(.delegate(.favoritesChanged))

            case let .favoriteToggleResponse(.failure(error)):
                state.fileActionErrorMessage = error.userMessage
                return .none

            case .renameCancelled:
                state.renameSheetItem = nil
                return .none

            case let .renameConfirmed(newName):
                return confirmRename(&state, newName: newName)

            case let .renameResponse(.success(result)):
                state.isPerformingFileAction = false
                state.renameSheetItem = nil
                if let index = state.items.index(id: result.originalID) {
                    state.items.remove(at: index)
                    state.items.insert(result.renamed, at: index)
                }
                return .none

            case let .renameResponse(.failure(error)):
                state.isPerformingFileAction = false
                state.fileActionErrorMessage = error.userMessage
                return .none

            case .deleteCancelled:
                state.deleteConfirmationItem = nil
                return .none

            case .deleteConfirmed:
                return confirmDelete(&state)

            case let .deleteResponse(.success(result)):
                state.isPerformingFileAction = false
                state.items.remove(id: result.itemID)
                let wasFavorited = state.favoritePaths.remove(result.itemID) != nil
                return wasFavorited ? .send(.delegate(.favoritesChanged)) : .none

            case let .deleteResponse(.failure(error)):
                state.isPerformingFileAction = false
                state.fileActionErrorMessage = error.userMessage
                return .none

            case let .extractZipTapped(item):
                state.isPerformingFileAction = true
                state.fileActionProgressMessage = "Extracting…"
                let serverURL = state.serverURL
                let filesClient = self.filesClient
                return .run { send in
                    do {
                        let extracted = try await filesClient.extractZip(serverURL, item)
                        await send(.extractZipResponse(.success(extracted)))
                    } catch {
                        await send(.extractZipResponse(.failure((error as? FilesClientError) ?? .network(String(describing: error)))))
                    }
                }

            case let .extractZipResponse(.success(extracted)):
                state.isPerformingFileAction = false
                state.fileActionProgressMessage = nil
                state.items.append(extracted)
                return .none

            case let .extractZipResponse(.failure(error)):
                state.isPerformingFileAction = false
                state.fileActionProgressMessage = nil
                state.fileActionErrorMessage = error.userMessage
                return .none

            case let .compressTapped(item):
                state.isPerformingFileAction = true
                state.fileActionProgressMessage = "Compressing…"
                let serverURL = state.serverURL
                let filesClient = self.filesClient
                return .run { send in
                    do {
                        let compressed = try await filesClient.compressItem(serverURL, item)
                        await send(.compressResponse(.success(compressed)))
                    } catch {
                        await send(.compressResponse(.failure((error as? FilesClientError) ?? .network(String(describing: error)))))
                    }
                }

            case let .compressResponse(.success(compressed)):
                state.isPerformingFileAction = false
                state.fileActionProgressMessage = nil
                state.items.append(compressed)
                return .none

            case let .compressResponse(.failure(error)):
                state.isPerformingFileAction = false
                state.fileActionProgressMessage = nil
                state.fileActionErrorMessage = error.userMessage
                return .none

            case let .infoTapped(item):
                return loadInfo(&state, item: item)

            case .infoDismissed:
                state.infoItem = nil
                state.infoMetadata = nil
                state.infoErrorMessage = nil
                state.isLoadingInfoMetadata = false
                return .none

            case let .infoMetadataResponse(.success(metadata)):
                state.isLoadingInfoMetadata = false
                state.infoMetadata = metadata
                return .none

            case let .infoMetadataResponse(.failure(error)):
                state.isLoadingInfoMetadata = false
                state.infoErrorMessage = error.userMessage
                return .none

            case .previewDismissed:
                state.previewItem = nil
                state.previewFileURL = nil
                state.isLoadingPreview = false
                state.previewErrorMessage = nil
                state.textContent = nil
                state.isLoadingTextContent = false
                state.isSavingTextContent = false
                state.textEditorErrorMessage = nil
                return .none

            case let .previewFileResponse(.success(fileURL)):
                state.isLoadingPreview = false
                state.previewFileURL = fileURL
                return .none

            case let .previewFileResponse(.failure(error)):
                state.isLoadingPreview = false
                state.previewErrorMessage = error.userMessage
                return .none

            case let .textContentResponse(.success(content)):
                state.isLoadingTextContent = false
                state.textContent = content
                return .none

            case let .textContentResponse(.failure(error)):
                state.isLoadingTextContent = false
                state.textEditorErrorMessage = error.userMessage
                return .none

            case let .textSaveTapped(newContent):
                return confirmTextSave(&state, newContent: newContent)

            case let .textSaveResponse(.success(savedContent)):
                state.isSavingTextContent = false
                state.textContent = savedContent
                return .none

            case let .textSaveResponse(.failure(error)):
                state.isSavingTextContent = false
                state.textEditorErrorMessage = error.userMessage
                return .none

            case .delegate:
                return .none
            }
        }
    }

    /// "This Folder" is answered instantly (and fuzzily) from the already-loaded
    /// `items`. No debounce is needed since there's no network round trip. "Everywhere"
    /// still hits `/api/search` and keeps a short debounce so keystrokes don't each
    /// fire their own request.
    private func search(_ state: inout State) -> Effect<Action> {
        guard !state.searchQuery.isEmpty else {
            state.searchResults = nil
            state.isSearchingEverywhere = false
            return .cancel(id: CancelID.search)
        }

        guard state.searchScope == .everywhere else {
            state.isSearchingEverywhere = false

            let items = state.items
            let query = state.searchQuery
            let clock = self.clock

            return .run { send in
                try await clock.sleep(for: Constants.localSearchSettleDelay)

                let matches = items
                    .filter { FuzzyMatch.matches(query: query, in: $0.name) }
                    .map {
                        SearchResultItem(name: $0.name, path: $0.path, kind: $0.isDirectory ? "dir" : $0.kind)
                    }
                let sortedResults = Self.sortedAlphabetically(matches)

                await send(.searchResultsResponse(.success(sortedResults)))
            }
            .cancellable(id: CancelID.search, cancelInFlight: true)
        }

        state.isSearchingEverywhere = true
        let serverURL = state.serverURL
        let query = state.searchQuery
        let filesClient = self.filesClient
        let clock = self.clock

        return .run { send in
            try await clock.sleep(for: Constants.searchDebounce)
            do {
                let results = try await filesClient.search(serverURL, "", query, Constants.searchLimit)
                await send(.searchResultsResponse(.success(results)))
            } catch {
                await send(.searchResultsResponse(.failure((error as? FilesClientError) ?? .network(String(describing: error)))))
            }
        }
        .cancellable(id: CancelID.search, cancelInFlight: true)
    }

    private func toggleFavorite(_ state: inout State, item: FileItem) -> Effect<Action> {
        let serverURL = state.serverURL
        let path = item.id
        let isCurrentlyFavorite = state.favoritePaths.contains(path)
        let filesClient = self.filesClient
        return .run { send in
            do {
                if isCurrentlyFavorite {
                    try await filesClient.removeFavorite(serverURL, path)
                    await send(.favoriteToggleResponse(.success(FavoriteToggleResult(path: path, isFavorite: false))))
                } else {
                    _ = try await filesClient.addFavorite(serverURL, path)
                    await send(.favoriteToggleResponse(.success(FavoriteToggleResult(path: path, isFavorite: true))))
                }
            } catch {
                await send(.favoriteToggleResponse(.failure((error as? FilesClientError) ?? .network(String(describing: error)))))
            }
        }
    }

    private func confirmRename(_ state: inout State, newName: String) -> Effect<Action> {
        guard let item = state.renameSheetItem else { return .none }
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName != item.name else {
            state.renameSheetItem = nil
            return .none
        }
        state.isPerformingFileAction = true
        let serverURL = state.serverURL
        let filesClient = self.filesClient
        let originalID = item.id
        return .run { send in
            do {
                let renamed = try await filesClient.renameItem(serverURL, item, trimmedName)
                await send(.renameResponse(.success(RenameResult(originalID: originalID, renamed: renamed))))
            } catch {
                await send(.renameResponse(.failure((error as? FilesClientError) ?? .network(String(describing: error)))))
            }
        }
    }

    private func confirmDelete(_ state: inout State) -> Effect<Action> {
        guard let item = state.deleteConfirmationItem else { return .none }
        state.deleteConfirmationItem = nil
        state.isPerformingFileAction = true
        let serverURL = state.serverURL
        let filesClient = self.filesClient
        let itemID = item.id
        return .run { send in
            do {
                try await filesClient.deleteItems(serverURL, [item])
                // Animated so the row visibly slides out of the list rather than popping,
                // since removal happens on the server round-trip, not the confirm tap itself.
                await send(.deleteResponse(.success(DeleteResult(itemID: itemID))), animation: .default)
            } catch {
                await send(.deleteResponse(.failure((error as? FilesClientError) ?? .network(String(describing: error)))))
            }
        }
    }

    private func loadInfo(_ state: inout State, item: FileItem) -> Effect<Action> {
        state.infoItem = item
        state.infoMetadata = nil
        state.infoErrorMessage = nil
        state.isLoadingInfoMetadata = true
        let serverURL = state.serverURL
        let filesClient = self.filesClient
        let path = item.id
        return .run { send in
            do {
                let metadata = try await filesClient.fetchMetadata(serverURL, path)
                await send(.infoMetadataResponse(.success(metadata)))
            } catch {
                await send(.infoMetadataResponse(.failure((error as? FilesClientError) ?? .network(String(describing: error)))))
            }
        }
    }

    /// Only reached for non-streamable items — `rowTapped` already set `state.previewItem`
    /// and skipped this for video/audio, which play live instead of downloading.
    private func loadPreview(_ state: inout State, item: FileItem) -> Effect<Action> {
        state.previewFileURL = nil
        state.previewErrorMessage = nil
        state.isLoadingPreview = true
        let serverURL = state.serverURL
        let filesClient = self.filesClient
        return .run { send in
            do {
                // Word docs aren't in `PREVIEWABLE_EXTENSIONS` — `GET /api/preview` 415s them,
                // so they come down via the unrestricted download endpoint instead.
                let fileURL = item.isOfficeDocument
                    ? try await filesClient.downloadRawFile(serverURL, item)
                    : try await filesClient.previewFile(serverURL, item)
                await send(.previewFileResponse(.success(fileURL)))
            } catch {
                await send(.previewFileResponse(.failure((error as? FilesClientError) ?? .network(String(describing: error)))))
            }
        }
    }

    private func loadTextContent(_ state: inout State, item: FileItem) -> Effect<Action> {
        state.textContent = nil
        state.textEditorErrorMessage = nil
        state.isLoadingTextContent = true
        let serverURL = state.serverURL
        let filesClient = self.filesClient
        let path = item.id
        return .run { send in
            do {
                let content = try await filesClient.fetchTextContent(serverURL, path)
                await send(.textContentResponse(.success(content)))
            } catch {
                await send(.textContentResponse(.failure((error as? FilesClientError) ?? .network(String(describing: error)))))
            }
        }
    }

    private func confirmTextSave(_ state: inout State, newContent: String) -> Effect<Action> {
        guard let item = state.previewItem else { return .none }
        state.isSavingTextContent = true
        state.textEditorErrorMessage = nil
        let serverURL = state.serverURL
        let filesClient = self.filesClient
        let path = item.id
        return .run { send in
            do {
                try await filesClient.saveTextContent(serverURL, path, newContent)
                await send(.textSaveResponse(.success(newContent)))
            } catch {
                await send(.textSaveResponse(.failure((error as? FilesClientError) ?? .network(String(describing: error)))))
            }
        }
    }

    private func load(_ state: inout State) -> Effect<Action> {
        state.isLoading = true
        state.errorMessage = nil
        let serverURL = state.serverURL
        let directoryPath = state.directoryPath
        let filesClient = self.filesClient
        return .concatenate(
            .run { send in
                do {
                    let result = try await filesClient.browse(serverURL, directoryPath)
                    await send(.itemsResponse(.success(result)))
                } catch {
                    await send(.itemsResponse(.failure((error as? FilesClientError) ?? .network(String(describing: error)))))
                }
            },
            .run { send in
                let favorites = try? await filesClient.favorites(serverURL)
                await send(.favoritesResponse(favorites ?? []))
            }
        )
    }

    /// Folders before files, each group alphabetical, matching the web client's own
    /// directory listing order.
    private static func sortedAlphabetically(_ items: [FileItem]) -> [FileItem] {
        items.sorted { lhs, rhs in
            guard lhs.isDirectory == rhs.isDirectory else { return lhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Folders before files always; `option`/`direction` only decide order within each of
    /// those groups. Equal elements return `false` regardless of direction: negating a `<`
    /// comparator to get `>` breaks `sorted`'s strict-weak-ordering requirement exactly when
    /// two elements compare equal, since both `(a, b)` and `(b, a)` would otherwise flip true.
    static func sorted(_ items: some Collection<FileItem>, by option: SortOption, direction: SortDirection) -> [FileItem] {
        items.sorted { lhs, rhs in
            guard lhs.isDirectory == rhs.isDirectory else { return lhs.isDirectory }
            let isAscending: Bool
            switch option {
            case .name:
                let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                guard order != .orderedSame else { return false }
                isAscending = order == .orderedAscending
            case .size:
                guard lhs.size != rhs.size else { return false }
                isAscending = lhs.size < rhs.size
            case .dateModified:
                guard lhs.dateModified != rhs.dateModified else { return false }
                isAscending = lhs.dateModified < rhs.dateModified
            case .kind:
                let order = lhs.kind.localizedCaseInsensitiveCompare(rhs.kind)
                guard order != .orderedSame else { return false }
                isAscending = order == .orderedAscending
            }
            return direction == .ascending ? isAscending : !isAscending
        }
    }

    private static func sortedAlphabetically(_ items: [SearchResultItem]) -> [SearchResultItem] {
        items.sorted { lhs, rhs in
            guard lhs.isDirectory == rhs.isDirectory else { return lhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
