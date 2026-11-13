import ComposableArchitecture
import CoreModels
import FilesClient
import FolderPickerFeature
import Foundation
import Localization

@Reducer
public struct FavoritesFeature {
    @ObservableState
    public struct State: Equatable {
        public var serverURL: URL
        /// The account scope the saved list is filed under, captured when this state was created.
        let cacheScope: String
        public var favorites: IdentifiedArrayOf<Favorite> = []
        /// The load lifecycle: `.idle` → `.loading` → `.loaded` / `.failed`. Drives the
        /// skeleton (`.loading` with no data) and the full screen error (`.failed`).
        public var phase: DataPhase = .idle
        /// A failed remove/reorder, or a refresh failure over an already populated list,
        /// surfaced as a toast rather than the full screen `phase.errorMessage`.
        public var actionErrorMessage: String?

        /// The first load's failure text, if it's still the current state.
        public var errorMessage: String? {
            phase.errorMessage
        }

        /// `.cached` while the list on screen is an offline copy; `.live` once a fetch lands.
        public var dataSource: CachedListSource = .live
        /// Ids of favorites whose folder is available offline, i.e. it is a pinned root or sits
        /// under one (so a downloaded subfolder favorite is flagged too). Drives the download
        /// badge on the row, mirroring `BrowseFeature.offlineItemIDs`.
        public var offlineFavoriteIDs: Set<Favorite.ID> = []
        /// The favorites whose folder is itself pinned, the only ones the toggle can unpin.
        public var offlinePinnedFavoriteIDs: Set<Favorite.ID> = []
        var offlineRemoval: OfflineRemovalRequest?

        /// What the selection bar's Available Offline button does right now.
        var selectedOfflineAction: OfflineBulkAction? {
            OfflineBulkAction.resolve(
                selectedIDs: favorites.filter { selectedFavoriteIDs.contains($0.id) }.map(\.id),
                offlineIDs: offlineFavoriteIDs,
                pinnedIDs: offlinePinnedFavoriteIDs
            )
        }

        public var searchQuery = ""
        /// Recursive file search across every favorited folder's subtree, run while `searchQuery`
        /// is non-empty. `nil` until the first search of a session; the fan out merges one backend
        /// search per favorite. Distinct from `displayedFavorites`, which only ever name filters the
        /// favorite folders themselves.
        public var fileSearchResults: IdentifiedArrayOf<SearchResultItem>?
        /// The ids of the results kept on this device; they head the list as "On device".
        public var searchOnDeviceIDs: Set<String> = []
        /// Lifecycle of the file search above: `.loading` on first run with no prior results,
        /// `.loaded` once merged results land, `.failed` when every favorite's search errored.
        public var searchPhase: DataPhase = .idle
        @Presents public var editSheet: FavoriteEditFeature.State?
        /// A `BrowseFeature` scoped to a search hit's parent folder, presented as a full screen
        /// preview cover over the results: so tapping a file result opens it directly (no visible
        /// folder navigation) and dismissing returns straight to the results. Reuses Browse's whole
        /// preview subsystem rather than duplicating it.
        @Presents public var previewHost: BrowseFeature.State?
        public var isSelecting = false
        public var selectedFavoriteIDs: Set<Favorite.ID> = []
        public var bulkRemoveConfirmationIsPresented = false
        /// Browsing into a favorited folder pushes here, same shape as `BrowseTabFeature`:
        /// this keeps navigation inside the Favorites tab rather than jumping to Browse.
        public var path = StackState<BrowseFeature.State>()
        /// Folders left by going back, nearest last, so Forward (⌘]) can reopen them. Opening
        /// anything else clears it, as in Finder.
        public var forwardStack: [BrowseFeature.State] = []

        public init(serverURL: URL) {
            self.serverURL = serverURL
            @Dependency(\.cacheScope) var cacheScopeSource
            cacheScope = cacheScopeSource.current()
            // Paint the last saved copy synchronously at construction, so the very first frame of
            // the Favorites tab already shows the cached list instead of a skeleton. Without this
            // the cache is only painted from `onAppear` (a `.task`, so it runs after the first
            // render) and a hung fetch to an unreachable server (e.g. a LAN address off the LAN)
            // leaves the tab blank the whole time it times out. `phase` stays `.idle` so
            // `onAppear` still refetches (stale-while-revalidate); `dataSource` stays `.live` so an
            // online refetch doesn't flash a "saved copy" banner.
            @Dependency(\.jsonCacheStore) var jsonCacheStore
            if let cached = ListCache.load(
                jsonCacheStore,
                FavoritesFeature.cacheNamespace,
                serverURL: serverURL,
                scope: cacheScope,
                as: [Favorite].self
            ) {
                favorites = IdentifiedArray(
                    cached.value.sorted { $0.position < $1.position }, id: \.id, uniquingIDsWith: { first, _ in first }
                )
            }
        }

