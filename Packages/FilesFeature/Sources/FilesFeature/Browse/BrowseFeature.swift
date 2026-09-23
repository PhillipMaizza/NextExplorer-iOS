import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Foundation
import Localization
import SwiftUI

/// One directory listing. The root browse screen and every pushed subfolder are the
/// same feature, scoped to a different `directoryPath`. Drilling into a folder is
/// signaled via `delegate(.openFolder)`/`delegate(.openPath)` rather than owning its own
/// navigation stack: `BrowseTabFeature` owns the single flat `StackState` all pushes land on.
@Reducer
public struct BrowseFeature {
    /// Effect timing/limits shared by `body` and the extracted `BrowseFeature+*.swift` effect
    /// helpers. Nested (not a file private top level enum) so those extensions can see it.
    enum Constants {
        /// Gate before the recursive backend search fires, so a burst of keystrokes collapses to one
        /// request (superseded ones are cancelled). 1s, matching the web client — the backend recurses
        /// and scans file contents with ripgrep, which is expensive, so this deliberately throttles
        /// how often it runs. The instant client side pre-fill covers perceived latency in the gap.
        static let searchDebounce: Duration = .seconds(1)
        /// Matches the backend's own default result cap.
        static let searchLimit = 100
        /// An action taken from a full-screen preview that also dismisses the cover (delete,
        /// "Open" on the download toast, "View in Shared") waits this long before it runs, so the
        /// cover finishes dismissing first and the effect — a row sliding out, a tab switch —
        /// plays on the list the user is now looking at, not mid transition.
        static let previewActionSettleDelay: Duration = .milliseconds(350)
    }

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

    /// State of the `POST /api/files/delete-impact` lookup that runs while a delete
    /// confirmation is on screen. `.unavailable` means the check itself failed — the delete
    /// still proceeds, the server still removes any linked shares, the alert just can't say
    /// how many.
    public enum DeleteImpactCheck: Equatable, Sendable {
        case idle
        case checking
        case loaded(DeleteImpact)
        case unavailable
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

    /// Where the currently displayed listing came from.
    public enum DataSource: Equatable, Sendable {
        case live
        /// Served from the offline cache, stamped with when it was last fetched from the server.
        case cached(fetchedAt: Date)
    }

