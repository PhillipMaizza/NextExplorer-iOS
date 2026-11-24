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
    @ObservableState
    public struct State: Equatable, Sendable {
        public var serverURL: URL
        /// The account scope the saved listings and lists are filed under, captured when this state
        /// was created, so a response landing after an account switch is saved to the account that asked.
        let cacheScope: String
        public var directoryPath: String
        public var title: String
        public var items: IdentifiedArrayOf<FileItem> = []
        /// A file a search sent the user to: selected, scrolled to and opened once the listing holds it.
        var revealItemID: FileItem.ID?
        /// The row the Mac table scrolls into view, set when `revealItemID` lands in the listing.
        var scrollTargetID: FileItem.ID?
        public var favoritePaths: Set<String> = []
        /// A favorites answer has landed. Until then `favoritePaths` says nothing, and toggling a star
        /// would re add a folder that is already a favorite, resetting its label, icon and color.
        public var hasLoadedFavorites = false
        /// Ids of the items in this listing that are available offline (a pinned file, or a folder
        /// covered by a pinned root), so rows/cells can show an offline badge. Recomputed off the
        /// main actor when the listing loads, on appear, and when a download finishes.
        public var offlineItemIDs: Set<String> = []
        /// The subset of `offlineItemIDs` the user pinned themselves. The rest are offline only
        /// because a parent folder is pinned, so they cannot be unpinned on their own.
        public var offlinePinnedItemIDs: Set<String> = []
        /// Items waiting for the user to confirm taking them out of Available Offline.
        var offlineRemoval: OfflineRemovalRequest?
        /// Kept files handed to the system share sheet, from their copies on the device.
        var keptShare: KeptFilesShare?

        /// What the selection bar's Available Offline button does right now.
        var selectedOfflineAction: OfflineBulkAction? {
            OfflineBulkAction.resolve(
                selectedIDs: selectedItems.map(\.id),
                offlineIDs: offlineItemIDs
            )
        }

        /// The server has personal folders on (`features.personal.enabled`). Only the root screen
        /// asks, since the root volume listing never includes the account's own folder.
        public var isPersonalSpaceEnabled = false
        /// The server has a trash (any server since mid September 2026): the root offers a Trash row.
        public var isTrashAvailable = false
        var archiveExtensions: [String] = []
        /// How far the server's folder size index goes, from its last features answer (kept on disk so
        /// a pushed folder knows without asking). Folder rows show a size only while this is not `.off`.
        public var folderSizeMode: FolderSizeMode = .off
        /// The size to show for each folder in this listing, by item id. Only folders the server has
        /// counted are here, and it is empty while the feature is off.
        public var folderSizes: [FileItem.ID: Int64] = [:]
        /// Folders whose rescan was asked for and is still being read back.
        var refreshingFolderSizeIDs: Set<FileItem.ID> = []
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
        public var createdFolderIDs: Set<FileItem.ID> = []
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

        public var effectiveSearchScope: SearchScope {
            folderDepth == 0 ? .everywhere : searchScope
        }

        /// The folder a search runs from: the root everywhere, this folder otherwise.
        var searchBasePath: String {
            effectiveSearchScope == .everywhere ? "" : directoryPath
        }

        public var searchResults: IdentifiedArrayOf<SearchResultItem>?
        /// The server search for the typed term: `.loading` from the keystroke through the answer,
        /// `.failed` when it could not answer, `.idle` with no term or one too short to send.
        public var searchPhase: DataPhase = .idle
        /// The term `searchResults` are the server's answer to; `nil` while they are instant
        /// matches. An answer stays on screen while a newer term is asked, and a failure keeps it
        /// only when it answers the term that failed.
        public var searchAnsweredTerm: String?
        /// Files and folders below the search's folder known from listings saved on the device, by
        /// id: read once a search needs them (a term too short for the server, or no server to
        /// reach). `nil` until read; cleared when the search ends or its scope changes.
        public var searchSavedItems: [String: FileItem]?
        /// The ids of the results kept on this device, read off the main actor whenever the results
        /// change; they head the list as "On device". Ids no longer in the results are ignored.
        public var searchOnDeviceIDs: Set<String> = []
        /// The file type categories the search results are filtered to. Empty means "all types";
        /// otherwise a result shows only if its category is in the set. Only relevant while
        /// searching, and pruned to the categories actually present as results change.
        public var selectedSearchCategories: Set<FileCategory> = []
        /// The kinds the folder's own items are narrowed to, the same way. Empty means everything;
        /// a kind the folder no longer holds is ignored rather than leaving an empty list.
        public var selectedFolderCategories: Set<FileCategory> = []
        /// How many results the search asks for; Show more steps it through
        /// `FilesClient.searchLimitSteps`, and a new query or scope starts over.
        public var searchLimit = FilesClient.searchLimitSteps[0]
        /// Why the latest server answer may be short of the whole truth, said rather than left
        /// to look like everything.
        public var searchShortfall: SearchShortfall?
        public var sortOption: SortOption = .name
        public var sortDirection: SortDirection = .ascending
        /// Read live from the same in memory key `SettingsFeature` writes, so toggling
        /// "Show Hidden Files" is reflected here immediately, even in an already open folder,
        /// with no manual refresh needed.
        @Shared(.inMemory("userPreferences")) public var preferences = UserPreferences()
        /// App wide "Copy" staging, shared under `FileClipboard.sharedKey` so the Paste
        /// action follows the user across every folder. `nil` when nothing is staged. Only
        /// ever holds copies: "Move" goes through `destinationPicker`, not the clipboard.
        @Shared(.inMemory(FileClipboard.sharedKey)) public var clipboard: FileClipboard?
        /// App wide ⌘Z history of reversible file operations (`FileUndoEntry`).
        @Shared(.inMemory(FileUndoEntry.sharedKey)) public var undoStack: [FileUndoEntry] = []
        /// Operations ⌘Z reversed, for ⇧⌘Z to do again (`FileUndoEntry.isRedoable` ones only).
        @Shared(.inMemory(FileUndoEntry.redoSharedKey)) public var redoStack: [FileUndoEntry] = []
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
        /// The params to rerun when the user taps "Retry" on a failed transfer's toast. The
        /// staged clipboard is never emptied while this is non nil, so a retry always has
        /// something to act on.
        public var pendingTransferRetry: TransferRetry?
        /// Items a copy or move into this folder created that the listing has not shown yet,
        /// and how many more refetches may wait for them (`Constants.arrivalRechecks`).
        public var awaitedArrivalIDs: Set<FileItem.ID> = []
        public var arrivalChecksLeft = 0
        /// Non nil while a transfer is waiting on the user's answer to a name collision prompt.
        public var transferConflict: TransferConflict?
        /// Set when an item is staged with "Copy"; `BrowseContentView` turns it into a brief
        /// "<name> copied" toast.
        public var clipboardStagedMessage: String?
        /// Item currently being renamed via the native rename alert. The in progress text
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
        /// Share link fallout of the pending delete, single or bulk: only one confirmation is
        /// ever on screen at once, so one field covers both. Filled in by `delete-impact` while
        /// the alert is up; reset to `.idle` when the alert is dismissed.
        public var deleteImpactCheck: DeleteImpactCheck = .idle
        public var isPerformingFileAction = false
        public var fileActionErrorMessage: String?
        /// Whether the list/grid is in multiselect mode: toggled from the toolbar, not tied
        /// to any particular item. `selectedItemIDs` is always cleared when this flips off.
        public var isSelecting = false
        public var selectedItemIDs: Set<FileItem.ID> = []
        public var isBulkActionInFlight = false
        /// How far the running bulk delete is (0 to 1); nil when none runs. Drives the progress bar.
        public var bulkDeleteProgress: Double?
        /// How far the running copy or move is (0 to 1); nil when none runs.
        public var transferProgress: Double?
        public var bulkDeletePhase: ConfirmPhase = .idle
        /// Items the trash refused during the last delete, still on disk. Non empty puts up the
        /// prompt that offers to delete them for good.
        public var keptDeletes: [KeptDelete] = []
        /// Set after a delete sent anything to the trash; becomes a toast that opens the trash.
        public var trashNotice: MovedToTrashNotice?
        /// Drives a persistent progress toast: `nil` when no extract/compress/download is
        /// running. Rename/delete don't set this: they're fast enough, and already have their
        /// own alert driven confirm flow, that a progress indicator would just flicker.
        public var fileActionProgressMessage: String?
        /// Set when a download is queued from a preview cover, which hides the app level progress
        /// bar; `BrowseContentView` turns it into a toast with an Open action. Never cleared by the
        /// reducer, only overwritten by the next one.
        public var downloadSuccessMessage: String?
        /// Item the "Get Info" sheet is showing, alongside its fetched metadata (or the
        /// still loading/error state while `GET /api/metadata/*` is in flight).
        public var infoItem: FileItem?
        public var infoMetadata: FileMetadata?
        /// Server disk usage for `infoItem` when it's a directory and the endpoint returned
        /// real figures: drives the Get Info sheet's "Server disk" section.
        public var infoUsage: StorageUsage?
        /// The `GET /api/metadata/*` load lifecycle for the Get Info sheet; `infoErrorMessage` is
        /// derived from it.
        public var infoPhase: DataPhase = .idle
        public var isInfoShowingSelection = false

        public var isInspectorOpen: Bool {
            infoItem != nil || isInfoShowingSelection
        }

        public var infoErrorMessage: String? {
            infoPhase.errorMessage
        }

        /// Item being downloaded for the QuickLook viewer (tapping a file), alongside the
        /// local temp file `previewFile` produces once `GET /api/preview` finishes. Only
        /// used for PDFs: images/RAW load themselves per page in the gallery view, and
        /// video/audio stream directly, neither going through this at all.
        public var previewItem: FileItem?
        /// The open file came from a search hit, not this folder's listing: it can live in another
        /// folder or be hidden here, so its gallery holds it alone.
        var isPreviewOutsideListing = false
        /// Pushed from the Offline tab: the screen offers only what works on files kept on the device
        /// (copy, share, save, remove from offline), so its access is narrowed when it lands.
        public var isKeptOffline = false
        /// The listing comes from the device (an Offline tab screen, or a saved copy shown with no
        /// network): only actions on kept files are offered, done from those files, not the server.
        var shouldShowDeviceContent: Bool {
            isKeptOffline || dataSource != .live
        }

        public var previewFileURL: URL?
        /// The `GET /api/preview` download lifecycle; `previewErrorMessage` is derived from it.
        public var previewPhase: DataPhase = .idle

        public var previewErrorMessage: String? {
            previewPhase.errorMessage
        }

        /// Text content for `previewItem` when it's neither previewable via download nor
        /// streamable (anything `GET /api/preview` 415s on): fetched/saved via the real
        /// `/api/editor` endpoint, the server's actual text view+edit path.
        public var textContent: String?
        /// The gallery handed a text file to the editor (its Edit button): the cover shows the editor
        /// for `previewItem` until it closes back to the gallery.
        public var isPreviewEditing = false
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
        public var isTextSaveConflictPresented: Bool {
            textSaveConflict?.isAlertPresented ?? false
        }

        /// The text a save could not write because the file changed on the server, and whether the
        /// alert asking what to do is showing (dismissing it keeps the conflict pending).
        struct TextSaveConflict: Equatable, Sendable {
            var pendingText: String
            var isAlertPresented = true
        }

        public var textSaveError: String?
        public var isLoadingTextContent: Bool {
            textPhase == .loading
        }

        /// A load failure (from `textPhase`) or a save failure (`textSaveError`): they never
        /// coexist, so one accessor drives the editor's error surface as before.
        public var textEditorErrorMessage: String? {
            textPhase.errorMessage ?? textSaveError
        }

        /// A term is typed; spaces alone are not one.
        public var isSearching: Bool {
            !SearchTerm(searchQuery).isEmpty
        }

        /// A server search for the typed term is waiting out the debounce or running, whatever
        /// is on screen meanwhile.
        public var isSearchPending: Bool {
            isSearching && searchPhase == .loading
        }

        /// The search could not reach the server: matches from saved listings stand in.
        public var isSearchOffline: Bool {
            searchPhase == .failed(FilesClientError.offline.userMessage)
        }

        /// Saved listings may answer only where the server cannot: a term it never sees, or no
        /// server to reach. Never over a real server error.
        var mayAnswerFromSavedListings: Bool {
            SearchTerm(searchQuery).isTooShort || isSearchOffline
        }

        /// The results on screen are a server answer worth keeping while a newer term is asked.
        var isShowingSearchAnswer: Bool {
            searchAnsweredTerm != nil && searchResults?.isEmpty == false
        }

        /// The search could not answer the typed term: said under the results with Retry.
        public var searchFailureMessage: String? {
            isSearching ? searchPhase.errorMessage : nil
        }

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
            IdentifiedArray(
                BrowseFeature.sorted(filteredItems, by: sortOption, direction: sortDirection, folderSizes: folderSizes),
                id: \.id,
                uniquingIDsWith: { first, _ in first }
            )
        }

        /// `items` with hidden entries dropped unless the preference is on, in listing order.
        var visibleItems: [FileItem] {
            preferences.shouldShowHiddenFiles ? items.elements : items.elements.filter { !isHiddenFileName($0.name) }
        }

        /// `visibleItems` narrowed to the picked kinds the folder still holds.
        var filteredItems: [FileItem] {
            let active = activeFolderCategories
            guard !active.isEmpty else { return visibleItems }
            return visibleItems.filter { active.contains(Self.category(of: $0)) }
        }

        private var activeFolderCategories: Set<FileCategory> {
            guard !selectedFolderCategories.isEmpty else { return [] }
            return selectedFolderCategories.intersection(availableFolderCategories)
        }

        /// The kinds in this folder, in display order, offered as filter chips. A folder holding
        /// only one kind (only folders, say) or nothing has nothing to narrow, so it offers none.
        public var availableFolderCategories: [FileCategory] {
            let present = Set(visibleItems.map(Self.category(of:)))
            guard present.count > 1 else { return [] }
            return FileCategory.allCases.filter(present.contains)
        }

        static func category(of item: FileItem) -> FileCategory {
            FileCategory.of(kind: item.kind, isDirectory: item.isDirectory)
        }

        /// Whether `displayedItems` would be non empty, and how many entries it would hold,
        /// without paying `displayedItems`' sort. Used for the toolbar/selection/empty
        /// state checks that only need emptiness or a count, not the ordered list.
        public var hasDisplayedItems: Bool {
            guard selectedFolderCategories.isEmpty else { return !filteredItems.isEmpty }
            return preferences.shouldShowHiddenFiles ? !items.isEmpty : items.contains { !isHiddenFileName($0.name) }
        }

        public var displayedItemCount: Int {
            guard selectedFolderCategories.isEmpty else { return filteredItems.count }
            return preferences.shouldShowHiddenFiles
                ? items.count
                : items.reduce(0) { isHiddenFileName($1.name) ? $0 : $0 + 1 }
        }

        /// `searchResults`, with hidden entries dropped unless the preference is on, then narrowed
        /// to `selectedSearchCategories` when the type filter is active.
        public var displayedSearchResults: IdentifiedArrayOf<SearchResultItem>? {
            guard let searchResults else { return nil }
            let visible = preferences.shouldShowHiddenFiles
                ? searchResults
                : searchResults.filter { !isHiddenFileName($0.name) }
            guard !selectedSearchCategories.isEmpty else { return visible }
            return visible.filter { selectedSearchCategories.contains(Self.category(of: $0)) }
        }

        /// `displayedSearchResults` split into what is on this device and what is only on the server.
        public var searchResultSections: SearchResultSections {
            SearchResultSections(displayedSearchResults.map(Array.init) ?? [], onDeviceIDs: searchOnDeviceIDs)
        }

        /// The categories actually present in the current (hidden filtered) results, in display
        /// order: the rows the filter sheet offers. Independent of the current selection, so
        /// toggling a category off doesn't make it vanish from the sheet.
        public var availableSearchCategories: [FileCategory] {
            FileCategory.present(in: visibleSearchResults)
        }

        public var searchCategoryCounts: [FileCategory: Int] {
            FileCategory.counts(in: visibleSearchResults)
        }

        private var visibleSearchResults: [SearchResultItem] {
            guard let searchResults else { return [] }
            return preferences.shouldShowHiddenFiles
                ? searchResults.elements
                : searchResults.filter { !isHiddenFileName($0.name) }.elements
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
            @Dependency(\.jsonCacheStore) var jsonCacheStore
            folderSizeMode = ListCache.load(
                jsonCacheStore, BrowseFeature.folderSizeModeCacheNamespace, serverURL: serverURL, scope: cacheScope,
                as: FolderSizeMode.self
            )?.value ?? .off
            archiveExtensions = ListCache.load(
                jsonCacheStore, BrowseFeature.archiveExtensionsCacheNamespace, serverURL: serverURL, scope: cacheScope,
                as: [String].self
            )?.value ?? []
            if directoryPath.isEmpty {
                isPersonalSpaceEnabled = ListCache.load(
                    jsonCacheStore, BrowseFeature.personalSpaceCacheNamespace, serverURL: serverURL, scope: cacheScope,
                    as: Bool.self
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
        /// The results changed, or what is kept offline did: find which results are on the device.
        case computeSearchOnDevice
        case searchOnDeviceComputed(Set<String>)
        case offlineAvailabilityComputed(all: Set<String>, pinned: Set<String>)
        /// Pin the item for offline use, or unpin it when the user pinned it already. An item that is
        /// offline only through a pinned parent folder does nothing.
        case offlineToggleTapped(FileItem)
        case offlineRemovalConfirmed
        case offlineRemovalCancelled
        /// A screen above this one took `paths` off the device: an Offline tab screen stops listing them.
        case keptItemsRemoved(paths: [String])
        case itemsResponse(Result<BrowseResult, FilesClientError>)
        case favoritesResponse([Favorite])
        /// The saved listing read off the main actor for an offline failure, `nil` when none is stored.
        case offlineListingResolved(CachedDirectory?, FilesClientError)
        /// The saved listing read off the main actor to paint a first load, `nil` when none is stored.
        case cachedListingPainted(CachedDirectory)
        /// The listing kept with a pinned folder, read for an Offline tab screen; `nil` when none is kept.
        case keptListingResolved(CachedDirectory?)
        case serverFeaturesResponse(ServerFeatures)
        case folderSizesResponse(attempt: Int, [FileItem.ID: FolderSize])
        case folderSizesDue(attempt: Int)
        case folderSizeRefreshTapped(FileItem.ID)
        case folderSizeRefreshResponse(FileItem.ID, Result<FolderSize, FilesClientError>)
        case folderSizesUnavailable
        case personalSpaceTapped
        case trashTapped
        case rowTapped(FileItem)
        case searchQueryChanged(String)
        case searchScopeChanged(SearchScope)
        case searchCategoryToggled(FileCategory)
        case searchFilterCleared
        case folderCategoryToggled(FileCategory)
        case folderFilterCleared
        case searchResultTapped(SearchResultItem)
        case searchShowMoreTapped
        /// Retry under a search that could not answer: asks again at once.
        case searchRetryTapped
        /// The listings saved below the search's folder, read off the main actor.
        case searchSavedItemsLoaded([FileItem])
        case searchResultsResponse(Result<SearchPage, FilesClientError>, term: String)
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
        /// "View in Shared" tapped on the created share link sheet while a preview cover is up.
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
        /// Confirm came from a full screen preview: dismiss the cover, then delete after a
        /// short settle so the list row animates out where the user can see it.
        case deleteConfirmedFromPreview
        /// Delete Permanently on a confirmation that would otherwise move the item to the trash.
        case deletePermanentlyConfirmed(fromPreview: Bool)
        /// The prompt about items the trash refused: delete them for good, or leave them.
        case keptDeletePermanentlyConfirmed
        case keptDeleteDismissed
        case deleteImpactResponse(Result<DeleteImpact, FilesClientError>)
        case deleteResponse(Result<DeleteResult, FilesClientError>)
        case extractTapped(FileItem, entryPaths: [String]? = nil)
        case extractResponse(Result<[FileItem], FilesClientError>)
        case compressTapped(FileItem)
        case compressResponse(Result<FileItem, FilesClientError>)
        case downloadTapped(FileItem)
        /// Files staged without the review sheet: a Mac drop or pick, or files shared from another
        /// app when Settings says to upload them to the default folder without asking.
        case directUploadStaged([PickedFile], destination: String, requested: Int)
        #if os(macOS)
            /// Files opened from Finder name no folder, so they always go through the review sheet.
            case reviewUpload(UploadReviewFeature.PickSource)
        #endif
        case searchResultEnclosingFolderTapped(SearchResultItem)
        /// Files dropped on a folder row (Finder on a Mac, the Files app on an iPad).
        case filesDroppedOnFolder([URL], folder: FileItem)
        /// Rows dragged in from another Browse window, moved into `destination`.
        case itemsDroppedFromOtherWindow([FileItem], destination: String)
        case selectModeToggled
        case itemSelectionToggled(FileItem.ID)
        /// A finger slide across the listing in select mode picked this selection.
        case selectionSwept(Set<FileItem.ID>)
        case selectAllTapped
        case deselectAllTapped
        case bulkDeleteTapped
        case bulkDeleteCancelled
        case bulkDeleteConfirmed
        case bulkDeletePermanentlyConfirmed
        case bulkDeleteProgressed(Double)
        case bulkDeleteCancelTapped
        case bulkDeleteResponse(Result<DeleteResult, FilesClientError>)
        case bulkFavoriteTapped
        case bulkFavoriteResponse(BulkFavoriteToggleResult)
        case bulkDownloadTapped
        /// Share on device content: the kept copies of these files go to the system share sheet.
        case keptShareTapped([FileItem])
        case keptShareResolved([URL])
        case keptShareDismissed
        /// Pins every selected item that is not offline yet; when all of them are, unpins the ones
        /// the user pinned. Items offline only through a parent folder are left alone.
        case bulkOfflineTapped
        case beginUpload(UploadReviewFeature.PickSource)
        /// Files another app shared in: opens the upload review here, or adds them to one already open.
        case receiveSharedFiles([URL])
        /// Shared files that go through the review sheet, starting in Settings' default folder.
        case reviewSharedFiles([URL], startingAt: String?)
        case uploadReview(PresentationAction<UploadReviewFeature.Action>)
        case copyTapped(FileItem)
        case moveTapped(FileItem)
        case copyToTapped(FileItem)
        case copySelectionToTapped
        case showInFolderTapped(FileItem)
        case bulkCopyTapped
        case bulkMoveTapped
        case clipboardCleared
        case pasteTapped(keepItemsAfterCopy: Bool)
        /// Keyboard driven actions for the Mac file table, acting on whatever rows are selected
        /// there (tracked in `selectedItemIDs` without entering select mode).
        case tableSelectionChanged(Set<FileItem.ID>)
        /// The listing now holds the file a search sent the user to: select it, scroll to it, open it.
        case revealItemShown(FileItem.ID)
        case copySelectionTapped
        case cutSelectionTapped
        /// Copies the selection into its own folder; the server names the copies "Name (2)".
        case duplicateSelectionTapped
        /// Reverses the last recorded file operation (⌘Z).
        case undoTapped
        case undoResponse(Result<FileUndoEntry, FilesClientError>)
        case redoTapped
        case redoResponse(Result<FileUndoEntry, FilesClientError>)
        case deleteSelectionTapped
        case renameSelectionTapped
        case infoSelectionTapped
        /// Mac: rows dragged onto a folder row in the same listing move into it.
        case itemsDroppedOnFolder(ids: [FileItem.ID], folder: FileItem)
        case retryTransferTapped
        case transferConflictCheckResponse(Result<[FileItem], FilesClientError>)
        case transferConflictResolved(TransferConflictChoice?)
        case transferProgressed(Double)
        case transferCancelTapped
        case transferResponse(Result<TransferOutcome, FilesClientError>)
        case destinationPicker(PresentationAction<DestinationPickerFeature.Action>)
        case infoTapped(FileItem)
        case permissionsTapped(FileItem)
        case permissions(PresentationAction<PermissionsFeature.Action>)
        case infoDismissed
        case infoMetadataResponse(Result<FileMetadata, FilesClientError>)
        case infoUsageResponse(Result<StorageUsage, FilesClientError>)
        case previewDismissed
        case previewEditTapped(FileItem)
        case previewEditorClosed
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
            /// folder: bubbled up to `MainTabFeature`'s app wide upload queue.
            case uploadRequested([PendingUpload])
            /// Items handed to `MainTabFeature`'s app wide download queue.
            case downloadRequested([FileItem])
            /// Items pinned for offline use, handed to the offline engine in `MainTabFeature`.
            case offlinePinRequested([FileItem])
            case offlineUnpinRequested(path: String)
            /// Mac: items placed in Finder through the save panel, for the same queue.
            case saveRequested([DownloadSaveRequest])
            /// A copy/move just changed what's on the server. `BrowseTabFeature` refetches
            /// the whole live navigation stack so both the source and destination listings
            /// reflect the new state.
            case directoryContentsChanged
            /// The "Open" button on the download success toast: switches to the Downloads
            /// tab so the user can see where the file landed.
            case openDownloadsTapped
            /// "Open Trash" on the toast after a delete moved items to the trash.
            case openTrashTapped
            /// "View in Shared" on the created share link sheet: switches to the Shared tab.
            case goToSharedTab
            /// An Offline tab screen took its own folder off the device with its last items: the
            /// parent closes it and drops `removedPaths` from the screens below.
            case keptFolderEmptied(removedPaths: [String])
        }
    }

    @Dependency(\.filesClient) var filesClient
    @Dependency(\.directoryCacheStore) var directoryCacheStore
    @Dependency(\.jsonCacheStore) var jsonCacheStore
    static let personalSpaceCacheNamespace = "personalSpace"
    static let folderSizeModeCacheNamespace = "folderSizeMode"
    static let archiveExtensionsCacheNamespace = "archiveExtensions"
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date) var date
    @Dependency(\.uploadStaging) var uploadStaging
    @Dependency(\.uploadDefaults) var uploadDefaults
    @Dependency(\.openURL) var openURL
    @Dependency(\.offlineFileStore) var offlineFileStore
    @Dependency(\.connectivity) var connectivity
    @Dependency(\.saveLocationPicker) var saveLocationPicker
    /// Internal (not private) so the effect helpers extracted into `BrowseFeature+*.swift`
    /// can reference these cancel ids across files.
    enum CancelID: Hashable {
        case search, searchSavedItems, bulkDelete, transfer, googleDocsPointer, deleteImpact, load, preview, info,
             previewDeferredAction, folderSizes
        case prefetchChildren, prefetchFavorites, offlineAvailability, searchOnDevice, arrivalRecheck, newFileExtensions
        /// Per path, so spamming one item's star collapses to a single in flight toggle
        /// (the latest tap wins) while other items toggle independently.
        case favorite(String)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        CombineReducers {
            Reduce(reduceListing)
            Reduce(reduceSearch)
            Reduce(reduceItemActions)
            Reduce(reduceSelection)
            Reduce(reduceMoves)
            Reduce(reduceInfo)
            Reduce(reduceFolderSizes)
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
                if state.isInfoShowingSelection {
                    return settleSelectionInfo(&state)
                }
                guard let shown = state.infoItem, shown.id != state.directoryPath, items[id: shown.id] == nil
                else { return .none }
                return closeInfo(&state)
            }
        }
        .onChange(of: \.selectedItemIDs) { _, _ in
            Reduce { state, _ in
                settleSelectionInfo(&state)
            }
        }
    }

    /// The access a screen acts on: the server's, narrowed on device content (an Offline tab screen or
    /// a saved copy shown with no network) to what works on kept files, so writes, deletes and uploads
    /// are not offered there.
    static func shownAccess(_ access: FileAccess, isNarrowed: Bool) -> FileAccess {
        guard isNarrowed else { return access }
        return FileAccess(
            canRead: access.canRead,
            canWrite: false,
            canUpload: false,
            canDelete: false,
            canShare: access.canShare,
            canDownload: access.canDownload,
            canCreateFolder: false,
            canCreateFile: false
        )
    }

    /// The confirmation for taking `items` off the device, under this screen's account. On an Offline
    /// tab screen, picking everything it still shows takes the folder itself off instead: a kept folder
    /// with nothing in it is not worth keeping, and the screen goes back once it is confirmed.
    func offlineRemoval(of items: [FileItem], state: State) -> OfflineRemovalRequest? {
        // The manifest is read once, not once per picked item.
        let roots = offlineFileStore.pinned(to: state.cacheScope).pinnedRoots()
        let coveringRoot: (String) -> String? = { roots.coveringRoot(of: $0)?.path }
        guard let request = OfflineRemovalRequest.removing(
            items.map { (path: $0.id, name: $0.name) },
            pinnedPaths: state.offlinePinnedItemIDs,
            coveringRoot: coveringRoot
        ) else { return nil }
        guard state.isKeptOffline, !state.directoryPath.isEmpty,
              state.visibleItems.allSatisfy({ Self.isTakenOff($0.id, by: request.paths) }),
              let folder = OfflineRemovalRequest.removing(
                  [(path: state.directoryPath, name: state.title)],
                  pinnedPaths: Set(roots.map(\.path)),
                  coveringRoot: coveringRoot
              )
        else { return request }
        return OfflineRemovalRequest(paths: folder.paths, names: request.names, emptiedFolderName: state.title)
    }

    /// Whether taking `paths` off the device takes `id` with it: the item itself or a folder above it.
    static func isTakenOff(_ id: String, by paths: [String]) -> Bool {
        paths.contains { id == $0 || id.hasPrefix($0 + "/") }
    }

    /// A screen listing what is on the device stops showing what just came off it.
    static func dropTakenOff(_ paths: [String], from state: inout State) {
        let stillKept = state.offlineItemIDs
        let countBefore = state.items.count
        state.items.removeAll { !stillKept.contains($0.id) && isTakenOff($0.id, by: paths) }
        if state.items.count != countBefore {
            state.selectedItemIDs.formIntersection(state.items.ids)
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
    /// comparator to get `>` breaks `sorted`'s strict weak ordering requirement exactly when
    /// two elements compare equal, since both `(a, b)` and `(b, a)` would otherwise flip true.
    static func sorted(
        _ items: some Collection<FileItem>,
        by option: SortOption,
        direction: SortDirection,
        folderSizes: [FileItem.ID: Int64] = [:]
    ) -> [FileItem] {
        func size(_ item: FileItem) -> Int64 {
            item.isDirectory ? folderSizes[item.id] ?? 0 : item.size
        }
        return items.sorted { lhs, rhs in
            guard lhs.isDirectory == rhs.isDirectory else { return lhs.isDirectory }
            let isAscending: Bool
            switch option {
            case .name:
                let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                guard order != .orderedSame else { return false }
                isAscending = order == .orderedAscending
            case .size:
                guard size(lhs) != size(rhs) else { return false }
                isAscending = size(lhs) < size(rhs)
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
    func openUploadReview(
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
}