        /// Favorites are shown in the user's own order (`position`, drag to reorder): the
        /// only transform here is the search filter. `favorites` is kept in `position` order
        /// by `load` and every reorder response.
        public var displayedFavorites: [Favorite] {
            let term = SearchTerm(searchQuery)
            guard !term.isEmpty else { return Array(favorites) }
            return favorites.filter { term.matches($0.displayName) }
        }

        /// Drag reorder only makes sense over the full, unfiltered list.
        public var canReorder: Bool {
            searchQuery.isEmpty && !isSelecting
        }

        /// True once the term is long enough for the server, so the view swaps the favorites list
        /// for file results. A shorter term filters the favorites by name instead.
        public var isSearching: Bool {
            SearchTerm(searchQuery).isSearchable
        }

        /// Typed, but too short for the server: the favorites are filtered by name and a hint
        /// says how many characters the file search needs.
        public var isSearchTermTooShort: Bool {
            SearchTerm(searchQuery).isTooShort
        }

        /// A file search for the typed term is waiting or running, whatever is on screen.
        public var isSearchPending: Bool {
            isSearching && searchPhase == .loading
        }

        /// A name filter left none of the favorites.
        public var hasNoMatchingFavorites: Bool {
            isSearchTermTooShort && displayedFavorites.isEmpty
        }

        /// File search results with hidden entries dropped unless the preference is on.
        /// `displayedSearchResults` split into what is on this device and what is only on the server.
        public var searchResultSections: SearchResultSections {
            SearchResultSections(displayedSearchResults, onDeviceIDs: searchOnDeviceIDs)
        }

        public var displayedSearchResults: [SearchResultItem] {
            guard let fileSearchResults else { return [] }
            return fileSearchResults.filter { showHiddenFiles || !isHiddenFileName($0.name) }
        }