    @ObservableState
    public struct State: Equatable, Sendable {
        public var serverURL: URL
        public var directoryPath: String
        public var title: String
        public var items: IdentifiedArrayOf<FileItem> = []
        public var favoritePaths: Set<String> = []
        /// Ids of the items in this listing that are available offline (a pinned file, or a folder
        /// covered by a pinned root), so rows/cells can show an offline badge. Recomputed off the
        /// main actor when the listing loads, on appear, and when a download finishes.
        public var offlineItemIDs: Set<String> = []
        public var access: FileAccess?
        /// The folder listing load lifecycle. `phase.hasLoaded` flips true the first time a
        /// browse response lands (success or failure), so the view shows the loading skeleton
        /// rather than the empty state until then; `phase.errorMessage` carries a failed load.
        public var phase: DataPhase = .idle
        /// `.cached` while the listing on screen is an offline copy; back to `.live` as soon as
        /// a fresh fetch lands. Drives the "showing saved copy" banner.
        public var dataSource: DataSource = .live
        public var searchQuery = ""
        public var searchScope: SearchScope = .thisFolder
        public var searchResults: IdentifiedArrayOf<SearchResultItem>?
        /// True while a recursive backend search (either scope) is in flight, so the UI can show a
        /// spinner over the instant client side pre-fill until the authoritative results land.
        public var isSearchingRemotely = false
        /// The file type categories the search results are filtered to. Empty means "all types";
        /// otherwise a result shows only if its category is in the set. Only relevant while
        /// searching, and pruned to the categories actually present as results change.
        public var selectedSearchCategories: Set<FileCategory> = []
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
        /// Current account's downloads scope, so saved files land in this account's folder.
        @Shared(.inMemory(DownloadAccountScope.sharedKey)) public var downloadScope = ""
        /// The "Move" destination chooser, presented for a single item or a multi selection.
        @Presents public var destinationPicker: DestinationPickerFeature.State?
        /// The review sheet shown after files are picked from the `+` menu — file list,
        /// destination folder, total size, Upload button. On confirm its files become
        /// `PendingUpload`s handed up to the app wide queue.
        @Presents public var uploadReview: UploadReviewFeature.State?
        /// The "Permissions" sheet for a single item — view/chmod/chown via `/api/permissions`.
        @Presents public var permissions: PermissionsFeature.State?
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
        /// Whether the "New folder" name sheet is open. Like rename, the draft text lives in
        /// `BrowseContentView`'s own `@State`; `newFolderConfirmed` carries the final name.
        public var isNewFolderSheetPresented = false
        /// Item awaiting a destructive confirmation before `deleteConfirmed` actually deletes it.
        public var deleteConfirmationItem: FileItem?
        /// Share-link fallout of the pending delete, single or bulk — only one confirmation is
        /// ever on screen at once, so one field covers both. Filled in by `delete-impact` while
        /// the alert is up; reset to `.idle` when the alert is dismissed.
        public var deleteImpactCheck: DeleteImpactCheck = .idle
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
        /// macOS: where the last download was saved (a file, or the folder of a bulk download),
        /// so the success toast can show it in Finder.
        public var lastSavedDownloadURL: URL?
        /// Item the "Get Info" sheet is showing, alongside its fetched metadata (or the
        /// still-loading/error state while `GET /api/metadata/*` is in flight).
        public var infoItem: FileItem?
        public var infoMetadata: FileMetadata?
        /// Server disk usage for `infoItem` when it's a directory and the endpoint returned
        /// real figures — drives the Get Info sheet's "Server disk" section.
        public var infoUsage: StorageUsage?
        /// The `GET /api/metadata/*` load lifecycle for the Get Info sheet. `isLoadingInfoMetadata`
        /// / `infoErrorMessage` are derived from it (rule #8: one phase, not a bool + error pair).
        public var infoPhase: DataPhase = .idle
        public var isLoadingInfoMetadata: Bool { infoPhase == .loading }
        public var infoErrorMessage: String? { infoPhase.errorMessage }
        /// Item being downloaded for the QuickLook viewer (tapping a file), alongside the
        /// local temp file `previewFile` produces once `GET /api/preview` finishes. Only
        /// used for PDFs — images/RAW load themselves per-page in the gallery view, and
        /// video/audio stream directly, neither going through this at all.
        public var previewItem: FileItem?
        public var previewFileURL: URL?
        /// The `GET /api/preview` download lifecycle. `isLoadingPreview` / `previewErrorMessage`
        /// are derived from it.
        public var previewPhase: DataPhase = .idle
        public var isLoadingPreview: Bool { previewPhase == .loading }
        public var previewErrorMessage: String? { previewPhase.errorMessage }
        /// Text content for `previewItem` when it's neither previewable-via-download nor
        /// streamable (anything `GET /api/preview` 415s on) — fetched/saved via the real
        /// `/api/editor` endpoint, the server's actual text view+edit path.
        public var textContent: String?
        /// The `/api/editor` read lifecycle. A save is a separate mutation (`isSavingTextContent`
        /// + `textSaveError`), so it never rewinds a loaded editor back to a load phase.
        public var textPhase: DataPhase = .idle
        public var isSavingTextContent = false
        public var textSaveError: String?
        public var isLoadingTextContent: Bool { textPhase == .loading }
        /// A load failure (from `textPhase`) or a save failure (`textSaveError`) — they never
        /// coexist, so one accessor drives the editor's error surface as before.
        public var textEditorErrorMessage: String? { textPhase.errorMessage ?? textSaveError }

        public var isSearching: Bool { !searchQuery.isEmpty }

        /// `items`, folders first, with hidden entries dropped unless the preference is on
        /// and sorted by `sortOption`.
        public var displayedItems: IdentifiedArrayOf<FileItem> {
            let visible = preferences.showHiddenFiles ? items : items.filter { !isHiddenFileName($0.name) }
            return IdentifiedArray(BrowseFeature.sorted(visible, by: sortOption, direction: sortDirection), id: \.id, uniquingIDsWith: { first, _ in first })
        }

        /// Whether `displayedItems` would be non empty, and how many entries it would hold,
        /// without paying `displayedItems`' filter+sort. Used for the toolbar/selection/empty
        /// state checks that only need emptiness or a count, not the ordered list.
        public var hasDisplayedItems: Bool {
            preferences.showHiddenFiles ? !items.isEmpty : items.contains { !isHiddenFileName($0.name) }
        }

