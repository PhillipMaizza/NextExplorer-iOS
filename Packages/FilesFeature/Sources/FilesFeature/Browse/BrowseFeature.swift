import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import FolderPickerFeature
import Foundation
import Localization
import NetworkClient
import ShareUploads
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
        /// After a copy or move into the folder on screen, how many extra refetches wait for the
        /// new items to be listed, and how far apart. A server that finishes the copy after
        /// answering (or a listing fetched a moment too early) otherwise leaves the new
        /// "Name (2)" missing until a manual refresh.
        static let arrivalRechecks = 3
        static let arrivalRecheckDelay: Duration = .milliseconds(700)
        /// An action taken from a full-screen preview that also dismisses the cover (delete,
        /// "Open" on the download toast, "View in Shared") waits this long before it runs, so the
        /// cover finishes dismissing first and the effect: a row sliding out, a tab switch:
        /// plays on the list the user is now looking at, not mid transition.
        static let previewActionSettleDelay: Duration = .milliseconds(350)
        /// How long the Mac inspector waits on a newly selected row before loading it.
        static let inspectorFollowDelay: Duration = .milliseconds(200)
        /// Most folders warmed into the offline cache per prefetch pass, so opening a folder with
        /// hundreds of subfolders doesn't fan out hundreds of listings.
        static let maxPrefetchedFolders = 20
        /// Favorites are warmed on their own budget so subfolders never use it up.
        static let maxPrefetchedFavorites = 40
        /// Gateway and proxy answers (bad gateway, unavailable, gateway timeout, and Cloudflare's
        /// origin timeout) that say nothing about whether a slow mutation finished on the server.
        static let ambiguousMutationStatuses: Set<Int> = [502, 503, 504, 524]
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
    /// confirmation is on screen. `.unavailable` means the check itself failed: the delete
    /// still proceeds, the server still removes any linked shares, the alert just can't say
    /// how many.
    public enum DeleteImpactCheck: Equatable, Sendable {
        case idle
        case checking
        case loaded(DeleteImpact)
        case unavailable
    }

    public struct BulkDeleteResult: Equatable, Sendable {
        public let itemIDs: [String]
    }

    public struct BulkFavoriteToggleResult: Equatable, Sendable {
        public let added: [String]
        public let removed: [String]
        public let failedCount: Int
        public let totalCount: Int

        public init(added: [String], removed: [String], failedCount: Int = 0, totalCount: Int? = nil) {
            self.added = added
            self.removed = removed
            self.failedCount = failedCount
            self.totalCount = totalCount ?? added.count + removed.count + failedCount
        }
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
        /// The destination items that share a name with something being transferred: deleted
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
        /// The account scope the saved listings and lists are filed under, captured when this state
        /// was created, so a response landing after an account switch is saved to the account that asked.
        let cacheScope: String
        public var directoryPath: String
        public var title: String
        public var items: IdentifiedArrayOf<FileItem> = []
        public var favoritePaths: Set<String> = []
        /// A favorites answer has landed. Until then `favoritePaths` says nothing, and toggling a star
        /// would re add a folder that is already a favorite, resetting its label, icon and color.
        public var hasLoadedFavorites = false
        /// Ids of the items in this listing that are available offline (a pinned file, or a folder
        /// covered by a pinned root), so rows/cells can show an offline badge. Recomputed off the
        /// main actor when the listing loads, on appear, and when a download finishes.
        public var offlineItemIDs: Set<String> = []
        /// The server has personal folders on (`features.personal.enabled`). Only the root screen
        /// asks, since the root volume listing never includes the account's own folder.
        public var isPersonalSpaceEnabled = false
        public var access: FileAccess?
        /// The folder listing load lifecycle. `phase.hasLoaded` flips true the first time a
        /// browse response lands (success or failure), so the view shows the loading skeleton
        /// rather than the empty state until then; `phase.errorMessage` carries a failed load.
        public var phase: DataPhase = .idle
        /// `.cached` while the listing on screen is an offline copy; back to `.live` as soon as
        /// a fresh fetch lands. Drives the "showing saved copy" banner.
        public var dataSource: DataSource = .live
        /// The items on screen are the cache first paint of a load that has not answered yet, not
        /// something a live load confirmed: a real server error must not keep them (rule #11). Not
        /// derivable from `phase` and `dataSource`: a refresh over live items is also `.loading` and
        /// `.live`, and only this flag tells those items apart from an unconfirmed saved copy.
        public var isShowingCachePaint = false
        public var searchQuery = ""
        public var searchScope: SearchScope = .thisFolder

        /// How far below the root this folder sits: 0 at the root, 1 for a top level location.
        var folderDepth: Int {
            directoryPath.split(separator: "/").count
        }

        /// A search inside a folder stays in that folder and can be widened to everywhere; the
        /// root already searches everywhere.
        public var canWidenSearch: Bool {
            folderDepth > 0 && searchScope == .thisFolder
        }

        /// The scope a search actually runs with.
        public var effectiveSearchScope: SearchScope {
            folderDepth == 0 ? .everywhere : searchScope
        }
        public var searchResults: IdentifiedArrayOf<SearchResultItem>?
        /// True while a recursive backend search (either scope) is in flight, so the UI can show a
        /// spinner over the instant client side pre-fill until the authoritative results land.
        public var isSearchingRemotely = false
        /// The file type categories the search results are filtered to. Empty means "all types";
        /// otherwise a result shows only if its category is in the set. Only relevant while
        /// searching, and pruned to the categories actually present as results change.
        public var selectedSearchCategories: Set<FileCategory> = []
        /// How many results the search asks for; Show more steps it through
        /// `FilesClient.searchLimitSteps`, and a new query or scope starts over.
        public var searchLimit = FilesClient.searchLimitSteps[0]
        /// Why the latest server answer may be short of the whole truth, said rather than left
        /// to look like everything.
        public var searchShortfall: SearchShortfall?
        public var sortOption: SortOption = .name
        public var sortDirection: SortDirection = .ascending
        /// Read live from the same in-memory key `SettingsFeature` writes, so toggling
        /// "Show Hidden Files" is reflected here immediately, even in an already-open folder,
        /// with no manual refresh needed.
        @Shared(.inMemory("userPreferences")) public var preferences = UserPreferences()
        /// App wide "Copy" staging, shared under `FileClipboard.sharedKey` so the Paste
        /// action follows the user across every folder. `nil` when nothing is staged. Only
        /// ever holds copies: "Move" goes through `destinationPicker`, not the clipboard.
        @Shared(.inMemory(FileClipboard.sharedKey)) public var clipboard: FileClipboard?
        /// App wide ⌘Z history of reversible file operations (`FileUndoEntry`).
        @Shared(.inMemory(FileUndoEntry.sharedKey)) public var undoStack: [FileUndoEntry] = []
        /// Current account's downloads scope, so saved files land in this account's folder.
        @Shared(.inMemory(DownloadAccountScope.sharedKey)) public var downloadScope = ""
        /// The "Move" destination chooser, presented for a single item or a multi selection.
        @Presents public var destinationPicker: DestinationPickerFeature.State?
        /// The review sheet shown after files are picked from the `+` menu: file list,
        /// destination folder, total size, Upload button. On confirm its files become
        /// `PendingUpload`s handed up to the app wide queue.
        @Presents public var uploadReview: UploadReviewFeature.State?
        /// The "Permissions" sheet for a single item: view/chmod/chown via `/api/permissions`.
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
        /// Items a copy or move into this folder created that the listing has not shown yet,
        /// and how many more refetches may wait for them (`Constants.arrivalRechecks`).
        public var awaitedArrivalIDs: Set<FileItem.ID> = []
        public var arrivalChecksLeft = 0
        /// Non nil while a transfer is waiting on the user's answer to a name-collision prompt.
        public var transferConflict: TransferConflict?
        /// Set when an item is staged with "Copy"; `BrowseContentView` turns it into a brief
        /// "<name> copied" toast.
        public var clipboardStagedMessage: String?
        /// Item currently being renamed via the native rename alert. The in-progress text
        /// itself lives in `BrowseContentView`'s own `@State`, not here: a `.alert`'s
        /// `TextField` bound through a TCA `.sending` binding didn't reliably propagate
        /// keystrokes back out, so `renameConfirmed` is sent the final text directly instead.
        public var renameSheetItem: FileItem?
        /// Whether the "New folder" name sheet is open. Like rename, the draft text lives in
        /// `BrowseContentView`'s own `@State`; `newFolderConfirmed` carries the final name.
        public var isNewFolderSheetPresented = false
        public var isNewFileSheetPresented = false
        /// Extra file types this server's text editor opens (`EDITOR_EXTENSIONS`), loaded when the
        /// New File sheet opens; the defaults apply until then or when the server can't be asked.
        public var newFileServerExtensions: [String] = []
        /// The file New File just made, so its preview opens straight into the editor; cleared
        /// when that preview closes.
        public var newlyCreatedFileID: FileItem.ID?
        /// Item awaiting a destructive confirmation before `deleteConfirmed` actually deletes it.
        public var deleteConfirmationItem: FileItem?
        /// Share-link fallout of the pending delete, single or bulk: only one confirmation is
        /// ever on screen at once, so one field covers both. Filled in by `delete-impact` while
        /// the alert is up; reset to `.idle` when the alert is dismissed.
        public var deleteImpactCheck: DeleteImpactCheck = .idle
        public var isPerformingFileAction = false
        public var fileActionErrorMessage: String?
        /// Whether the list/grid is in multi-select mode: toggled from the toolbar, not tied
        /// to any particular item. `selectedItemIDs` is always cleared when this flips off.
        public var isSelecting = false
        public var selectedItemIDs: Set<FileItem.ID> = []
        public var isBulkActionInFlight = false
        public var bulkDeleteConfirmationIsPresented = false
        /// Drives a persistent progress toast: `nil` when no extract/compress/download is
        /// running. Rename/delete don't set this: they're fast enough, and already have their
        /// own alert-driven confirm flow, that a progress indicator would just flicker.
        public var fileActionProgressMessage: String?
        /// Set when a download is queued from a preview cover, which hides the app level progress
        /// bar; `BrowseContentView` turns it into a toast with an Open action. Never cleared by the
        /// reducer, only overwritten by the next one.
        public var downloadSuccessMessage: String?
        /// Item the "Get Info" sheet is showing, alongside its fetched metadata (or the
        /// still-loading/error state while `GET /api/metadata/*` is in flight).
        public var infoItem: FileItem?
        public var infoMetadata: FileMetadata?
        /// Server disk usage for `infoItem` when it's a directory and the endpoint returned
        /// real figures: drives the Get Info sheet's "Server disk" section.
        public var infoUsage: StorageUsage?
        /// The `GET /api/metadata/*` load lifecycle for the Get Info sheet. `isLoadingInfoMetadata`
        /// / `infoErrorMessage` are derived from it (rule #8: one phase, not a bool + error pair).
        public var infoPhase: DataPhase = .idle
        public var isLoadingInfoMetadata: Bool { infoPhase == .loading }
        public var infoErrorMessage: String? { infoPhase.errorMessage }
        /// Item being downloaded for the QuickLook viewer (tapping a file), alongside the
        /// local temp file `previewFile` produces once `GET /api/preview` finishes. Only
        /// used for PDFs: images/RAW load themselves per-page in the gallery view, and
        /// video/audio stream directly, neither going through this at all.
        public var previewItem: FileItem?
        public var previewFileURL: URL?
        /// The `GET /api/preview` download lifecycle. `isLoadingPreview` / `previewErrorMessage`
        /// are derived from it.
        public var previewPhase: DataPhase = .idle
        public var isLoadingPreview: Bool { previewPhase == .loading }
        public var previewErrorMessage: String? { previewPhase.errorMessage }
        /// Text content for `previewItem` when it's neither previewable-via-download nor
        /// streamable (anything `GET /api/preview` 415s on): fetched/saved via the real
        /// `/api/editor` endpoint, the server's actual text view+edit path.
        public var textContent: String?
        /// The `/api/editor` read lifecycle. A save is a separate mutation (`isSavingTextContent`
        /// + `textSaveError`), so it never rewinds a loaded editor back to a load phase.
        public var textPhase: DataPhase = .idle
        /// The text of every save in flight, by the path it writes: keyed per file so a response
        /// landing after the preview closed or moved on never touches another file's editor, a second
        /// file can be saved while the first is still answering, and the conflict prompt can resend
        /// the text on Overwrite.
        var savingTexts: [String: String] = [:]
        public var isSavingTextContent: Bool {
            previewItem.map { savingTexts[$0.id] != nil } ?? false
        }
        /// Set while a save found the file changed on the server and the user has not chosen between
        /// Overwrite and Reload: a further save asks again instead of silently replacing the changes.
        var textSaveConflict: TextSaveConflict?
        public var isTextSaveConflictPresented: Bool { textSaveConflict?.isAlertPresented ?? false }

        /// The text a save could not write because the file changed on the server, and whether the
        /// alert asking what to do is showing (dismissing it keeps the conflict pending).
        struct TextSaveConflict: Equatable, Sendable {
            var pendingText: String
            var isAlertPresented = true
        }
        public var textSaveError: String?
        public var isLoadingTextContent: Bool { textPhase == .loading }
        /// A load failure (from `textPhase`) or a save failure (`textSaveError`): they never
        /// coexist, so one accessor drives the editor's error surface as before.
        public var textEditorErrorMessage: String? { textPhase.errorMessage ?? textSaveError }

        public var isSearching: Bool { !searchQuery.isEmpty }

        /// Typed, but too short for the server to search; only the instant matches show.
        public var isSearchTermTooShort: Bool {
            SearchTerm(searchQuery).isTooShort
        }

        public var canShowMoreSearchResults: Bool {
            guard case .firstOnly = searchShortfall else { return false }
            return searchLimit < (FilesClient.searchLimitSteps.last ?? searchLimit)
        }

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
        /// order: the rows the filter sheet offers. Independent of the current selection, so
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
            @Dependency(\.cacheScope) var cacheScopeSource
            cacheScope = cacheScopeSource.current()
            // The last known answer paints with the first frame, so the entry never pops in above
            // the volumes (shifting them under the user's finger) once the features call returns.
            if directoryPath.isEmpty {
                @Dependency(\.jsonCacheStore) var jsonCacheStore
                isPersonalSpaceEnabled = ListCache.load(
                    jsonCacheStore, BrowseFeature.personalSpaceCacheNamespace, serverURL: serverURL, scope: cacheScope, as: Bool.self
                )?.value ?? false
            }
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
        /// The saved listing read off the main actor for an offline failure, `nil` when none is stored.
        case offlineListingResolved(CachedDirectory?, FilesClientError)
        /// The saved listing read off the main actor to paint a first load, `nil` when none is stored.
        case cachedListingPainted(CachedDirectory)
        case serverFeaturesResponse(ServerFeatures)
        case personalSpaceTapped
        case rowTapped(FileItem)
        case searchQueryChanged(String)
        case searchScopeChanged(SearchScope)
        case searchCategoryToggled(FileCategory)
        case searchFilterCleared
        case searchResultTapped(SearchResultItem)
        case searchShowMoreTapped
        case searchResultsResponse(Result<SearchPage, FilesClientError>)
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
        case newFileTapped
        case newFileCancelled
        case newFileConfirmed(String)
        case newFileExtensionsLoaded([String])
        case newFileResponse(Result<FileItem, FilesClientError>)
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
        case downloadTapped(FileItem)
        /// Files staged without the review sheet: a Mac drop or pick, or files shared from another
        /// app when Settings says to upload them to the default folder without asking.
        case directUploadStaged([PickedFile], destination: String, requested: Int)
        #if os(macOS)
            /// Files opened from Finder name no folder, so they always go through the review sheet.
            case reviewUpload(UploadReviewFeature.PickSource)
            /// A search result's Show in Enclosing Folder: ends the search and opens its folder.
            case searchResultEnclosingFolderTapped(SearchResultItem)
        #endif
        /// Files dropped on a folder row (Finder on a Mac, the Files app on an iPad).
        case filesDroppedOnFolder([URL], folder: FileItem)
        /// Rows dragged in from another Browse window, moved into `destination`.
        case itemsDroppedFromOtherWindow([FileItem], destination: String)
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
        case bulkDownloadTapped
        case beginUpload(UploadReviewFeature.PickSource)
        /// Files another app shared in: opens the upload review here, or adds them to one already open.
        case receiveSharedFiles([URL])
        /// Shared files that go through the review sheet, starting in Settings' default folder.
        case reviewSharedFiles([URL], startingAt: String?)
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
        /// Copies the selection into its own folder; the server names the copies "Name (2)".
        case duplicateSelectionTapped
        /// Reverses the last recorded file operation (⌘Z).
        case undoTapped
        case undoResponse(Result<Bool, FilesClientError>)
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
        case textSaveResponse(path: String, result: Result<String, FilesClientError>)
        case textSaveOverwriteTapped
        case textSaveReloadTapped
        case textSaveConflictDismissed
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case openFolder(FileItem)
            case openPath(path: String, title: String)
            case favoritesChanged
            /// Files the user picked from the `+` menu, each already carrying its destination
            /// folder: bubbled up to `MainTabFeature`'s app-wide upload queue.
            case uploadRequested([PendingUpload])
            /// Items handed to `MainTabFeature`'s app wide download queue.
            case downloadRequested([FileItem])
            /// Mac: items placed in Finder through the save panel, for the same queue.
            case saveRequested([DownloadSaveRequest])
            /// A copy/move just changed what's on the server. `BrowseTabFeature` re-fetches
            /// the whole live navigation stack so both the source and destination listings
            /// reflect the new state.
            case directoryContentsChanged
            /// The "Open" button on the download-success toast: switches to the Downloads
            /// tab so the user can see where the file landed.
            case openDownloadsTapped
            /// "View in Shared" on the created-share-link sheet: switches to the Shared tab.
            case goToSharedTab
        }
    }

    @Dependency(\.filesClient) var filesClient
    @Dependency(\.directoryCacheStore) var directoryCacheStore
    @Dependency(\.jsonCacheStore) var jsonCacheStore
    static let personalSpaceCacheNamespace = "personalSpace"
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date) var date
    @Dependency(\.localDownloadStore) var localDownloadStore
    @Dependency(\.uploadStaging) var uploadStaging
    @Dependency(\.uploadDefaults) var uploadDefaults
    @Dependency(\.openURL) var openURL
    @Dependency(\.offlineFileStore) var offlineFileStore
    @Dependency(\.connectivity) var connectivity
    @Dependency(\.saveLocationPicker) var saveLocationPicker
    // Internal (not private) so the effect helpers extracted into `BrowseFeature+*.swift`
    // can reference these cancel ids across files.
    enum CancelID: Hashable {
        case search, transfer, googleDocsPointer, deleteImpact, load, preview, info, previewDeferredAction
        case prefetchChildren, prefetchFavorites, offlineAvailability, arrivalRecheck, newFileExtensions
        /// Per path, so spamming one item's star collapses to a single in flight toggle
        /// (the latest tap wins) while other items toggle independently.
        case favorite(String)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                // Guard on the phase, not `items.isEmpty`: a folder that is genuinely empty
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
                state.isShowingCachePaint = false
                state.items = IdentifiedArray(Self.sortedAlphabetically(result.items), id: \.id, uniquingIDsWith: { first, _ in first })
                state.access = result.access
                return .merge(
                    recheckArrivals(&state),
                    search(&state),
                    computeOfflineAvailability(&state),
                    prefetch(
                        serverURL: state.serverURL,
                        paths: result.items.filter(\.isDirectory).map(\.id),
                        scope: state.cacheScope,
                        preferred: state.favoritePaths,
                        shouldIncludePinnedRoots: true,
                        limit: Constants.maxPrefetchedFolders,
                        cancelID: CancelID.prefetchChildren
                    )
                )

            case let .itemsResponse(.failure(error)):
                guard error == .offline else { return failItemsLoad(&state, error) }
                let directoryCacheStore = directoryCacheStore.bound(to: state.cacheScope)
                let serverURL = state.serverURL
                let directoryPath = state.directoryPath
                return .run { send in
                    await send(.offlineListingResolved(directoryCacheStore.read(serverURL: serverURL, path: directoryPath), error))
                }
                .cancellable(id: CancelID.load)

            case let .offlineListingResolved(cached, error):
                // Offline (server unreachable) with a copy to show: keep it on screen under the
                // "saved copy" banner rather than a blocking error overlay. Prefer the disk copy for its
                // fetched at stamp; otherwise keep whatever the cache first paint (or a prior load this
                // session) already put in `state.items`. Only a real server error, or offline with
                // nothing cached, falls through to the error path.
                state.isShowingCachePaint = false
                if let cached {
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
                return failItemsLoad(&state, error)

            case let .cachedListingPainted(cached):
                guard state.phase == .loading, state.items.isEmpty else { return .none }
                state.items = IdentifiedArray(uniqueElements: Self.sortedAlphabetically(cached.items))
                state.access = cached.access
                state.isShowingCachePaint = true
                return .none

            case let .serverFeaturesResponse(features):
                state.isPersonalSpaceEnabled = features.isPersonalEnabled
                let jsonCacheStore = jsonCacheStore
                let serverURL = state.serverURL
                let cacheScope = state.cacheScope
                return .run { _ in
                    ListCache.save(jsonCacheStore, Self.personalSpaceCacheNamespace, serverURL: serverURL, scope: cacheScope, value: features.isPersonalEnabled)
                }

            case .personalSpaceTapped:
                return .send(.delegate(.openPath(path: PersonalSpace.rootPath, title: L10n.Browse.myFiles)))

            case let .favoritesResponse(favorites):
                state.favoritePaths = Set(favorites.map(\.path))
                state.hasLoadedFavorites = true
                // Browse is the default tab, so its favorites load doubles as a launch time
                // "keep the folders you care about ready offline" pass.
                return prefetch(
                    serverURL: state.serverURL,
                    paths: Self.favoriteFolderPaths(favorites, knownItems: state.items),
                    scope: state.cacheScope,
                    limit: Constants.maxPrefetchedFavorites,
                    cancelID: CancelID.prefetchFavorites
                )

            case let .rowTapped(item):
                guard item.isDirectory else {
                    // Google Drive stub files (`.gsheet`, `.gdoc`, …) link out to a real
                    // Google document: open that, don't show the JSON stub.
                    if item.isGoogleDocsPointer {
                        return openGoogleDocsPointer(serverURL: state.serverURL, item: item)
                    }
                    // Sets `previewItem` unconditionally so the viewer presents immediately.
                    // - Files the app has no viewer for (archives it can't browse, known
                    //   binaries, undecodable video) get `UnsupportedFilePreviewView`: the
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
                // A focus change or keyboard dismiss resends the same text through the field's
                // binding, and a typed space leaves the term the server reads unchanged; rerunning
                // `search` would reset results to the local prefill and refetch, flashing the
                // list. Only a new term searches again; the pending one keeps its debounce.
                let isNewTerm = SearchTerm(query) != SearchTerm(state.searchQuery)
                state.searchQuery = query
                guard isNewTerm else { return .none }
                state.searchLimit = FilesClient.searchLimitSteps[0]
                return search(&state)

            case let .searchScopeChanged(scope):
                guard scope != state.searchScope else { return .none }
                state.searchScope = scope
                state.searchLimit = FilesClient.searchLimitSteps[0]
                return search(&state, isDebounced: false)

            case .searchShowMoreTapped:
                guard state.canShowMoreSearchResults else { return .none }
                state.searchLimit = FilesClient.searchLimitSteps.first { $0 > state.searchLimit } ?? state.searchLimit
                state.isSearchingRemotely = true
                return fetchSearchResults(state, isDebounced: false)

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
                    // Opening a folder ends the search, as in Finder, so the search never carries
                    // into the folder it opens.
                    state.searchQuery = ""
                    return .merge(
                        search(&state),
                        .send(.delegate(.openPath(path: result.id, title: result.name)))
                    )
                }
                // Search results only carry `dir`/`file` for `kind`, so rebuild the extension
                // from the name and hand a real `FileItem` to the same preview routing a
                // browse row tap uses. `dateModified`/`size` are unknown here, so the preview
                // cache treats it as fresh and re-fetches: fine for an occasional tap.
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

            case let .searchResultsResponse(.success(page)):
                state.isSearchingRemotely = false
                // The server ranks its answer (names first, closest first, then contents by
                // relevance), so it stays in that order.
                state.searchResults = IdentifiedArray(page.items, id: \.id, uniquingIDsWith: { first, _ in first })
                state.searchShortfall = SearchShortfall(page)
                // Drop any selected category the new results no longer contain, so the filter
                // can't strand the list on an empty set the sheet doesn't even offer.
                state.selectedSearchCategories.formIntersection(Set(state.availableSearchCategories))
                return .none

            case let .searchResultsResponse(.failure(error)):
                state.isSearchingRemotely = false
                state.searchResults = []
                state.searchShortfall = nil
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
                guard item.isDirectory, state.hasLoadedFavorites else { return .none }
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
                let previousName = state.items[id: result.originalID]?.name ?? (result.originalID as NSString).lastPathComponent
                state.$undoStack.withLock { $0.record(FileUndoEntry(.renamed(result.renamed, previousName: previousName))) }
                if let index = state.items.index(id: result.originalID) {
                    state.items.remove(at: index)
                    state.items.insert(result.renamed, at: index)
                }
                // A rename from a preview keeps the cover up: repoint it at the renamed item
                // so its title/actions follow.
                if state.previewItem?.id == result.originalID {
                    state.previewItem = result.renamed
                }
                syncListingCache(state)
                // The Mac inspector follows the rename instead of showing the old path.
                if state.infoItem?.id == result.originalID {
                    return loadInfo(&state, item: result.renamed)
                }
                return .none

            case let .renameResponse(.failure(error)):
                state.isPerformingFileAction = false
                state.fileActionErrorMessage = error.userMessage
                return refetchAfterAmbiguousFailure(&state, error)

            case .newFolderTapped:
                // The menu hides it where the folder refuses new folders; a keyboard shortcut
                // must not get past that either.
                guard state.access?.canCreateFolder ?? true else { return .none }
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
                state.$undoStack.withLock { $0.record(FileUndoEntry(.created([folder]))) }
                syncListingCache(state)
                return .none

            case let .newFolderResponse(.failure(error)):
                state.isPerformingFileAction = false
                // Keep the sheet open (mirrors rename) so a server rejection (a name taken, a
                // permission) leaves the typed name in place for the user to correct and retry.
                state.fileActionErrorMessage = error.userMessage
                return .none

            case .newFileTapped:
                guard state.access?.canCreateFile ?? true else { return .none }
                state.isNewFileSheetPresented = true
                let serverURL = state.serverURL
                let filesClient = filesClient
                return .run { send in
                    if let extensions = try? await filesClient.serverFeatures(serverURL).editorExtensions, !extensions.isEmpty {
                        await send(.newFileExtensionsLoaded(extensions))
                    }
                }
                .cancellable(id: CancelID.newFileExtensions, cancelInFlight: true)

            case .newFileCancelled:
                state.isNewFileSheetPresented = false
                return .cancel(id: CancelID.newFileExtensions)

            case let .newFileExtensionsLoaded(extensions):
                state.newFileServerExtensions = extensions
                return .none

            case let .newFileConfirmed(name):
                return confirmNewFile(&state, name: name)

            case let .newFileResponse(.success(file)):
                state.isPerformingFileAction = false
                state.isNewFileSheetPresented = false
                state.items.append(file)
                state.$undoStack.withLock { $0.record(FileUndoEntry(.created([file]))) }
                syncListingCache(state)
                // Straight into the editor: an empty file is only ever made to be written in. After
                // the sheet has gone, since a cover presented mid dismissal can be dropped on iOS.
                state.newlyCreatedFileID = file.id
                let clock = self.clock
                return .run { send in
                    try await clock.sleep(for: Constants.previewActionSettleDelay)
                    await send(.rowTapped(file))
                }
                .cancellable(id: CancelID.previewDeferredAction, cancelInFlight: true)

            case let .newFileResponse(.failure(error)):
                state.isPerformingFileAction = false
                // The sheet stays open with the typed name, as for a new folder.
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
                return refetchAfterAmbiguousFailure(&state, error)

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
                return refetchAfterAmbiguousFailure(&state, error)

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
                return refetchAfterAmbiguousFailure(&state, error)

            case let .downloadTapped(item):
                #if os(macOS)
                    // A Mac saves where the user says, through the save panel, then the queue saves it there.
                    return startDownload(&state, item: item)
                #else
                    if state.previewItem != nil {
                        state.downloadSuccessMessage = L10n.DownloadQueue.barTitleOne(item.name)
                    }
                    return .send(.delegate(.downloadRequested([item])))
                #endif

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
                return refetchAfterAmbiguousFailure(&state, error)

            case .bulkFavoriteTapped:
                guard state.hasLoadedFavorites else { return .none }
                return startBulkFavorite(&state)

            case let .bulkFavoriteResponse(result):
                state.isBulkActionInFlight = false
                state.favoritePaths.formUnion(result.added)
                state.favoritePaths.subtract(result.removed)
                state.isSelecting = false
                state.selectedItemIDs = []
                if result.failedCount > 0 {
                    state.fileActionErrorMessage = L10n.Browse.bulkFavoriteFailed(result.failedCount, result.totalCount)
                }
                let didChangeAnything = !result.added.isEmpty || !result.removed.isEmpty
                return didChangeAnything ? .send(.delegate(.favoritesChanged)) : .none

            case .bulkDownloadTapped:
                let targets = state.items.filter { state.selectedItemIDs.contains($0.id) }
                guard !targets.isEmpty else { return .none }
                state.isSelecting = false
                state.selectedItemIDs = []
                #if os(macOS)
                    return startBulkDownload(&state, targets: Array(targets))
                #else
                    return .send(.delegate(.downloadRequested(Array(targets))))
                #endif

            case let .beginUpload(source):
                guard source.count > 0 else { return .none }
                #if os(macOS)
                    // A Mac drop or file pick already says where the files go (the folder on
                    // screen), so they upload straight away instead of through the review sheet.
                    if case let .documents(urls) = source, !state.directoryPath.isEmpty {
                        return stageDirectUpload(urls, destination: state.directoryPath)
                    }
                #endif
                return openUploadReview(source, state: &state)

            #if os(macOS)
                case let .searchResultEnclosingFolderTapped(result):
                    state.searchQuery = ""
                    let title = result.path.isEmpty ? L10n.Browse.navigationTitle : (result.path as NSString).lastPathComponent
                    return .merge(
                        search(&state),
                        .send(.delegate(.openPath(path: result.path, title: title)))
                    )

                case let .reviewUpload(source):
                    return openUploadReview(source, state: &state)

            #endif

            case let .itemsDroppedFromOtherWindow(dropped, destination):
                // The source folder lives in another window, so the backend enforces its canDelete. This window
                // is the destination: canWrite is the client side guard, as the web client's paste check.
                guard state.access?.canWrite ?? false else { return .none }
                // Not where they already are, and never into themselves or their own subfolders.
                let items = dropped.filter { item in
                    item.path != destination && item.id != destination && !destination.hasPrefix(item.id + "/")
                }
                return runTransfer(&state, retry: TransferRetry(
                    items: items, destination: destination, operation: .move, clearClipboard: false
                ))

            case let .filesDroppedOnFolder(urls, folder):
                // Finder files dropped on a folder row go into that folder, as in Finder.
                guard folder.isDirectory, !urls.isEmpty, state.access?.canUpload ?? false else {
                    return BrowseDropHandler.discardStagedFiles(urls)
                }
                return stageDirectUpload(urls, destination: folder.id)

            case let .directUploadStaged(files, destination, _):
                guard !files.isEmpty else {
                    state.fileActionErrorMessage = L10n.Uploads.stagingFailed
                    return .none
                }
                return .send(.delegate(.uploadRequested(files.map {
                    PendingUpload(id: $0.id, fileURL: $0.fileURL, fileName: $0.fileName, destination: destination)
                })))

            case let .receiveSharedFiles(urls):
                guard !urls.isEmpty else { return .none }
                // Settings > Shared Files: a default folder with Upload Without Asking takes them
                // straight there, no sheet.
                let defaults = uploadDefaults.loadActive()
                if let folder = defaults.directFolder {
                    return stageDirectUpload(urls, destination: folder)
                }
                if state.uploadReview != nil {
                    return .send(.uploadReview(.presented(.stage(.documents(urls)))))
                }
                let review = Action.reviewSharedFiles(urls, startingAt: defaults.folderPath)
                // An open preview would cover the review sheet.
                if state.previewItem != nil {
                    return .concatenate(.send(.previewDismissed), .send(review))
                }
                return .send(review)

            case let .reviewSharedFiles(urls, startingAt):
                return openUploadReview(.documents(urls), startingAt: startingAt, state: &state)

            case let .uploadReview(.presented(.delegate(.confirmed(files, destination)))):
                state.uploadReview = nil
                guard !files.isEmpty, !destination.isEmpty else { return .none }
                return .send(.delegate(.uploadRequested(files.map {
                    PendingUpload(id: $0.id, fileURL: $0.fileURL, fileName: $0.fileName, destination: destination)
                })))

            case .uploadReview(.presented(.delegate(.cancelled))):
                // Discard whatever staging already copied: those files are never uploaded now.
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
                return loadInfo(&state, item: item, settle: Constants.inspectorFollowDelay)

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

            case .undoTapped:
                return undo(&state)

            case .undoResponse(.success):
                state.isPerformingFileAction = false
                return .send(.delegate(.directoryContentsChanged))

            case let .undoResponse(.failure(error)):
                state.isPerformingFileAction = false
                state.fileActionErrorMessage = error.userMessage
                return .send(.delegate(.directoryContentsChanged))

            case .duplicateSelectionTapped:
                let items = selectedItems(state)
                guard !items.isEmpty, !state.directoryPath.isEmpty, state.access?.canWrite ?? false else { return .none }
                return performTransfer(&state, retry: TransferRetry(
                    items: items,
                    destination: state.directoryPath,
                    operation: .copy,
                    clearClipboard: false,
                    resolution: .keepBoth
                ))

            case .deleteSelectionTapped:
                let items = selectedItems(state)
                guard !items.isEmpty, state.access?.canDelete ?? false else { return .none }
                return items.count == 1 ? .send(.deleteTapped(items[0])) : .send(.bulkDeleteTapped)

            case .renameSelectionTapped:
                let items = selectedItems(state)
                guard items.count == 1, state.access?.canWrite ?? false else { return .none }
                return .send(.renameTapped(items[0]))

            case let .itemsDroppedOnFolder(ids, folder):
                // A move deletes the original from this folder, so the backend (prepareTransfer) asks for
                // canDelete on the source and only read on the destination.
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
                    // The listing failed: fall back to the server's safe auto-rename rather
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
                let sources = state.pendingTransferRetry?.items ?? []
                state.isPerformingFileAction = false
                state.fileActionProgressMessage = nil
                state.pendingTransferRetry = nil
                state.transferErrorMessage = nil
                if outcome.clearClipboard {
                    state.$clipboard.withLock { $0 = nil }
                }
                state.transferSuccessMessage = Self.transferSuccessMessage(for: outcome)
                applyTransfer(&state, outcome: outcome, sources: sources)
                awaitArrivals(&state, from: outcome.result)
                return .send(.delegate(.directoryContentsChanged))

            case let .transferResponse(.failure(error)):
                state.isPerformingFileAction = false
                state.fileActionProgressMessage = nil
                state.transferErrorMessage = error.userMessage
                return refetchAfterAmbiguousFailure(&state, error)

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
                // Kept only when the server actually reported disk figures: a denied path
                // answers all zeros, which the "Server disk" section shouldn't show.
                state.infoUsage = usage.isMeaningful ? usage : nil
                return .none

            case .infoUsageResponse(.failure):
                return .none

            case .previewDismissed:
                state.newlyCreatedFileID = nil
                state.previewItem = nil
                state.previewFileURL = nil
                state.previewPhase = .idle
                state.textContent = nil
                state.textPhase = .idle
                state.textSaveError = nil
                state.textSaveConflict = nil
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
                    // Couldn't read the stub or it had no usable link: fall back to showing
                    // it in the text viewer rather than leaving the tap dead.
                    state.previewItem = item
                    return loadTextContent(&state, item: item)
                }

            case .textContentRetryTapped:
                guard let item = state.previewItem else { return .none }
                return loadTextContent(&state, item: item)

            case let .textSaveTapped(newContent):
                return confirmTextSave(&state, newContent: newContent)

            case let .textSaveResponse(path, .success(savedContent)):
                let isStillOpen = path == state.previewItem?.id
                state.savingTexts[path] = nil
                if isStillOpen {
                    state.textContent = savedContent
                }
                return .none

            case let .textSaveResponse(path, .failure(error)):
                let isStillOpen = path == state.previewItem?.id
                let pendingText = state.savingTexts.removeValue(forKey: path)
                if isStillOpen, error == .changedOnServer {
                    state.textSaveConflict = pendingText.map { State.TextSaveConflict(pendingText: $0) }
                    state.textSaveError = error.userMessage
                } else if isStillOpen {
                    state.textSaveError = error.userMessage
                } else {
                    state.fileActionErrorMessage = error.userMessage
                }
                return .none

            case .textSaveOverwriteTapped:
                guard let content = state.textSaveConflict?.pendingText else { return .none }
                state.textSaveConflict = nil
                state.textSaveError = nil
                return confirmTextSave(&state, newContent: content)

            case .textSaveReloadTapped:
                guard let item = state.previewItem else { return .none }
                return loadTextContent(&state, item: item)

            case .textSaveConflictDismissed:
                state.textSaveConflict?.isAlertPresented = false
                state.textSaveError = nil
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
        // An inspector open on an item that left this folder (deleted, moved away, gone in a
        // refresh) closes, rather than offering actions on a path that no longer exists.
        .onChange(of: \.items) { _, items in
            Reduce { state, _ in
                guard let shown = state.infoItem, items[id: shown.id] == nil else { return .none }
                state.infoItem = nil
                state.infoMetadata = nil
                state.infoUsage = nil
                state.infoPhase = .idle
                return .cancel(id: CancelID.info)
            }
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
    private func openUploadReview(
        _ source: UploadReviewFeature.PickSource,
        startingAt folder: String? = nil,
        state: inout State
    ) -> Effect<Action> {
        state.uploadReview = UploadReviewFeature.State(
            serverURL: state.serverURL,
            startingDestination: folder.flatMap { $0.isEmpty ? nil : $0 } ?? state.directoryPath
        )
        return .send(.uploadReview(.presented(.stage(source))))
    }

    /// Stages the files and uploads them to `destination` straight away, no review sheet.
    func stageDirectUpload(_ urls: [URL], destination: String) -> Effect<Action> {
        let uploadStaging = uploadStaging
        return .run { send in
            var staged: [PickedFile] = []
            for await file in uploadStaging.stageDocuments(urls) {
                staged.append(file)
            }
            await send(.directUploadStaged(staged, destination: destination, requested: urls.count))
        }
    }

    /// The selected rows in list order (the selection set itself is unordered).
    func selectedItems(_ state: State) -> [FileItem] {
        state.items.filter { state.selectedItemIDs.contains($0.id) }
    }
}