        /// Mirrors the browse preference so a hidden file inside a favorite doesn't surface in
        /// results unless the user opted in. Kept here so the reducer test can flip it.
        public var showHiddenFiles = false
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case refreshButtonTapped
        case favoritesResponse(Result<[Favorite], FilesClientError>)
        /// The saved list read off the main actor after an offline failure, `nil` when none is stored.
        case offlineFavoritesResolved(cached: [Favorite]?, fetchedAt: Date?, error: FilesClientError)
        /// The saved list read off the main actor to paint a first load.
        case cachedFavoritesPainted([Favorite])
        /// Recompute which favorites are available offline (a pinned root, or under one).
        case computeOfflineAvailability
        case offlineAvailabilityComputed(all: Set<Favorite.ID>, pinned: Set<Favorite.ID>)
        /// Pins the favorite's folder for offline use, or unpins it when the user pinned it.
        case offlineToggleTapped(Favorite)
        /// Pins the selected favorites' folders, or, when they all are offline, asks to unpin them.
        case bulkOfflineTapped
        case offlineRemovalConfirmed
        case offlineRemovalCancelled
        case rowTapped(Favorite)
        case removeTapped(Favorite)
        case removeResponse(Favorite.ID, Result<Bool, FilesClientError>)
        case editTapped(Favorite)
        case editSheet(PresentationAction<FavoriteEditFeature.Action>)
        case favoritesMoved(IndexSet, Int)
        case reorderResponse(Result<[Favorite], FilesClientError>)
        case searchQueryChanged(String)
        case fileSearchResponse(Result<[SearchResultItem], FilesClientError>)
        case searchRetryTapped
        /// The results changed, or what is kept offline did: find which results are on the device.
        case computeSearchOnDevice
        case searchOnDeviceComputed(Set<String>)
        /// "View in Shared" after creating a link from a search result's preview.
        case viewSharesFromPreviewTapped
        case searchResultTapped(SearchResultItem)
        /// A search result's Show in Enclosing Folder: pushes the folder it lives in, keeping the
        /// search under it to come back to.
        case searchResultEnclosingFolderTapped(SearchResultItem)
        case previewHost(PresentationAction<BrowseFeature.Action>)
        case selectModeToggled
        case itemSelectionToggled(Favorite.ID)
        case selectAllTapped
        case deselectAllTapped
        case bulkRemoveTapped
        case bulkRemoveCancelled
        case bulkRemoveConfirmed
        case bulkRemoveResponse([String])
        case path(StackActionOf<BrowseFeature>)
        /// Mac ⌘[: leave the visible folder for the screen under it.
        case goBack
        /// Mac ⌘↑: open the folder that contains the visible one, back to the list from a
        /// favorite's own folder.
        case goToEnclosingFolder
        /// Mac ⌘]: reopen the folder last left by going back.
        case goForward
        case navigateToDirectory(path: String, title: String)
        /// Re-fetches every pushed subfolder currently on the live navigation stack: sent
        /// when the app becomes active again after being backgrounded.
        case syncPathStack
        /// Refetches only the pushed screens whose `directoryPath` equals `path`. Sent after
        /// an upload finishes so just the affected folder reloads.
        case refreshDirectory(path: String)
        /// A download landed: recompute the "available offline" badges on pushed folders.
        case offlineAvailabilityChanged
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case favoritesChanged
            case openDownloadsTapped
            case goToSharedTab
            case uploadRequested([PendingUpload])
            case downloadRequested([FileItem])
            case offlinePinRequested([FileItem])
            case offlineUnpinRequested(path: String)
            case saveRequested([DownloadSaveRequest])
        }
    }

    @Dependency(\.filesClient) var filesClient
    @Dependency(\.jsonCacheStore) var jsonCacheStore
    @Dependency(\.offlineFileStore) var offlineFileStore
    @Dependency(\.directoryCacheStore) var directoryCacheStore
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date) var date

    /// Cache namespace for this tab's saved offline copy.
    static let cacheNamespace = "favorites"

    private enum CancelID: Hashable { case reorder, load, remove(Favorite.ID), search, offlineAvailability,
                                           searchOnDevice
    }

    private enum Constants {
        static let searchLimit = 100
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .goBack:
                state.goBack()
                return .none

            case .goToEnclosingFolder:
                state.goToEnclosingFolder(serverURL: state.serverURL, isFirstScreenTop: true)
                return .none

            case .goForward:
                state.goForward()
                return .none

            case let .path(.popFrom(id)):
                state.recordPop(from: id)
                return .none

            case .onAppear:
                // Always refresh the offline badges (cheap disk read) so the cached first-frame
                // favorites are flagged even when the list itself needn't reload.
                let availability = computeOfflineAvailability(&state)
                guard state.phase.shouldLoadOnAppear else { return availability }
                return .merge(load(&state), availability)

            case .refreshButtonTapped:
                return .merge(load(&state), refreshSearch(&state))

            case .computeOfflineAvailability:
                return computeOfflineAvailability(&state)

            case let .offlineAvailabilityComputed(all, pinned):
                state.offlineFavoriteIDs = all
                state.offlinePinnedFavoriteIDs = pinned
                return .none

            case .offlineRemovalCancelled:
                state.offlineRemoval = nil
                return .none

            case .offlineRemovalConfirmed:
                guard let request = state.offlineRemoval else { return .none }
                state.offlineRemoval = nil
                let removed = state.favorites.filter { request.paths.contains($0.path) }.map(\.id)
                state.offlineFavoriteIDs.subtract(removed)
                state.offlinePinnedFavoriteIDs.subtract(removed)
                return .merge(request.paths.map { .send(.delegate(.offlineUnpinRequested(path: $0))) })

            case .bulkOfflineTapped:
                let selected = state.favorites.filter { state.selectedFavoriteIDs.contains($0.id) }
                guard !selected.isEmpty else { return .none }
                state.isSelecting = false
                state.selectedFavoriteIDs = []
                let toPin = selected.filter { !state.offlineFavoriteIDs.contains($0.id) }
                if !toPin.isEmpty {
                    state.offlineFavoriteIDs.formUnion(toPin.map(\.id))
                    state.offlinePinnedFavoriteIDs.formUnion(toPin.map(\.id))
                    return .send(.delegate(.offlinePinRequested(toPin.map(\.folderItem))))
                }
                let toUnpin = selected.filter { state.offlinePinnedFavoriteIDs.contains($0.id) }
                guard !toUnpin.isEmpty else { return .none }
                state.offlineRemoval = OfflineRemovalRequest(
                    paths: toUnpin.map(\.path),
                    names: toUnpin.map(\.displayName)
                )
                return .none

            case let .offlineToggleTapped(favorite):
                if state.offlinePinnedFavoriteIDs.contains(favorite.id) {
                    state.offlineRemoval = OfflineRemovalRequest(
                        paths: [favorite.path],
                        names: [favorite.displayName]
                    )
                    return .none
                }
                guard !state.offlineFavoriteIDs.contains(favorite.id) else { return .none }
                state.offlinePinnedFavoriteIDs.insert(favorite.id)
                state.offlineFavoriteIDs.insert(favorite.id)
                return .send(.delegate(.offlinePinRequested([favorite.folderItem])))

            case let .favoritesResponse(.success(favorites)):
                state.phase = .loaded
                state.dataSource = .live
                let search = replaceFavorites(favorites, in: &state)
                syncCache(state)
                return .merge(search, computeOfflineAvailability(&state))

            case let .favoritesResponse(.failure(error)):
                // Offline with a saved copy: show it under a banner rather than an error screen.
                guard error == .offline else { return failLoad(&state, error) }
                let jsonCacheStore = jsonCacheStore
                let serverURL = state.serverURL
                let cacheScope = state.cacheScope
                return .run { send in
                    let cached = ListCache.load(
                        jsonCacheStore,
                        Self.cacheNamespace,
                        serverURL: serverURL,
                        scope: cacheScope,
                        as: [Favorite].self
                    )
                    await send(.offlineFavoritesResolved(
                        cached: cached?.value,
                        fetchedAt: cached?.fetchedAt,
                        error: error
                    ))
                }
                .cancellable(id: CancelID.load)

            case let .offlineFavoritesResolved(cached, fetchedAt, error):
                guard let cached, let fetchedAt else { return failLoad(&state, error) }
                state.phase = .loaded
                state.dataSource = .cached(fetchedAt: fetchedAt)
                return .merge(replaceFavorites(cached, in: &state), computeOfflineAvailability(&state))

            case let .cachedFavoritesPainted(cached):
                guard state.phase == .loading, state.favorites.isEmpty else { return .none }
                return replaceFavorites(cached, in: &state)

            case let .rowTapped(favorite):
                pushFolder(favorite.path, title: favorite.displayName, in: &state)
                return .none

            case let .removeTapped(favorite):
                state.actionErrorMessage = nil
                let serverURL = state.serverURL
                let filesClient = filesClient
                return .run { send in
                    try await send(.removeResponse(favorite.id, apiResult {
                        try await filesClient.removeFavorite(serverURL, favorite.path)
                        return true
                    }), animation: .default)
                }
                // A rapid double tap on one row's remove collapses to a single request.
                .cancellable(id: CancelID.remove(favorite.id), cancelInFlight: true)

            case let .removeResponse(id, .success):
                state.favorites.remove(id: id)
                syncCache(state)
                return .none

            case let .removeResponse(_, .failure(error)):
                state.actionErrorMessage = error.userMessage
                return .none

            case let .editTapped(favorite):
                state.editSheet = FavoriteEditFeature.State(serverURL: state.serverURL, favorite: favorite)
                return .none

            case let .editSheet(.presented(.delegate(.updated(favorite)))):
                state.favorites[id: favorite.id] = favorite
                state.editSheet = nil
                return .send(.delegate(.favoritesChanged))

            case .editSheet:
                return .none

            case let .favoritesMoved(source, destination):
                guard state.canReorder else { return .none }
                var items = Array(state.favorites)
                items.move(fromOffsets: source, toOffset: destination)
                state.favorites = IdentifiedArray(items, id: \.id, uniquingIDsWith: { first, _ in first })
                state.actionErrorMessage = nil
                let orderedIDs = items.map(\.id)
                let serverURL = state.serverURL
                let filesClient = filesClient
                return .run { send in
                    try await send(.reorderResponse(apiResult {
                        try await filesClient.reorderFavorites(serverURL, orderedIDs)
                    }))
                }
                .cancellable(id: CancelID.reorder, cancelInFlight: true)

            case let .reorderResponse(.success(favorites)):
                let search = replaceFavorites(favorites, in: &state)
                syncCache(state)
                return .merge(search, .send(.delegate(.favoritesChanged)))

            case .reorderResponse(.failure):
                state.actionErrorMessage = L10n.Favorites.reorderFailed
                // The optimistic move may be out of sync with the server now: refetch the
                // authoritative order.
                return load(&state)

            case let .searchQueryChanged(query):
                // A focus change or keyboard dismiss resends the same text through the field's
                // binding, and a typed space leaves the term the server reads unchanged; searching
                // again would flash the results. Only a new term searches again.
                let isNewTerm = SearchTerm(query) != SearchTerm(state.searchQuery)
                state.searchQuery = query
                guard isNewTerm else { return .none }
                return favoriteSearch(&state)

            case let .fileSearchResponse(.success(results)):
                // Each favorite's answer is ranked on its own; merged, they are ranked again the way
                // the server ranks one answer, closest name first, rather than alphabetically.
                state.fileSearchResults = IdentifiedArray(
                    SearchTerm(state.searchQuery).ranked(results), id: \.id, uniquingIDsWith: { first, _ in first }
                )
                state.searchPhase = .loaded
                return .none

            case let .fileSearchResponse(.failure(error)):
                // A first search with nothing on screen shows the full screen failure; a refine over
                // existing results keeps them and surfaces a toast instead.
                if state.fileSearchResults == nil {
                    state.searchPhase = .failed(error.userMessage)
                } else {
                    state.searchPhase = .loaded
                    state.actionErrorMessage = error.userMessage
                }
                return .none

            case .searchRetryTapped:
                return favoriteSearch(&state, isDebounced: false)

            case .computeSearchOnDevice:
                return .searchOnDevice(
                    state.fileSearchResults?.elements ?? [],
                    ids: &state.searchOnDeviceIDs,
                    store: offlineFileStore.pinned(to: state.cacheScope),
                    cancelID: CancelID.searchOnDevice
                ) { .searchOnDeviceComputed($0) }

            case let .searchOnDeviceComputed(ids):
                state.searchOnDeviceIDs = ids
                return .none

            case let .searchResultTapped(result):
                // A directory result navigates into that folder (push). A file result opens directly
                // in a preview cover hosted here (no folder navigation): spin up a `BrowseFeature`
                // scoped to the file's parent, seed `previewItem` so the cover has content on the
                // first frame, then let `rowTapped` fetch it. `result.path` is the parent dir.
                guard !result.isDirectory else {
                    pushFolder(result.id, title: result.name, in: &state)
                    return .none
                }
                let item = offlineFileStore.pinned(to: state.cacheScope).matchingPinnedCopy(
                    result.previewItem(openedAt: date.now)
                )
                state.previewHost = .previewHost(
                    for: item,
                    serverURL: state.serverURL,
                    folderTitle: result.enclosingFolderTitle
                )
                return .send(.previewHost(.presented(.rowTapped(item))))

            case let .searchResultEnclosingFolderTapped(result):
                pushFolder(result.path, title: result.enclosingFolderTitle, in: &state)
                return .none

            case let .path(.element(id: _, action: .delegate(.downloadRequested(items)))),
                 let .previewHost(.presented(.delegate(.downloadRequested(items)))):
                return .send(.delegate(.downloadRequested(items)))

            case let .path(.element(id: _, action: .delegate(.offlinePinRequested(items)))),
                 let .previewHost(.presented(.delegate(.offlinePinRequested(items)))):
                return .send(.delegate(.offlinePinRequested(items)))

            case let .path(.element(id: _, action: .delegate(.offlineUnpinRequested(path)))),
                 let .previewHost(.presented(.delegate(.offlineUnpinRequested(path)))):
                return .send(.delegate(.offlineUnpinRequested(path: path)))

            case let .path(.element(id: _, action: .delegate(.saveRequested(requests)))),
                 let .previewHost(.presented(.delegate(.saveRequested(requests)))):
                return .send(.delegate(.saveRequested(requests)))

            case .previewHost(.presented(.previewDismissed)):
                // Closing the file preview tears the whole host down, returning to the results.
                state.previewHost = nil
                return .none

            case .viewSharesFromPreviewTapped:
                state.previewHost = nil
                return .send(.delegate(.goToSharedTab))

            case .previewHost(.presented(.renameResponse(.success))):
                // The preview follows the new name; the results behind it search again so they do too.
                return .send(.searchRetryTapped)

            case .previewHost(.presented(.deleteResponse(.success))):
                // The previewed file is gone: back to the results, which search again without it.
                state.previewHost = nil
                return .send(.searchRetryTapped)

            case .previewHost:
                return .none

            case .selectModeToggled:
                state.isSelecting.toggle()
                state.selectedFavoriteIDs = []
                return .none

            case let .itemSelectionToggled(id):
                if state.selectedFavoriteIDs.contains(id) {
                    state.selectedFavoriteIDs.remove(id)
                } else {
                    state.selectedFavoriteIDs.insert(id)
                }
                return .none

            case .selectAllTapped:
                state.selectedFavoriteIDs = Set(state.displayedFavorites.map(\.id))
                return .none

            case .deselectAllTapped:
                state.selectedFavoriteIDs = []
                return .none

            case .bulkRemoveTapped:
                guard !state.selectedFavoriteIDs.isEmpty else { return .none }
                state.bulkRemoveConfirmationIsPresented = true
                return .none

            case .bulkRemoveCancelled:
                state.bulkRemoveConfirmationIsPresented = false
                return .none

            case .bulkRemoveConfirmed:
                state.actionErrorMessage = nil
                return confirmBulkRemove(&state)

            case let .bulkRemoveResponse(removedPaths):
                let attempted = state.selectedFavoriteIDs.count
                state.favorites.removeAll { removedPaths.contains($0.path) }
                if removedPaths.isEmpty, attempted > 0 {
                    state.actionErrorMessage = attempted == 1
                        ? L10n.Favorites.removeFailedOne
                        : L10n.Favorites.removeFailedMany
                } else if removedPaths.count < attempted {
                    state.actionErrorMessage = L10n.Favorites.removePartial(removedPaths.count, attempted)
                }
                state.isSelecting = false
                state.selectedFavoriteIDs = []
                syncCache(state)
                return .none

            case let .path(.element(id: _, action: .delegate(.openFolder(item)))):
                state.forwardStack = []
                state.path.append(BrowseNavigation.screen(for: item, serverURL: state.serverURL))
                return .none

            case let .path(.element(id: _, action: .delegate(.openPath(path, title)))):
                return .send(.navigateToDirectory(path: path, title: title))

            case .path(.element(id: _, action: .delegate(.favoritesChanged))):
                return .send(.delegate(.favoritesChanged))

            case .path(.element(id: _, action: .delegate(.directoryContentsChanged))):
                return .send(.syncPathStack)

            case .path(.element(id: _, action: .delegate(.openDownloadsTapped))):
                return .send(.delegate(.openDownloadsTapped))

            case .path(.element(id: _, action: .delegate(.goToSharedTab))):
                return .send(.delegate(.goToSharedTab))

            case let .path(.element(id: _, action: .delegate(.uploadRequested(files)))):
                return .send(.delegate(.uploadRequested(files)))

            case .offlineAvailabilityChanged:
                var effects: [Effect<Action>] = state.path.ids
                    .map { .send(.path(.element(id: $0, action: .computeOfflineAvailability))) }
                // A pin or a finished run changes which search results are on the device.
                if state.fileSearchResults != nil {
                    effects.append(.send(.computeSearchOnDevice))
                }
                return .merge(effects)

            case let .navigateToDirectory(path, title):
                state.forwardStack = []
                BrowseNavigation.jump(to: path, title: title, serverURL: state.serverURL, stack: &state.path)
                return .none

            case .syncPathStack:
                return .merge(state.path.ids.map { .send(.path(.element(id: $0, action: .refreshButtonTapped))) })

            case let .refreshDirectory(path):
                let effects = state.path.ids
                    .filter { state.path[id: $0]?.directoryPath == path }
                    .map { Effect<Action>.send(.path(.element(id: $0, action: .refreshButtonTapped))) }
                return .merge(effects)

            case .path, .delegate:
                return .none
            }
        }
        .forEach(\.path, action: \.path) {
            BrowseFeature()
        }
        .ifLet(\.$editSheet, action: \.editSheet) {
            FavoriteEditFeature()
        }
        .ifLet(\.$previewHost, action: \.previewHost) {
            BrowseFeature()
        }
    }

    /// A full screen error only when there's nothing to blank; a failure over an already populated
    /// list stays `.loaded` and toasts instead.
    private func failLoad(_ state: inout State, _ error: FilesClientError) -> Effect<Action> {
        if state.favorites.isEmpty {
            state.phase = .failed(error.userMessage)
        } else {
            state.phase = .loaded
            state.actionErrorMessage = error.userMessage
        }
        return .none
    }

    private func load(_ state: inout State) -> Effect<Action> {
        // Paint the last saved copy on a first load so there's no skeleton flash while the fetch runs
        // (stale while revalidate). A successful fetch silently replaces it; only a failed one
        // (offline) surfaces the "saved copy" banner, so `dataSource` stays `.live` here. The disk
        // read runs beside the fetch, off the main actor, and is dropped if the fetch won.
        let paint: Effect<Action>
        if !state.phase.hasLoaded, state.favorites.isEmpty {
            let jsonCacheStore = jsonCacheStore
            let serverURL = state.serverURL
            let cacheScope = state.cacheScope
            paint = .run { send in
                guard let cached = ListCache.load(
                    jsonCacheStore,
                    Self.cacheNamespace,
                    serverURL: serverURL,
                    scope: cacheScope,
                    as: [Favorite].self
                ) else { return }
                await send(.cachedFavoritesPainted(cached.value))
            }
        } else {
            paint = .none
        }
        state.phase = .loading
        let serverURL = state.serverURL
        let filesClient = filesClient
        return .merge(
            paint,
            .run { send in
                try await send(.favoritesResponse(apiResult { try await filesClient.favorites(serverURL) }))
            }
        )
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }

    /// Recomputes which favorites are available offline, off the main actor (reads the pinned
    /// manifest from disk), then commits the ids. A favorite folder counts as available when it is
    /// a pinned directory root or sits under one, so a downloaded subfolder favorite is flagged
    /// too. Mirrors `BrowseFeature.computeOfflineAvailability` for directories.
    private func computeOfflineAvailability(_ state: inout State) -> Effect<Action> {
        let favorites = state.favorites
        guard !favorites.isEmpty else {
            state.offlineFavoriteIDs = []
            state.offlinePinnedFavoriteIDs = []
            return .none
        }
        let offlineFileStore = offlineFileStore
        return .run { send in
            let (all, pinned) = await Task.detached(priority: .utility) { () -> (Set<Favorite.ID>, Set<Favorite.ID>) in
                let pinnedDirectoryPaths = offlineFileStore.pinnedRoots().filter(\.isDirectory).map(\.path)
                var all = Set<Favorite.ID>()
                var pinned = Set<Favorite.ID>()
                for favorite in favorites {
                    if pinnedDirectoryPaths.contains(favorite.path) {
                        pinned.insert(favorite.id)
                        all.insert(favorite.id)
                    } else if pinnedDirectoryPaths.contains(where: { favorite.path.hasPrefix($0 + "/") }) {
                        all.insert(favorite.id)
                    }
                }
                return (all, pinned)
            }.value
            await send(.offlineAvailabilityComputed(all: all, pinned: pinned))
        }
        .cancellable(id: CancelID.offlineAvailability, cancelInFlight: true)
    }

    /// Recursive file search fanned out across every favorited folder: one backend search per
    /// favorite (each searches that folder's whole subtree), merged and de duped. Tolerant per
    /// favorite so a since deleted favorite can't fail the whole search; results are still
    /// authoritative for the ones that answered.
    /// Opens a folder on top of the tab, ending any forward history.
    private func pushFolder(_ path: String, title: String, in state: inout State) {
        state.forwardStack = []
        state.path.append(BrowseFeature.State(serverURL: state.serverURL, directoryPath: path, title: title))
    }

    /// Replaces the list (a fetch, the saved copy, a reorder answer), sorted by position. A search
    /// already typed ran against the folders it had: when they changed (typed before the list
    /// loaded, or a favorite added or removed elsewhere) it searches the new ones at once.
    private func replaceFavorites(_ favorites: [Favorite], in state: inout State) -> Effect<Action> {
        let searchedPaths = Set(state.favorites.map(\.path))
        state.favorites = IdentifiedArray(
            favorites.sorted { $0.position < $1.position },
            id: \.id,
            uniquingIDsWith: { first, _ in first }
        )
        guard Set(state.favorites.map(\.path)) != searchedPaths else { return .none }
        return refreshSearch(&state)
    }

    /// Searches the typed term again at once, keeping the results on screen: a refresh while
    /// searching refreshes what is on screen. Nothing happens under three characters.
    private func refreshSearch(_ state: inout State) -> Effect<Action> {
        guard SearchTerm(state.searchQuery).isSearchable else { return .none }
        return favoriteSearch(&state, isDebounced: false)
    }

    /// Typing is debounced; Retry is a decision already made and asks at once.
    private func favoriteSearch(_ state: inout State, isDebounced: Bool = true) -> Effect<Action> {
        let term = SearchTerm(state.searchQuery)
        let query = term.text
        // The server only searches from three characters on.
        guard term.isSearchable else {
            state.fileSearchResults = nil
            state.searchPhase = .idle
            return .cancel(id: CancelID.search)
        }
        let favoritePaths = state.favorites.map(\.path)
        guard !favoritePaths.isEmpty else {
            state.fileSearchResults = []
            state.searchPhase = .loaded
            return .cancel(id: CancelID.search)
        }
        // Every search is loading until it answers. The view shows the skeleton only while no
        // results exist yet: refining keeps the current rows on screen, and the header says a
        // newer answer is coming.
        state.searchPhase = .loading
        let serverURL = state.serverURL
        let filesClient = filesClient
        let clock = clock
        let directoryCacheStore = directoryCacheStore.bound(to: state.cacheScope)
        let offlineFileStore = offlineFileStore.pinned(to: state.cacheScope)
        return .run { send in
            if isDebounced {
                try await clock.sleep(for: FilesClient.searchDebounce)
            }
            let outcomes = try await withThrowingTaskGroup(of: Result<[SearchResultItem], FilesClientError>
                .self)
            { group in
                for path in favoritePaths {
                    group.addTask {
                        try await apiResult {
                            try await filesClient.search(serverURL, path, query, Constants.searchLimit).items
                        }
                    }
                }
                var acc: [Result<[SearchResultItem], FilesClientError>] = []
                for try await outcome in group {
                    acc.append(outcome)
                }
                return acc
            }
            let hits = outcomes.compactMap { try? $0.get() }.flatMap { $0 }
            let firstFailure = outcomes.compactMap { outcome -> FilesClientError? in
                if case let .failure(error) = outcome {
                    return error
                }
                return nil
            }.first
            // Surface an error (retryable) only when nothing came back and at least one favorite
            // failed: a partial success still shows its hits.
            if hits.isEmpty, firstFailure == .offline {
                // No server to reach: what the device saved and kept below the favorites answers.
                let read = Task.detached(priority: .userInitiated) {
                    var heldItems = false
                    let matches = favoritePaths.flatMap { path -> [SearchResultItem] in
                        let items = BrowseFeature.savedAndKeptItems(
                            under: path,
                            serverURL: serverURL,
                            directoryCacheStore: directoryCacheStore,
                            offlineFileStore: offlineFileStore
                        )
                        heldItems = heldItems || !items.isEmpty
                        return BrowseFeature.searchMatches(items, term: term, below: path)
                    }
                    return (matches: matches, heldItems: heldItems)
                }
                // A search that ends or moves stops the read too, not just its answer.
                let kept = await withTaskCancellationHandler { await read.value } onCancel: { read.cancel() }
                guard !Task.isCancelled else { return }
                // Nothing saved at all is "offline"; saved data that matches nothing is an empty answer.
                await send(
                    kept.matches.isEmpty && !kept.heldItems
                        ? .fileSearchResponse(.failure(.offline))
                        : .fileSearchResponse(.success(kept.matches))
                )
            } else if hits.isEmpty, let firstFailure {
                await send(.fileSearchResponse(.failure(firstFailure)))
            } else {
                await send(.fileSearchResponse(.success(hits)))
            }
        }
        .cancellable(id: CancelID.search, cancelInFlight: true)
    }

    /// Persists the current list as this tab's offline copy, keeping it in sync after a load or
    /// an in-place mutation.
    private func syncCache(_ state: State) {
        ListCache.save(
            jsonCacheStore,
            Self.cacheNamespace,
            serverURL: state.serverURL,
            scope: state.cacheScope,
            value: Array(state.favorites)
        )
    }

    /// Best-effort, matching the sign-out flow's philosophy: one failure shouldn't block
    /// removing the rest of the selection.
    private func confirmBulkRemove(_ state: inout State) -> Effect<Action> {
        state.bulkRemoveConfirmationIsPresented = false
        let targets = state.favorites.filter { state.selectedFavoriteIDs.contains($0.id) }
        guard !targets.isEmpty else { return .none }
        let serverURL = state.serverURL
        let filesClient = filesClient
        return .run { send in
            var removedPaths: [String] = []
            for favorite in targets where await (try? filesClient.removeFavorite(serverURL, favorite.path)) != nil {
                removedPaths.append(favorite.path)
            }
            await send(.bulkRemoveResponse(removedPaths), animation: .default)
        }
    }
}

extension Favorite {
    /// The favorite's folder as an item, for the offline engine, which only needs its path and kind.
    var folderItem: FileItem {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        return FileItem(
            name: components.last.map(String.init) ?? path,
            path: components.dropLast().joined(separator: "/"),
            dateModified: updatedAt,
            size: 0,
            kind: FileItem.directoryKind
        )
    }
}