        public var displayedItemCount: Int {
            preferences.showHiddenFiles ? items.count : items.reduce(0) { isHiddenFileName($1.name) ? $0 : $0 + 1 }
        }

        /// `searchResults`, with hidden entries dropped unless the preference is on, then narrowed
        /// to `selectedSearchCategories` when the type filter is active.
        public var displayedSearchResults: IdentifiedArrayOf<SearchResultItem>? {
            guard let searchResults else { return nil }
            let visible = preferences.showHiddenFiles ? searchResults : searchResults.filter { !isHiddenFileName($0.name) }
            guard !selectedSearchCategories.isEmpty else { return visible }
            return visible.filter { selectedSearchCategories.contains(Self.category(of: $0)) }
        }

        /// The categories actually present in the current (hidden filtered) results, in display
        /// order — the rows the filter sheet offers. Independent of the current selection, so
        /// toggling a category off doesn't make it vanish from the sheet.
        public var availableSearchCategories: [FileCategory] {
            guard let searchResults else { return [] }
            let visible = preferences.showHiddenFiles ? searchResults : searchResults.filter { !isHiddenFileName($0.name) }
            let present = Set(visible.map(Self.category(of:)))
            return FileCategory.allCases.filter(present.contains)
        }

        /// A search hit reports only `dir`/`file` for kind, so derive the extension from the name
        /// (the same thing the row icon does) before bucketing it. The extension is ignored for a
        /// directory, which `FileCategory.of` buckets as `.folder` off the flag alone.
        static func category(of result: SearchResultItem) -> FileCategory {
            FileCategory.of(kind: (result.name as NSString).pathExtension, isDirectory: result.isDirectory)
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
        /// Recompute which visible items are available offline (from the offline store), off the
        /// main actor. Sent on appear and when a download finishes.
        case computeOfflineAvailability
        case offlineAvailabilityComputed(Set<String>)
        case itemsResponse(Result<BrowseResult, FilesClientError>)
        case favoritesResponse([Favorite])
        case rowTapped(FileItem)
        case searchQueryChanged(String)
        case searchScopeChanged(SearchScope)
        case searchCategoryToggled(FileCategory)
        case searchFilterCleared
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
        /// "Open" tapped on the download toast while a preview cover is up: dismiss the cover,
        /// then jump to the Downloads tab once it's gone.
        case openDownloadsFromPreview
        /// "View in Shared" tapped on the created-share-link sheet while a preview cover is up.
        case goToSharedTabFromPreview
        case renameResponse(Result<RenameResult, FilesClientError>)
        case newFolderTapped
        case newFolderCancelled
        case newFolderConfirmed(String)
        case newFolderResponse(Result<FileItem, FilesClientError>)
        case deleteCancelled
        case deleteConfirmed
        /// Confirm came from a full-screen preview: dismiss the cover, then delete after a
        /// short settle so the list row animates out where the user can see it.
        case deleteConfirmedFromPreview
        case deleteImpactResponse(Result<DeleteImpact, FilesClientError>)
        case deleteResponse(Result<DeleteResult, FilesClientError>)
        case extractZipTapped(FileItem)
        case extractZipResponse(Result<FileItem, FilesClientError>)
        case compressTapped(FileItem)
        case compressResponse(Result<FileItem, FilesClientError>)
        case downloadTapped(FileItem, DownloadLocation, removeArchiveAfterDownload: Bool)
        case downloadProgressUpdated(String)
        /// macOS: the save panel was dismissed without choosing a destination.
        case downloadCancelled
        /// macOS: the folder picked for a bulk download.
        case bulkDownloadFolderChosen(URL)
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
        case beginUpload(UploadReviewFeature.PickSource)
        case uploadReview(PresentationAction<UploadReviewFeature.Action>)
        case copyTapped(FileItem)
        case moveTapped(FileItem)
        case bulkCopyTapped
        case bulkMoveTapped
        case clipboardCleared
        case pasteTapped(keepItemsAfterCopy: Bool)
        /// Keyboard driven actions for the Mac file table, acting on whatever rows are selected
        /// there (tracked in `selectedItemIDs` without entering select mode).
        case tableSelectionChanged(Set<FileItem.ID>)
        case copySelectionTapped
        case cutSelectionTapped
        case deleteSelectionTapped
        case renameSelectionTapped
        case infoSelectionTapped
        /// Mac: rows dragged onto a folder row in the same listing move into it.
        case itemsDroppedOnFolder(ids: [FileItem.ID], folder: FileItem)
        case retryTransferTapped
        case transferConflictCheckResponse(Result<[FileItem], FilesClientError>)
        case transferConflictResolved(TransferConflictChoice?)
        case transferResponse(Result<TransferOutcome, FilesClientError>)
        case destinationPicker(PresentationAction<DestinationPickerFeature.Action>)
        case infoTapped(FileItem)
        case permissionsTapped(FileItem)
        case permissions(PresentationAction<PermissionsFeature.Action>)
        case infoDismissed
        case infoMetadataResponse(Result<FileMetadata, FilesClientError>)
        case infoUsageResponse(Result<StorageUsage, FilesClientError>)
        case previewDismissed
        case previewFileResponse(Result<URL, FilesClientError>)
        case textContentResponse(Result<String, FilesClientError>)
        case openInBrowserTapped(FileItem)
        case googleDocsPointerResponse(item: FileItem, Result<URL, FilesClientError>)
        case textSaveTapped(String)
        case textContentRetryTapped
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
            /// "View in Shared" on the created-share-link sheet — switches to the Shared tab.
            case goToSharedTab
        }
    }

