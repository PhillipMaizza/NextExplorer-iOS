import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Localization

@Reducer
public struct FavoritesFeature {
    @ObservableState
    public struct State: Equatable {
        public var serverURL: URL
        public var favorites: IdentifiedArrayOf<Favorite> = []
        /// The load lifecycle: `.idle` → `.loading` → `.loaded` / `.failed`. Drives the
        /// skeleton (`.loading` with no data) and the full screen error (`.failed`).
        public var phase: DataPhase = .idle
        /// A failed remove/reorder, or a refresh failure over an already populated list,
        /// surfaced as a toast rather than the full screen `phase.errorMessage`.
        public var actionErrorMessage: String?

        /// The first load's failure text, if it's still the current state.
        public var errorMessage: String? { phase.errorMessage }
        /// `.cached` while the list on screen is an offline copy; `.live` once a fetch lands.
        public var dataSource: CachedListSource = .live
        public var searchQuery = ""
        @Presents public var editSheet: FavoriteEditFeature.State?
        public var isSelecting = false
        public var selectedFavoriteIDs: Set<Favorite.ID> = []
        public var bulkRemoveConfirmationIsPresented = false
        /// Browsing into a favorited folder pushes here, same shape as `BrowseTabFeature` —
        /// this keeps navigation inside the Favorites tab rather than jumping to Browse.
        public var path = StackState<BrowseFeature.State>()

        public init(serverURL: URL) {
            self.serverURL = serverURL
        }

        /// Favorites are shown in the user's own order (`position`, drag to reorder) — the
        /// only transform here is the search filter. `favorites` is kept in `position` order
        /// by `load` and every reorder response.
        public var displayedFavorites: [Favorite] {
            guard !searchQuery.isEmpty else { return Array(favorites) }
            return favorites.filter { SearchMatch.matches(query: searchQuery, in: $0.displayName) }
        }

