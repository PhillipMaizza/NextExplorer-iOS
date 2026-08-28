import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Foundation
import Localization
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
            case .thisFolder: L10n.Browse.scopeThisFolder
            case .everywhere: L10n.Browse.scopeEverywhere
            }
        }
    }

    /// How `displayedItems` orders a folder's contents. Folders always sort before files
    /// regardless of option; this only decides the order within each of those two groups.
    public enum SortOption: String, Hashable, Sendable, CaseIterable {
        case name, size, dateModified, kind

        var title: String {
            switch self {
            case .name: L10n.Sort.name
            case .size: L10n.Sort.size
            case .dateModified: L10n.Sort.dateModified
            case .kind: L10n.Sort.kind
            }
        }

        var icon: Image {
            switch self {
            case .name: IconKit.textformat
            case .size: IconKit.size
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
            case .ascending: L10n.Sort.ascending
            case .descending: L10n.Sort.descending
            }
        }

        var icon: Image {
            switch self {
            case .ascending: IconKit.sortAscending
            case .descending: IconKit.sortDescending
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

    public struct DownloadResult: Equatable, Sendable {
        public let destinationURL: URL
        public let location: DownloadLocation
    }

    public struct BulkDeleteResult: Equatable, Sendable {
        public let itemIDs: [String]
    }

    public struct BulkFavoriteToggleResult: Equatable, Sendable {
        public let added: [String]
        public let removed: [String]
    }

    /// The result of a `copy`/`move` transfer, plus whether this transfer should empty the
    /// shared clipboard once it succeeds: `move` always clears, `copy` clears unless the
    /// "Keep Items After Paste" setting is on.
    public struct TransferOutcome: Equatable, Sendable {
        public let result: TransferResult
        public let operation: TransferOperation
        public let clearClipboard: Bool
    }

    /// Everything needed to re-run a failed transfer from the "Retry" action on its toast, and
    /// to remember how a name-collision prompt was answered so a retry doesn't ask again.
    public struct TransferRetry: Equatable, Sendable {
        /// How a name collision at the destination should be handled. `.ask` means the check
        /// hasn't run yet; `.keepBoth` lets the server auto-rename (`file (1).txt`); `.replace`
        /// deletes `itemsToReplace` first, then transfers onto the freed names.
        public enum Resolution: Equatable, Sendable { case ask, keepBoth, replace }

        public let items: [FileItem]
        public let destination: String
        public let operation: TransferOperation
        public let clearClipboard: Bool
        public var resolution: Resolution = .ask
        public var itemsToReplace: [FileItem] = []

        func resolved(_ resolution: Resolution, replacing itemsToReplace: [FileItem] = []) -> TransferRetry {
            TransferRetry(
                items: items, destination: destination, operation: operation,
                clearClipboard: clearClipboard, resolution: resolution, itemsToReplace: itemsToReplace
            )
        }
    }

    /// A pending transfer that's blocked on the user answering a name-collision prompt.
    public struct TransferConflict: Equatable, Sendable {
        public let retry: TransferRetry
        /// The destination items that share a name with something being transferred — deleted
        /// first if the user picks "Replace".
        public let collidingItems: [FileItem]
        public var count: Int { collidingItems.count }
        public var firstName: String { collidingItems.first?.name ?? "" }
    }

    /// The answer to a name-collision prompt. `nil` (in the action payload) is "Cancel".
    public enum TransferConflictChoice: Equatable, Sendable { case replace, keepBoth }

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
        /// App wide "Copy" staging, shared under `FileClipboard.sharedKey` so the Paste
        /// action follows the user across every folder. `nil` when nothing is staged. Only
        /// ever holds copies — "Move" goes through `destinationPicker`, not the clipboard.
        @Shared(.inMemory(FileClipboard.sharedKey)) public var clipboard: FileClipboard?
        /// The "Move" destination chooser, presented for a single item or a multi selection.
        @Presents public var destinationPicker: DestinationPickerFeature.State?
        /// The review sheet shown after files are picked from the `+` menu — file list,
        /// destination folder, total size, Upload button. On confirm its files become
        /// `PendingUpload`s handed up to the app wide queue.
        @Presents public var uploadReview: UploadReviewFeature.State?
        /// Set once a transfer finishes; `BrowseContentView` turns this into a success toast,
        /// mirroring `downloadSuccessMessage`'s lifecycle.
        public var transferSuccessMessage: String?
        /// Set on a failed transfer alongside `pendingTransferRetry`; `BrowseContentView`
        /// turns this into a failure toast with a "Retry" action.
        public var transferErrorMessage: String?
        /// The params to re-run when the user taps "Retry" on a failed transfer's toast. The
        /// staged clipboard is never emptied while this is non nil, so a retry always has
        /// something to act on.
        public var pendingTransferRetry: TransferRetry?
        /// Non nil while a transfer is waiting on the user's answer to a name-collision prompt.
        public var transferConflict: TransferConflict?
        /// Set when an item is staged with "Copy"; `BrowseContentView` turns it into a brief
        /// "<name> copied" toast.
        public var clipboardStagedMessage: String?
        /// Item currently being renamed via the native rename alert. The in-progress text
        /// itself lives in `BrowseContentView`'s own `@State`, not here — a `.alert`'s
        /// `TextField` bound through a TCA `.sending` binding didn't reliably propagate
        /// keystrokes back out, so `renameConfirmed` is sent the final text directly instead.
        public var renameSheetItem: FileItem?
        /// Item awaiting a destructive confirmation before `deleteConfirmed` actually deletes it.
        public var deleteConfirmationItem: FileItem?
        public var isPerformingFileAction = false
        public var fileActionErrorMessage: String?
        /// Whether the list/grid is in multi-select mode — toggled from the toolbar, not tied
        /// to any particular item. `selectedItemIDs` is always cleared when this flips off.
        public var isSelecting = false
        public var selectedItemIDs: Set<FileItem.ID> = []
        public var isBulkActionInFlight = false
        public var bulkDeleteConfirmationIsPresented = false
        /// Drives a persistent progress toast — `nil` when no extract/compress/download is
        /// running. Rename/delete don't set this: they're fast enough, and already have their
        /// own alert-driven confirm flow, that a progress indicator would just flicker.
        public var fileActionProgressMessage: String?
        /// Set once a download finishes; `BrowseContentView` turns this into a success toast.
        /// Mirrors `fileActionErrorMessage`'s lifecycle — it's never explicitly cleared back to
        /// `nil` by the reducer, only ever overwritten by the next download's message.
        public var downloadSuccessMessage: String?
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
        case downloadTapped(FileItem, DownloadLocation, removeArchiveAfterDownload: Bool)
        case downloadProgressUpdated(String)
        case downloadResponse(Result<DownloadResult, FilesClientError>)
        case selectModeToggled
        case itemSelectionToggled(FileItem.ID)
        case selectAllTapped
        case deselectAllTapped
        case bulkDeleteTapped
        case bulkDeleteCancelled
        case bulkDeleteConfirmed
        case bulkDeleteResponse(Result<BulkDeleteResult, FilesClientError>)
        case bulkFavoriteTapped
        case bulkFavoriteResponse(BulkFavoriteToggleResult)
        case bulkDownloadTapped(DownloadLocation, removeArchiveAfterDownload: Bool)
        case bulkDownloadResponse(savedCount: Int, total: Int, location: DownloadLocation)
        case uploadFilesPicked([PickedFile])
        case uploadReview(PresentationAction<UploadReviewFeature.Action>)
        case copyTapped(FileItem)
        case moveTapped(FileItem)
        case bulkCopyTapped
        case bulkMoveTapped
        case clipboardCleared
        case pasteTapped(keepItemsAfterCopy: Bool)
        case retryTransferTapped
        case transferConflictCheckResponse(Result<[FileItem], FilesClientError>)
        case transferConflictResolved(TransferConflictChoice?)
        case transferResponse(Result<TransferOutcome, FilesClientError>)
        case destinationPicker(PresentationAction<DestinationPickerFeature.Action>)
        case infoTapped(FileItem)
        case infoDismissed
        case infoMetadataResponse(Result<FileMetadata, FilesClientError>)
        case previewDismissed
        case previewFileResponse(Result<URL, FilesClientError>)
        case textContentResponse(Result<String, FilesClientError>)
        case openInBrowserTapped(FileItem)
        case googleDocsPointerResponse(item: FileItem, Result<URL, FilesClientError>)
        case textSaveTapped(String)
        case textSaveResponse(Result<String, FilesClientError>)
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case openFolder(FileItem)
            case openPath(path: String, title: String)
            case favoritesChanged
            /// Files the user picked from the `+` menu, each already carrying its destination
            /// folder — bubbled up to `MainTabFeature`'s app-wide upload queue.
            case uploadRequested([PendingUpload])
            /// A copy/move just changed what's on the server. `BrowseTabFeature` re-fetches
            /// the whole live navigation stack so both the source and destination listings
            /// reflect the new state.
            case directoryContentsChanged
            /// The "Open" button on the download-success toast — switches to the Downloads
            /// tab so the user can see where the file landed.
            case openDownloadsTapped
        }
    }

    @Dependency(\.filesClient) var filesClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.localDownloadStore) var localDownloadStore
    @Dependency(\.openURL) var openURL
    private enum CancelID { case search, transfer, googleDocsPointer }

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
                    // Google Drive stub files (`.gsheet`, `.gdoc`, …) link out to a real
                    // Google document — open that, don't show the JSON stub.
                    if item.isGoogleDocsPointer {
                        return openGoogleDocsPointer(serverURL: state.serverURL, item: item)
                    }
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

            case let .searchResultsResponse(.failure(error)):
                state.isSearchingEverywhere = false
                state.searchResults = []
                // Surface it, otherwise a network blip during an "Everywhere" search is
                // indistinguishable from a genuine empty result.
                state.fileActionErrorMessage = error == .sessionExpired ? error.userMessage : L10n.Browse.searchFailed
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
                state.fileActionProgressMessage = L10n.Browse.progressExtracting
                let serverURL = state.serverURL
                let filesClient = self.filesClient
                return .run { send in
                    await send(.extractZipResponse(await apiResult { try await filesClient.extractZip(serverURL, item) }))
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
                state.fileActionProgressMessage = L10n.Browse.progressCompressing
                let serverURL = state.serverURL
                let filesClient = self.filesClient
                return .run { send in
                    await send(.compressResponse(await apiResult { try await filesClient.compressItem(serverURL, item) }))
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

            case let .downloadTapped(item, location, removeArchiveAfterDownload):
                return startDownload(&state, item: item, location: location, removeArchiveAfterDownload: removeArchiveAfterDownload)

            case let .downloadProgressUpdated(message):
                state.fileActionProgressMessage = message
                return .none

            case let .downloadResponse(.success(result)):
                state.isPerformingFileAction = false
                state.fileActionProgressMessage = nil
                state.downloadSuccessMessage = L10n.Browse.downloadSavedTo(result.location.title)
                return .none

            case let .downloadResponse(.failure(error)):
                state.isPerformingFileAction = false
                state.fileActionProgressMessage = nil
                state.fileActionErrorMessage = error.userMessage
                return .none

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

            case .selectAllTapped:
                state.selectedItemIDs = Set(state.displayedItems.map(\.id))
                return .none

            case .deselectAllTapped:
                state.selectedItemIDs = []
                return .none

            case .bulkDeleteTapped:
                guard !state.selectedItemIDs.isEmpty else { return .none }
                state.bulkDeleteConfirmationIsPresented = true
                return .none

            case .bulkDeleteCancelled:
                state.bulkDeleteConfirmationIsPresented = false
                return .none

            case .bulkDeleteConfirmed:
                return confirmBulkDelete(&state)

            case let .bulkDeleteResponse(.success(result)):
                state.isBulkActionInFlight = false
                for itemID in result.itemIDs {
                    state.items.remove(id: itemID)
                }
                let hadFavorited = result.itemIDs.reduce(into: false) { hadFavorited, itemID in
                    if state.favoritePaths.remove(itemID) != nil { hadFavorited = true }
                }
                state.isSelecting = false
                state.selectedItemIDs = []
                return hadFavorited ? .send(.delegate(.favoritesChanged)) : .none

            case let .bulkDeleteResponse(.failure(error)):
                state.isBulkActionInFlight = false
                state.fileActionErrorMessage = error.userMessage
                return .none

            case .bulkFavoriteTapped:
                return startBulkFavorite(&state)

            case let .bulkFavoriteResponse(result):
                state.isBulkActionInFlight = false
                state.favoritePaths.formUnion(result.added)
                state.favoritePaths.subtract(result.removed)
                state.isSelecting = false
                state.selectedItemIDs = []
                let didChangeAnything = !result.added.isEmpty || !result.removed.isEmpty
                return didChangeAnything ? .send(.delegate(.favoritesChanged)) : .none

            case let .bulkDownloadTapped(location, removeArchiveAfterDownload):
                return startBulkDownload(&state, location: location, removeArchiveAfterDownload: removeArchiveAfterDownload)

            case let .bulkDownloadResponse(savedCount, total, location):
                state.isBulkActionInFlight = false
                state.fileActionProgressMessage = nil
                state.isSelecting = false
                state.selectedItemIDs = []
                if savedCount == total {
                    state.downloadSuccessMessage = L10n.Browse.downloadSavedAllTo(savedCount, location.title)
                } else if savedCount > 0 {
                    state.downloadSuccessMessage = L10n.Browse.downloadSavedCountTo(savedCount, total, location.title)
                } else {
                    state.fileActionErrorMessage = L10n.Browse.downloadBulkFailed
                }
                return .none

            case let .uploadFilesPicked(files):
                guard !files.isEmpty else { return .none }
                state.uploadReview = UploadReviewFeature.State(
                    serverURL: state.serverURL, files: files, startingDestination: state.directoryPath
                )
                return .none

            case let .uploadReview(.presented(.delegate(.confirmed(files, destination)))):
                state.uploadReview = nil
                guard !files.isEmpty, !destination.isEmpty else { return .none }
                return .send(.delegate(.uploadRequested(files.map {
                    PendingUpload(id: $0.id, fileURL: $0.fileURL, fileName: $0.fileName, destination: destination)
                })))

            case .uploadReview(.presented(.delegate(.cancelled))):
                state.uploadReview = nil
                return .none

            case .uploadReview:
                return .none

            case let .copyTapped(item):
                state.$clipboard.withLock { $0 = FileClipboard(items: [item], operation: .copy) }
                state.clipboardStagedMessage = L10n.Browse.clipboardCopiedOne(item.name)
                return .none

            case let .moveTapped(item):
                state.destinationPicker = DestinationPickerFeature.State(serverURL: state.serverURL, items: [item])
                return .none

            case .bulkCopyTapped:
                let items = Array(state.items.filter { state.selectedItemIDs.contains($0.id) })
                guard !items.isEmpty else { return .none }
                state.$clipboard.withLock { $0 = FileClipboard(items: items, operation: .copy) }
                state.clipboardStagedMessage = L10n.Browse.clipboardCopiedMany(items.count)
                state.isSelecting = false
                state.selectedItemIDs = []
                return .none

            case .bulkMoveTapped:
                let items = Array(state.items.filter { state.selectedItemIDs.contains($0.id) })
                guard !items.isEmpty else { return .none }
                state.destinationPicker = DestinationPickerFeature.State(serverURL: state.serverURL, items: items)
                state.isSelecting = false
                state.selectedItemIDs = []
                return .none

            case .clipboardCleared:
                state.$clipboard.withLock { $0 = nil }
                return .none

            case let .pasteTapped(keepItemsAfterCopy):
                return paste(&state, keepItemsAfterCopy: keepItemsAfterCopy)

            case let .destinationPicker(.presented(.delegate(.confirmed(destination)))):
                guard let picker = state.destinationPicker else { return .none }
                let items = picker.items
                state.destinationPicker = nil
                return runTransfer(&state, retry: TransferRetry(
                    items: items, destination: destination, operation: .move, clearClipboard: false
                ))

            case .destinationPicker(.presented(.delegate(.cancelled))):
                state.destinationPicker = nil
                return .none

            case .destinationPicker:
                return .none

            case .retryTransferTapped:
                guard let retry = state.pendingTransferRetry else { return .none }
                return runTransfer(&state, retry: retry)

            case let .transferConflictCheckResponse(result):
                guard let retry = state.pendingTransferRetry else { return .none }
                switch result {
                case let .success(destinationItems):
                    return resolveTransfer(&state, retry: retry, colliding: Self.collidingItems(for: retry, in: destinationItems))
                case .failure:
                    // The listing failed — fall back to the server's safe auto-rename rather
                    // than blocking the transfer on a check we couldn't run.
                    return performTransfer(&state, retry: retry.resolved(.keepBoth))
                }

            case let .transferConflictResolved(choice):
                guard let conflict = state.transferConflict else { return .none }
                state.transferConflict = nil
                switch choice {
                case .replace:
                    return performTransfer(&state, retry: conflict.retry.resolved(.replace, replacing: conflict.collidingItems))
                case .keepBoth:
                    return performTransfer(&state, retry: conflict.retry.resolved(.keepBoth))
                case .none:
                    state.pendingTransferRetry = nil
                    return .none
                }

            case let .transferResponse(.success(outcome)):
                state.isPerformingFileAction = false
                state.fileActionProgressMessage = nil
                state.pendingTransferRetry = nil
                state.transferErrorMessage = nil
                if outcome.clearClipboard {
                    state.$clipboard.withLock { $0 = nil }
                }
                state.transferSuccessMessage = Self.transferSuccessMessage(for: outcome)
                return .send(.delegate(.directoryContentsChanged))

            case let .transferResponse(.failure(error)):
                state.isPerformingFileAction = false
                state.fileActionProgressMessage = nil
                state.transferErrorMessage = error.userMessage
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

            case let .openInBrowserTapped(item):
                guard item.isHTML, let url = FilesClient.rawFileURL(serverURL: state.serverURL, item: item) else { return .none }
                return .run { [openURL] _ in await openURL(url) }

            case let .googleDocsPointerResponse(item, result):
                switch result {
                case let .success(url):
                    return .run { [openURL] _ in await openURL(url) }
                case .failure:
                    // Couldn't read the stub or it had no usable link — fall back to showing
                    // it in the text viewer rather than leaving the tap dead.
                    state.previewItem = item
                    return loadTextContent(&state, item: item)
                }

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
        .ifLet(\.$destinationPicker, action: \.destinationPicker) {
            DestinationPickerFeature()
        }
        .ifLet(\.$uploadReview, action: \.uploadReview) {
            UploadReviewFeature()
        }
    }

    private func paste(_ state: inout State, keepItemsAfterCopy: Bool) -> Effect<Action> {
        guard let clipboard = state.clipboard,
              clipboard.canPaste(into: state.directoryPath, canWrite: state.access?.canWrite ?? false)
        else { return .none }
        let clearClipboard = clipboard.operation == .move || !keepItemsAfterCopy
        return runTransfer(&state, retry: TransferRetry(
            items: clipboard.items,
            destination: state.directoryPath,
            operation: clipboard.operation,
            clearClipboard: clearClipboard
        ))
    }

    /// Entry point for every copy/move. Runs the name-collision check first (unless the retry
    /// already carries an answer), then either prompts or hands off to `performTransfer`.
    private func runTransfer(_ state: inout State, retry: TransferRetry) -> Effect<Action> {
        guard !retry.items.isEmpty, !state.isPerformingFileAction else { return .none }
        guard retry.resolution == .ask else { return performTransfer(&state, retry: retry) }

        // Paste always targets the folder that's already on screen, so its listing is right
        // here in `state.items` — no round trip. A picker move can land anywhere else, so
        // that case asks the server for the destination listing.
        if retry.destination == state.directoryPath {
            return resolveTransfer(&state, retry: retry, colliding: Self.collidingItems(for: retry, in: Array(state.items)))
        }

        state.isPerformingFileAction = true
        state.fileActionProgressMessage = retry.operation == .move ? L10n.Browse.progressMoving : L10n.Browse.progressCopying
        state.transferErrorMessage = nil
        state.pendingTransferRetry = retry
        let serverURL = state.serverURL
        let filesClient = self.filesClient
        return .run { send in
            await send(.transferConflictCheckResponse(await apiResult {
                try await filesClient.browse(serverURL, retry.destination).items
            }))
        }
        .cancellable(id: CancelID.transfer)
    }

    /// No collisions → straight through (server auto-rename is a no-op when nothing clashes).
    /// Otherwise stash the pending transfer and let `BrowseContentView` raise the prompt.
    private func resolveTransfer(_ state: inout State, retry: TransferRetry, colliding: [FileItem]) -> Effect<Action> {
        guard !colliding.isEmpty else { return performTransfer(&state, retry: retry.resolved(.keepBoth)) }
        state.isPerformingFileAction = false
        state.fileActionProgressMessage = nil
        state.pendingTransferRetry = retry
        state.transferConflict = TransferConflict(retry: retry, collidingItems: colliding)
        return .none
    }

    /// Actually moves the bytes: for `.replace`, deletes the clashing destination items first,
    /// then transfers. The staged clipboard is never emptied until this confirms success.
    private func performTransfer(_ state: inout State, retry: TransferRetry) -> Effect<Action> {
        guard !retry.items.isEmpty else { return .none }
        state.isPerformingFileAction = true
        state.fileActionProgressMessage = retry.operation == .move ? L10n.Browse.progressMoving : L10n.Browse.progressCopying
        state.transferErrorMessage = nil
        state.transferConflict = nil
        // Kept until the transfer confirms success, so the "Retry" action on a failure toast
        // always has the exact params to re-run.
        state.pendingTransferRetry = retry
        let serverURL = state.serverURL
        let filesClient = self.filesClient
        return .run { send in
            await send(.transferResponse(await apiResult {
                if retry.resolution == .replace, !retry.itemsToReplace.isEmpty {
                    try await filesClient.deleteItems(serverURL, retry.itemsToReplace)
                }
                let result = try await filesClient.transferItems(serverURL, retry.items, retry.destination, retry.operation)
                return TransferOutcome(result: result, operation: retry.operation, clearClipboard: retry.clearClipboard)
            }), animation: .default)
        }
        .cancellable(id: CancelID.transfer)
    }

    /// Destination items that share a name with something inbound — minus any that *are* the
    /// inbound item (copying a file into its own folder isn't a real collision; the server
    /// just makes a numbered duplicate).
    private static func collidingItems(for retry: TransferRetry, in destinationItems: [FileItem]) -> [FileItem] {
        let incomingNames = Set(retry.items.map(\.name))
        let sourceIDs = Set(retry.items.map(\.id))
        return destinationItems.filter { incomingNames.contains($0.name) && !sourceIDs.contains($0.id) }
    }

    private static func transferSuccessMessage(for outcome: TransferOutcome) -> String {
        let moved = outcome.result.movedCount
        let skipped = outcome.result.skippedCount
        switch outcome.operation {
        case .move:
            return skipped > 0
                ? L10n.Browse.transferMovedWithSkipped(moved, skipped)
                : L10n.Browse.transferMoved(moved)
        case .copy:
            return skipped > 0
                ? L10n.Browse.transferCopiedWithSkipped(moved, skipped)
                : L10n.Browse.transferCopied(moved)
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
            await send(.searchResultsResponse(await apiResult {
                try await filesClient.search(serverURL, "", query, Constants.searchLimit)
            }))
        }
        .cancellable(id: CancelID.search, cancelInFlight: true)
    }

    private func toggleFavorite(_ state: inout State, item: FileItem) -> Effect<Action> {
        let serverURL = state.serverURL
        let path = item.id
        let isCurrentlyFavorite = state.favoritePaths.contains(path)
        let filesClient = self.filesClient
        return .run { send in
            await send(.favoriteToggleResponse(await apiResult {
                if isCurrentlyFavorite {
                    try await filesClient.removeFavorite(serverURL, path)
                } else {
                    _ = try await filesClient.addFavorite(serverURL, path)
                }
                return FavoriteToggleResult(path: path, isFavorite: !isCurrentlyFavorite)
            }))
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
            await send(.renameResponse(await apiResult {
                RenameResult(originalID: originalID, renamed: try await filesClient.renameItem(serverURL, item, trimmedName))
            }))
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
            // Animated so the row visibly slides out of the list rather than popping,
            // since removal happens on the server round trip, not the confirm tap itself.
            await send(.deleteResponse(await apiResult {
                try await filesClient.deleteItems(serverURL, [item])
                return DeleteResult(itemID: itemID)
            }), animation: .default)
        }
    }

    /// Folders have no dedicated "zip and stream" endpoint, so they're compressed server-side
    /// first (the same `compressItem` the context menu's own "Compress" action uses — this
    /// leaves the resulting `.zip` sitting alongside the folder on the server, same side
    /// effect "Compress" already has) and the resulting archive is downloaded like any file.
    private func startDownload(_ state: inout State, item: FileItem, location: DownloadLocation, removeArchiveAfterDownload: Bool) -> Effect<Action> {
        state.isPerformingFileAction = true
        state.fileActionProgressMessage = item.isDirectory ? L10n.Browse.progressCompressing : L10n.Browse.progressDownloading
        let serverURL = state.serverURL
        let filesClient = self.filesClient
        let localDownloadStore = self.localDownloadStore
        return .run { send in
            await send(.downloadResponse(await apiResult {
                var compressedArchive: FileItem?
                let fileToDownload: FileItem
                if item.isDirectory {
                    let archive = try await filesClient.compressItem(serverURL, item)
                    compressedArchive = archive
                    fileToDownload = archive
                    await send(.downloadProgressUpdated(L10n.Browse.progressDownloading))
                } else {
                    fileToDownload = item
                }
                let cachedURL = try await filesClient.downloadRawFile(serverURL, fileToDownload)
                let destinationURL = try localDownloadStore.save(cachedURL, fileToDownload.name, location)
                // Best-effort, and after the fact — the download already succeeded, so a
                // cleanup failure here shouldn't surface as an error to the user.
                if removeArchiveAfterDownload, let compressedArchive {
                    try? await filesClient.deleteItems(serverURL, [compressedArchive])
                }
                return DownloadResult(destinationURL: destinationURL, location: location)
            }))
        }
    }

    private func confirmBulkDelete(_ state: inout State) -> Effect<Action> {
        state.bulkDeleteConfirmationIsPresented = false
        let itemsToDelete = state.selectedItemIDs.compactMap { state.items[id: $0] }
        guard !itemsToDelete.isEmpty else { return .none }
        state.isBulkActionInFlight = true
        let serverURL = state.serverURL
        let filesClient = self.filesClient
        let itemIDs = itemsToDelete.map(\.id)
        return .run { send in
            // Animated so the rows visibly slide out of the list rather than popping,
            // since removal happens on the server round trip, not the confirm tap itself.
            await send(.bulkDeleteResponse(await apiResult {
                try await filesClient.deleteItems(serverURL, itemsToDelete)
                return BulkDeleteResult(itemIDs: itemIDs)
            }), animation: .default)
        }
    }

    /// Every selected directory is toggled, mirroring the single-item context-menu action:
    /// already-favorited directories are removed, the rest are added. Best-effort per item,
    /// matching the same philosophy the sign-out flow already uses elsewhere: one failure
    /// shouldn't block toggling the rest.
    private func startBulkFavorite(_ state: inout State) -> Effect<Action> {
        let targets = state.selectedItemIDs
            .compactMap { state.items[id: $0] }
            .filter(\.isDirectory)
        guard !targets.isEmpty else { return .none }
        state.isBulkActionInFlight = true
        let serverURL = state.serverURL
        let favoritePaths = state.favoritePaths
        let filesClient = self.filesClient
        return .run { send in
            var added: [String] = []
            var removed: [String] = []
            for item in targets {
                let isCurrentlyFavorite = favoritePaths.contains(item.id)
                if isCurrentlyFavorite {
                    if (try? await filesClient.removeFavorite(serverURL, item.id)) != nil {
                        removed.append(item.id)
                    }
                } else {
                    if (try? await filesClient.addFavorite(serverURL, item.id)) != nil {
                        added.append(item.id)
                    }
                }
            }
            await send(.bulkFavoriteResponse(BulkFavoriteToggleResult(added: added, removed: removed)))
        }
    }

    /// Sequential, not concurrent: reuses the same compress-then-download chain
    /// `startDownload` uses for a single folder, one selected item at a time, so the
    /// progress toast can report "N of M" as it goes. Best-effort — one item's failure
    /// doesn't stop the rest of the batch.
    private func startBulkDownload(_ state: inout State, location: DownloadLocation, removeArchiveAfterDownload: Bool) -> Effect<Action> {
        let targets = state.selectedItemIDs.compactMap { state.items[id: $0] }
        guard !targets.isEmpty else { return .none }
        state.isBulkActionInFlight = true
        state.fileActionProgressMessage = L10n.Browse.progressDownloadingIndexed(1, targets.count)
        let serverURL = state.serverURL
        let filesClient = self.filesClient
        let localDownloadStore = self.localDownloadStore
        return .run { send in
            var savedCount = 0
            for (index, item) in targets.enumerated() {
                if index > 0 {
                    await send(.downloadProgressUpdated(L10n.Browse.progressDownloadingIndexed(index + 1, targets.count)))
                }
                do {
                    var compressedArchive: FileItem?
                    let fileToDownload: FileItem
                    if item.isDirectory {
                        let archive = try await filesClient.compressItem(serverURL, item)
                        compressedArchive = archive
                        fileToDownload = archive
                    } else {
                        fileToDownload = item
                    }
                    let cachedURL = try await filesClient.downloadRawFile(serverURL, fileToDownload)
                    _ = try localDownloadStore.save(cachedURL, fileToDownload.name, location)
                    if removeArchiveAfterDownload, let compressedArchive {
                        try? await filesClient.deleteItems(serverURL, [compressedArchive])
                    }
                    savedCount += 1
                } catch {
                    continue
                }
            }
            await send(.bulkDownloadResponse(savedCount: savedCount, total: targets.count, location: location))
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
            await send(.infoMetadataResponse(await apiResult { try await filesClient.fetchMetadata(serverURL, path) }))
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
            await send(.previewFileResponse(await apiResult {
                // Word docs aren't in `PREVIEWABLE_EXTENSIONS` — `GET /api/preview` 415s them,
                // so they come down via the unrestricted download endpoint instead.
                item.isOfficeDocument
                    ? try await filesClient.downloadRawFile(serverURL, item)
                    : try await filesClient.previewFile(serverURL, item)
            }))
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
            await send(.textContentResponse(await apiResult { try await filesClient.fetchTextContent(serverURL, path) }))
        }
    }

    /// Fetches a Google Drive stub file, reads the link out of its JSON, and hands it to the
    /// system to open (the Google app or the browser). No preview state is touched unless the
    /// fetch fails, in which case `googleDocsPointerResponse` falls back to the text viewer.
    private func openGoogleDocsPointer(serverURL: URL, item: FileItem) -> Effect<Action> {
        let filesClient = self.filesClient
        let path = item.id
        return .run { send in
            await send(.googleDocsPointerResponse(item: item, await apiResult {
                let contents = try await filesClient.fetchTextContent(serverURL, path)
                guard let url = GoogleDocsPointer.targetURL(fromContents: contents) else {
                    throw FilesClientError.decoding("Google Drive stub has no link")
                }
                return url
            }))
        }
        .cancellable(id: CancelID.googleDocsPointer, cancelInFlight: true)
    }

    private func confirmTextSave(_ state: inout State, newContent: String) -> Effect<Action> {
        guard let item = state.previewItem else { return .none }
        state.isSavingTextContent = true
        state.textEditorErrorMessage = nil
        let serverURL = state.serverURL
        let filesClient = self.filesClient
        let path = item.id
        return .run { send in
            await send(.textSaveResponse(await apiResult {
                try await filesClient.saveTextContent(serverURL, path, newContent)
                return newContent
            }))
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
                await send(.itemsResponse(await apiResult { try await filesClient.browse(serverURL, directoryPath) }))
            },
            .run { send in
                let favorites = try? await filesClient.favorites(serverURL)
                await send(.favoritesResponse(favorites ?? []))
            }
        )
    }

    /// Folders before files, each group alphabetical, matching the web client's own
    /// directory listing order. Used for both `FileItem` listings and `SearchResultItem`
    /// result sets.
    static func sortedAlphabetically<T: DirectoryFirstSortable>(_ items: [T]) -> [T] {
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

}

/// An item that sorts folders first then by name: `FileItem` and `SearchResultItem`.
protocol DirectoryFirstSortable {
    var name: String { get }
    var isDirectory: Bool { get }
}

extension FileItem: DirectoryFirstSortable {}
extension SearchResultItem: DirectoryFirstSortable {}