    @Dependency(\.filesClient) var filesClient
    @Dependency(\.directoryCacheStore) var directoryCacheStore
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date) var date
    @Dependency(\.localDownloadStore) var localDownloadStore
    @Dependency(\.uploadStaging) var uploadStaging
    @Dependency(\.openURL) var openURL
    @Dependency(\.offlineFileStore) var offlineFileStore
    @Dependency(\.saveLocationPicker) var saveLocationPicker
    // Internal (not private) so the effect helpers extracted into `BrowseFeature+*.swift`
    // can reference these cancel ids across files.
    enum CancelID: Hashable {
        case search, transfer, googleDocsPointer, deleteImpact, load, preview, info, previewDeferredAction
        case prefetchChildren, prefetchFavorites, offlineAvailability
        /// Per path, so spamming one item's star collapses to a single in flight toggle
        /// (the latest tap wins) while other items toggle independently.
        case favorite(String)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                // Guard on the phase, not `items.isEmpty` — a folder that is genuinely empty
                // would otherwise re-fetch on every return to it. A failed load stays put too
                // (retry is the refresh button), so only `.idle` triggers a fetch.
                guard state.phase == .idle else { return .none }
                return load(&state)

            case .refreshButtonTapped:
                return load(&state)

            case .computeOfflineAvailability:
                return computeOfflineAvailability(&state)

            case let .offlineAvailabilityComputed(ids):
                state.offlineItemIDs = ids
                return .none

            case let .itemsResponse(.success(result)):
                state.phase = .loaded
                state.dataSource = .live
                state.items = IdentifiedArray(Self.sortedAlphabetically(result.items), id: \.id, uniquingIDsWith: { first, _ in first })
                state.access = result.access
                return .merge(
                    search(&state),
                    computeOfflineAvailability(&state),
                    prefetch(
                        serverURL: state.serverURL,
                        paths: result.items.filter(\.isDirectory).map(\.id),
                        cancelID: CancelID.prefetchChildren
                    )
                )

            case let .itemsResponse(.failure(error)):
                // Offline (server unreachable) with a copy to show: keep it on screen under the
                // "saved copy" banner rather than a blocking error overlay. Prefer a fresh disk
                // read for its fetched-at stamp; otherwise keep whatever the cache-first paint
                // (or a prior load this session) already put in `state.items`. Only a real
                // server error, or offline with nothing cached, falls through to the error path.
                if error == .offline {
                    if let cached = directoryCacheStore.read(serverURL: state.serverURL, path: state.directoryPath) {
                        state.phase = .loaded
                        state.items = IdentifiedArray(Self.sortedAlphabetically(cached.items), id: \.id, uniquingIDsWith: { first, _ in first })
                        state.access = cached.access
                        state.dataSource = .cached(fetchedAt: cached.fetchedAt)
                        return .merge(search(&state), computeOfflineAvailability(&state))
                    } else if !state.items.isEmpty {
                        state.phase = .loaded
                        state.dataSource = .cached(fetchedAt: date.now)
                        return .merge(search(&state), computeOfflineAvailability(&state))
                    }
                }
                state.phase = .failed(error.userMessage)
                return .none