        /// Drag reorder only makes sense over the full, unfiltered list.
        public var canReorder: Bool { searchQuery.isEmpty && !isSelecting }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case refreshButtonTapped
        case favoritesResponse(Result<[Favorite], FilesClientError>)
        case rowTapped(Favorite)
        case removeTapped(Favorite)
        case removeResponse(Favorite.ID, Result<Bool, FilesClientError>)
        case editTapped(Favorite)
        case editSheet(PresentationAction<FavoriteEditFeature.Action>)
        case favoritesMoved(IndexSet, Int)
        case reorderResponse(Result<[Favorite], FilesClientError>)
        case searchQueryChanged(String)
        case selectModeToggled
        case itemSelectionToggled(Favorite.ID)
        case selectAllTapped
        case deselectAllTapped
        case bulkRemoveTapped
        case bulkRemoveCancelled
        case bulkRemoveConfirmed
        case bulkRemoveResponse([String])
        case path(StackActionOf<BrowseFeature>)
        case navigateToDirectory(path: String, title: String)
        /// Re-fetches every pushed subfolder currently on the live navigation stack — sent
        /// when the app becomes active again after being backgrounded.
        case syncPathStack
        /// Refetches only the pushed screens whose `directoryPath` equals `path`. Sent after
        /// an upload finishes so just the affected folder reloads.
        case refreshDirectory(path: String)
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case favoritesChanged
            case openDownloadsTapped
            case goToSharedTab
            case uploadRequested([PendingUpload])
        }
    }

    @Dependency(\.filesClient) var filesClient
    @Dependency(\.jsonCacheStore) var jsonCacheStore

    /// Cache namespace for this tab's saved offline copy.
    private static let cacheNamespace = "favorites"

    private enum CancelID: Hashable { case reorder, load, remove(Favorite.ID) }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.phase.shouldLoadOnAppear else { return .none }
                return load(&state)

            case .refreshButtonTapped:
                return load(&state)

            case let .favoritesResponse(.success(favorites)):
                state.phase = .loaded
                state.dataSource = .live
                state.favorites = IdentifiedArray(favorites.sorted { $0.position < $1.position }, id: \.id, uniquingIDsWith: { first, _ in first })
                syncCache(state)
                return .none

            case let .favoritesResponse(.failure(error)):
                // Offline with a saved copy: show it under a banner rather than an error screen.
                if error == .offline,
                   let cached = ListCache.load(jsonCacheStore, Self.cacheNamespace, serverURL: state.serverURL, as: [Favorite].self) {
                    state.phase = .loaded
                    state.favorites = IdentifiedArray(cached.value.sorted { $0.position < $1.position }, id: \.id, uniquingIDsWith: { first, _ in first })
                    state.dataSource = .cached(fetchedAt: cached.fetchedAt)
                    return .none
                }
                // A full screen error only when there's nothing to blank; a failure over an
                // already populated list stays `.loaded` and toasts instead.
                if state.favorites.isEmpty {
                    state.phase = .failed(error.userMessage)
                } else {
                    state.phase = .loaded
                    state.actionErrorMessage = error.userMessage
                }
                return .none

            case let .rowTapped(favorite):
                state.path.append(BrowseFeature.State(serverURL: state.serverURL, directoryPath: favorite.path, title: favorite.displayName))
                return .none

            case let .removeTapped(favorite):
                state.actionErrorMessage = nil
                let serverURL = state.serverURL
                let filesClient = self.filesClient
                return .run { send in
                    await send(.removeResponse(favorite.id, try await apiResult {
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
                let filesClient = self.filesClient
                return .run { send in
                    await send(.reorderResponse(try await apiResult {
                        try await filesClient.reorderFavorites(serverURL, orderedIDs)
                    }))
                }
                .cancellable(id: CancelID.reorder, cancelInFlight: true)

            case let .reorderResponse(.success(favorites)):
                state.favorites = IdentifiedArray(favorites.sorted { $0.position < $1.position }, id: \.id, uniquingIDsWith: { first, _ in first })
                syncCache(state)
                return .send(.delegate(.favoritesChanged))

            case .reorderResponse(.failure):
                state.actionErrorMessage = L10n.Favorites.reorderFailed
                // The optimistic move may be out of sync with the server now — refetch the
                // authoritative order.
                return load(&state)

            case let .searchQueryChanged(query):
                state.searchQuery = query
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
                    state.actionErrorMessage = attempted == 1 ? L10n.Favorites.removeFailedOne : L10n.Favorites.removeFailedMany
                } else if removedPaths.count < attempted {
                    state.actionErrorMessage = L10n.Favorites.removePartial(removedPaths.count, attempted)
                }
                state.isSelecting = false
                state.selectedFavoriteIDs = []
                syncCache(state)
                return .none

            case let .path(.element(id: _, action: .delegate(.openFolder(item)))):
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

            case let .navigateToDirectory(path, title):
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
    }

    private func load(_ state: inout State) -> Effect<Action> {
        // Paint the last saved copy immediately on a first load so there's no skeleton flash
        // while the fetch runs (stale-while-revalidate). A successful fetch silently replaces it;
        // only a failed one (offline) surfaces the "saved copy" banner, so `dataSource` stays
        // `.live` here.
        if !state.phase.hasLoaded, state.favorites.isEmpty,
           let cached = ListCache.load(jsonCacheStore, Self.cacheNamespace, serverURL: state.serverURL, as: [Favorite].self) {
            state.favorites = IdentifiedArray(cached.value.sorted { $0.position < $1.position }, id: \.id, uniquingIDsWith: { first, _ in first })
        }
        state.phase = .loading
        let serverURL = state.serverURL
        let filesClient = self.filesClient
        return .run { send in
            await send(.favoritesResponse(try await apiResult { try await filesClient.favorites(serverURL) }))
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }

    /// Persists the current list as this tab's offline copy, keeping it in sync after a load or
    /// an in-place mutation.
    private func syncCache(_ state: State) {
        ListCache.save(jsonCacheStore, Self.cacheNamespace, serverURL: state.serverURL, value: Array(state.favorites))
    }

    /// Best-effort, matching the sign-out flow's philosophy: one failure shouldn't block
    /// removing the rest of the selection.
    private func confirmBulkRemove(_ state: inout State) -> Effect<Action> {
        state.bulkRemoveConfirmationIsPresented = false
        let targets = state.favorites.filter { state.selectedFavoriteIDs.contains($0.id) }
        guard !targets.isEmpty else { return .none }
        let serverURL = state.serverURL
        let filesClient = self.filesClient
        return .run { send in
            var removedPaths: [String] = []
            for favorite in targets {
                if (try? await filesClient.removeFavorite(serverURL, favorite.path)) != nil {
                    removedPaths.append(favorite.path)
                }
            }
            await send(.bulkRemoveResponse(removedPaths), animation: .default)
        }
    }
}