            case let .favoritesResponse(favorites):
                state.favoritePaths = Set(favorites.map(\.path))
                // Browse is the default tab, so its favorites load doubles as a launch time
                // "keep the folders you care about ready offline" pass.
                return prefetch(
                    serverURL: state.serverURL,
                    paths: favorites.map(\.path),
                    cancelID: CancelID.prefetchFavorites
                )

            case let .rowTapped(item):
                guard item.isDirectory else {
                    // Google Drive stub files (`.gsheet`, `.gdoc`, …) link out to a real
                    // Google document — open that, don't show the JSON stub.
                    if item.isGoogleDocsPointer {
                        return openGoogleDocsPointer(serverURL: state.serverURL, item: item)
                    }
                    // Sets `previewItem` unconditionally so the viewer presents immediately.
                    // - Files the app has no viewer for (archives it can't browse, known
                    //   binaries, undecodable video) get `UnsupportedFilePreviewView` — the
                    //   name/type/size + download/share actions, no fetch.
                    // - Streamable media (video/audio) plays live from `FilesClient.previewURL`.
                    // - Images/RAW load themselves per-page in the gallery view.
                    // - Browsable archives (.zip/.rar) list themselves in `ArchiveBrowserView`.
                    // Only PDFs and plain-text files need a fetch here.
                    state.previewItem = item
                    if item.isUnsupportedForPreview
                        || item.isBrowsableArchive
                        || item.isStreamableMedia
                        || ((item.isImage || item.isRawImage) && !item.isSVG) {
                        return .none
                    } else if item.isPreviewableViaDownload {
                        return loadPreview(&state, item: item)
                    } else {
                        return loadTextContent(&state, item: item)
                    }
                }
                return .send(.delegate(.openFolder(item)))

            case let .searchQueryChanged(query):
                // A focus change or keyboard dismiss can re-send the same text through the
                // field's binding; re-running `search` would reset results to the local pre-fill
                // and refetch, flashing the list. Only act on a real text change.
                guard query != state.searchQuery else { return .none }
                state.searchQuery = query
                return search(&state)

            case let .searchScopeChanged(scope):
                state.searchScope = scope
                return search(&state)

            case let .searchCategoryToggled(category):
                if state.selectedSearchCategories.contains(category) {
                    state.selectedSearchCategories.remove(category)
                } else {
                    state.selectedSearchCategories.insert(category)
                }
                return .none

            case .searchFilterCleared:
                state.selectedSearchCategories = []
                return .none

            case let .searchResultTapped(result):
                guard !result.isDirectory else {
                    return .send(.delegate(.openPath(path: result.id, title: result.name)))
                }
                // Search results only carry `dir`/`file` for `kind`, so rebuild the extension
                // from the name and hand a real `FileItem` to the same preview routing a
                // browse row tap uses. `dateModified`/`size` are unknown here, so the preview
                // cache treats it as fresh and re-fetches — fine for an occasional tap.
                let ext = (result.name as NSString).pathExtension.lowercased()
                let item = FileItem(
                    name: result.name,
                    path: result.path,
                    dateModified: date.now,
                    size: 0,
                    kind: ext.isEmpty ? "unknown" : ext,
                    supportsThumbnail: false
                )
                return .send(.rowTapped(item))

            case let .searchResultsResponse(.success(results)):
                state.isSearchingRemotely = false
                state.searchResults = IdentifiedArray(Self.sortedAlphabetically(results), id: \.id, uniquingIDsWith: { first, _ in first })
                // Drop any selected category the new results no longer contain, so the filter
                // can't strand the list on an empty set the sheet doesn't even offer.
                state.selectedSearchCategories.formIntersection(Set(state.availableSearchCategories))
                return .none

            case let .searchResultsResponse(.failure(error)):
                state.isSearchingRemotely = false
                state.searchResults = []
                // Surface it, otherwise a network blip during a search is indistinguishable from
                // a genuine empty result.
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
                state.deleteImpactCheck = .checking
                return checkDeleteImpact(&state, items: [item])

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

            case .openDownloadsFromPreview:
                let clock = self.clock
                return .merge(
                    .send(.previewDismissed),
                    .run { send in
                        try await clock.sleep(for: Constants.previewActionSettleDelay)
                        await send(.delegate(.openDownloadsTapped))
                    }
                    .cancellable(id: CancelID.previewDeferredAction, cancelInFlight: true)
                )

            case .goToSharedTabFromPreview:
                let clock = self.clock
                return .merge(
                    .send(.previewDismissed),
                    .run { send in
                        try await clock.sleep(for: Constants.previewActionSettleDelay)
                        await send(.delegate(.goToSharedTab))
                    }
                    .cancellable(id: CancelID.previewDeferredAction, cancelInFlight: true)
                )

            case let .renameResponse(.success(result)):
                state.isPerformingFileAction = false
                state.renameSheetItem = nil
                if let index = state.items.index(id: result.originalID) {
                    state.items.remove(at: index)
                    state.items.insert(result.renamed, at: index)
                }
                // A rename from a preview keeps the cover up — repoint it at the renamed item
                // so its title/actions follow.
                if state.previewItem?.id == result.originalID {
                    state.previewItem = result.renamed
                }
                syncListingCache(state)
                return .none

            case let .renameResponse(.failure(error)):
                state.isPerformingFileAction = false
                state.fileActionErrorMessage = error.userMessage
                return .none

            case .newFolderTapped:
                state.isNewFolderSheetPresented = true
                return .none

            case .newFolderCancelled:
                state.isNewFolderSheetPresented = false
                return .none

            case let .newFolderConfirmed(name):
                return confirmNewFolder(&state, name: name)

            case let .newFolderResponse(.success(folder)):
                state.isPerformingFileAction = false
                state.isNewFolderSheetPresented = false
                state.items.append(folder)
                syncListingCache(state)
                return .none

            case let .newFolderResponse(.failure(error)):
                state.isPerformingFileAction = false
                // Keep the sheet open (mirrors rename) so a server rejection (a name taken, a
                // permission) leaves the typed name in place for the user to correct and retry.
                state.fileActionErrorMessage = error.userMessage
                return .none

            case .deleteCancelled:
                state.deleteConfirmationItem = nil
                state.deleteImpactCheck = .idle
                return .cancel(id: CancelID.deleteImpact)

            case let .deleteImpactResponse(.success(impact)):
                state.deleteImpactCheck = .loaded(impact)
                return .none

            case .deleteImpactResponse(.failure):
                state.deleteImpactCheck = .unavailable
                return .none

            case .deleteConfirmed:
                return confirmDelete(&state)

            case .deleteConfirmedFromPreview:
                return .merge(
                    .send(.previewDismissed),
                    confirmDelete(&state, deferred: true)
                )

            case let .deleteResponse(.success(result)):
                state.isPerformingFileAction = false
                state.items.remove(id: result.itemID)
                let wasFavorited = state.favoritePaths.remove(result.itemID) != nil
                syncListingCache(state)
                return wasFavorited ? .send(.delegate(.favoritesChanged)) : .none

            case let .deleteResponse(.failure(error)):
                state.isPerformingFileAction = false
                state.fileActionErrorMessage = error.userMessage
                return .none

            case let .extractZipTapped(item):
                guard !state.isPerformingFileAction else { return .none }
                state.isPerformingFileAction = true
                state.fileActionProgressMessage = L10n.Browse.progressExtracting
                let serverURL = state.serverURL
                let filesClient = self.filesClient
                return .run { send in
                    await send(.extractZipResponse(try await apiResult { try await filesClient.extractZip(serverURL, item) }))
                }

            case let .extractZipResponse(.success(extracted)):
                state.isPerformingFileAction = false
                state.fileActionProgressMessage = nil
                state.items.append(extracted)
                syncListingCache(state)
                return .none

            case let .extractZipResponse(.failure(error)):
                state.isPerformingFileAction = false
                state.fileActionProgressMessage = nil
                state.fileActionErrorMessage = error.userMessage
                return .none

            case let .compressTapped(item):
                guard !state.isPerformingFileAction else { return .none }
                state.isPerformingFileAction = true
                state.fileActionProgressMessage = L10n.Browse.progressCompressing
                let serverURL = state.serverURL
                let filesClient = self.filesClient
                return .run { send in
                    await send(.compressResponse(try await apiResult { try await filesClient.compressItem(serverURL, item) }))
                }

            case let .compressResponse(.success(compressed)):
                state.isPerformingFileAction = false
                state.fileActionProgressMessage = nil
                state.items.append(compressed)
                syncListingCache(state)
                // Refetch so the new archive carries the same server metadata a normal listing
                // entry does and is browsable straight away, not only after a manual refresh.
                return load(&state)

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

            case .downloadCancelled:
                state.isPerformingFileAction = false
                state.isBulkActionInFlight = false
                state.fileActionProgressMessage = nil
                return .none

            case let .bulkDownloadFolderChosen(folder):
                state.lastSavedDownloadURL = folder
                return .none

            case let .downloadResponse(.success(result)):
                state.isPerformingFileAction = false
                state.fileActionProgressMessage = nil
                #if os(macOS)
                    state.lastSavedDownloadURL = result.destinationURL
                #endif
                state.downloadSuccessMessage = L10n.Browse.downloadSavedTo(downloadDestinationTitle(state, location: result.location))
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
                state.deleteImpactCheck = .checking
                let selected = state.selectedItemIDs.compactMap { state.items[id: $0] }
                return checkDeleteImpact(&state, items: selected)

            case .bulkDeleteCancelled:
                state.bulkDeleteConfirmationIsPresented = false
                state.deleteImpactCheck = .idle
                return .cancel(id: CancelID.deleteImpact)

            case .bulkDeleteConfirmed:
                return confirmBulkDelete(&state)

            case let .bulkDeleteResponse(.success(result)):
                state.isBulkActionInFlight = false
                for itemID in result.itemIDs {
                    state.items.remove(id: itemID)
                }
                var hadFavorited = false
                for itemID in result.itemIDs where state.favoritePaths.remove(itemID) != nil {
                    hadFavorited = true
                }
                state.isSelecting = false
                state.selectedItemIDs = []
                syncListingCache(state)
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
                    state.downloadSuccessMessage = L10n.Browse.downloadSavedAllTo(savedCount, downloadDestinationTitle(state, location: location))
                } else if savedCount > 0 {
                    state.downloadSuccessMessage = L10n.Browse.downloadSavedCountTo(savedCount, total, downloadDestinationTitle(state, location: location))
                } else {
                    state.fileActionErrorMessage = L10n.Browse.downloadBulkFailed
                }
                return .none

            case let .beginUpload(source):
                guard source.count > 0 else { return .none }
                state.uploadReview = UploadReviewFeature.State(
                    serverURL: state.serverURL,
                    startingDestination: state.directoryPath
                )
                return .send(.uploadReview(.presented(.stage(source))))

            case let .uploadReview(.presented(.delegate(.confirmed(files, destination)))):
                state.uploadReview = nil
                guard !files.isEmpty, !destination.isEmpty else { return .none }
                return .send(.delegate(.uploadRequested(files.map {
                    PendingUpload(id: $0.id, fileURL: $0.fileURL, fileName: $0.fileName, destination: destination)
                })))

            case .uploadReview(.presented(.delegate(.cancelled))):
                // Discard whatever staging already copied — those files are never uploaded now.
                let staged = state.uploadReview?.files.map(\.fileURL) ?? []
                state.uploadReview = nil
                guard !staged.isEmpty else { return .none }
                let uploadStaging = self.uploadStaging
                return .run { _ in await uploadStaging.discard(staged) }

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

            case let .tableSelectionChanged(ids):
                guard !state.isSelecting else { return .none }
                state.selectedItemIDs = ids
                // An open inspector follows the selection to the newly picked row.
                guard state.infoItem != nil, ids.count == 1,
                      let item = selectedItems(state).first, item.id != state.infoItem?.id
                else { return .none }
                return loadInfo(&state, item: item)

            case .copySelectionTapped:
                let items = selectedItems(state)
                guard !items.isEmpty else { return .none }
                state.$clipboard.withLock { $0 = FileClipboard(items: items, operation: .copy) }
                state.clipboardStagedMessage = items.count == 1
                    ? L10n.Browse.clipboardCopiedOne(items[0].name)
                    : L10n.Browse.clipboardCopiedMany(items.count)
                return .none

            case .cutSelectionTapped:
                let items = selectedItems(state)
                guard !items.isEmpty, state.access?.canDelete ?? false else { return .none }
                state.$clipboard.withLock { $0 = FileClipboard(items: items, operation: .move) }
                state.clipboardStagedMessage = items.count == 1
                    ? L10n.Browse.clipboardCutOne(items[0].name)
                    : L10n.Browse.clipboardCutMany(items.count)
                return .none

            case .deleteSelectionTapped:
                let items = selectedItems(state)
                guard !items.isEmpty, state.access?.canDelete ?? false else { return .none }
                return items.count == 1 ? .send(.deleteTapped(items[0])) : .send(.bulkDeleteTapped)

            case .renameSelectionTapped:
                let items = selectedItems(state)
                guard items.count == 1, state.access?.canWrite ?? false else { return .none }
                return .send(.renameTapped(items[0]))

            case let .itemsDroppedOnFolder(ids, folder):
                guard folder.isDirectory, state.access?.canDelete ?? false else { return .none }
                // Never into itself or one of its own subfolders.
                let items = state.items.filter { item in
                    ids.contains(item.id) && item.id != folder.id && !folder.id.hasPrefix(item.id + "/")
                }
                return runTransfer(&state, retry: TransferRetry(
                    items: Array(items), destination: folder.id, operation: .move, clearClipboard: false
                ))

            case .infoSelectionTapped:
                // ⌘I toggles: pressing it again for the item already shown closes the inspector.
                if state.infoItem != nil, state.infoItem?.id == selectedItems(state).first?.id {
                    return .send(.infoDismissed)
                }
                let items = selectedItems(state)
                guard items.count == 1 else { return .none }
                return .send(.infoTapped(items[0]))

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

            case let .permissionsTapped(item):
                state.permissions = PermissionsFeature.State(serverURL: state.serverURL, item: item)
                return .none

            case .permissions:
                return .none

            case .infoDismissed:
                state.infoItem = nil
                state.infoMetadata = nil
                state.infoUsage = nil
                state.infoPhase = .idle
                return .cancel(id: CancelID.info)

            case let .infoMetadataResponse(.success(metadata)):
                state.infoPhase = .loaded
                state.infoMetadata = metadata
                return .none

            case let .infoMetadataResponse(.failure(error)):
                state.infoPhase = .failed(error.userMessage)
                return .none

            case let .infoUsageResponse(.success(usage)):
                // Kept only when the server actually reported disk figures — a denied path
                // answers all zeros, which the "Server disk" section shouldn't show.
                state.infoUsage = usage.isMeaningful ? usage : nil
                return .none

            case .infoUsageResponse(.failure):
                return .none

            case .previewDismissed:
                state.previewItem = nil
                state.previewFileURL = nil
                state.previewPhase = .idle
                state.textContent = nil
                state.textPhase = .idle
                state.isSavingTextContent = false
                state.textSaveError = nil
                return .merge(.cancel(id: CancelID.preview), .cancel(id: CancelID.googleDocsPointer))

            case let .previewFileResponse(.success(fileURL)):
                state.previewPhase = .loaded
                state.previewFileURL = fileURL
                return .none

            case let .previewFileResponse(.failure(error)):
                state.previewPhase = .failed(error.userMessage)
                return .none

            case let .textContentResponse(.success(content)):
                state.textPhase = .loaded
                state.textContent = content
                return .none

            case let .textContentResponse(.failure(error)):
                state.textPhase = .failed(error.userMessage)
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

            case .textContentRetryTapped:
                guard let item = state.previewItem else { return .none }
                return loadTextContent(&state, item: item)

            case let .textSaveTapped(newContent):
                return confirmTextSave(&state, newContent: newContent)

            case let .textSaveResponse(.success(savedContent)):
                state.isSavingTextContent = false
                state.textContent = savedContent
                return .none

            case let .textSaveResponse(.failure(error)):
                state.isSavingTextContent = false
                state.textSaveError = error.userMessage
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
        .ifLet(\.$permissions, action: \.permissions) {
            PermissionsFeature()
        }
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

extension BrowseFeature {
    /// The selected rows in list order (the selection set itself is unordered).
    func selectedItems(_ state: State) -> [FileItem] {
        state.items.filter { state.selectedItemIDs.contains($0.id) }
    }
}
