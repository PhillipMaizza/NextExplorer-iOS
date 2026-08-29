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
        public var isLoading = false
        public var errorMessage: String?
        /// A failed remove/reorder, surfaced as a toast rather than the list level
        /// `errorMessage`, which is only shown when the list is empty.
        public var actionErrorMessage: String?
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
            return favorites.filter { FuzzyMatch.matches(query: searchQuery, in: $0.displayName) }
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
            case uploadRequested([PendingUpload])
        }
    }

    @Dependency(\.filesClient) var filesClient

    private enum CancelID { case reorder }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.favorites.isEmpty, state.errorMessage == nil, !state.isLoading else { return .none }
                return load(&state)

            case .refreshButtonTapped:
                return load(&state)

            case let .favoritesResponse(.success(favorites)):
                state.isLoading = false
                state.favorites = IdentifiedArray(uniqueElements: favorites.sorted { $0.position < $1.position })
                state.errorMessage = nil
                return .none

            case let .favoritesResponse(.failure(error)):
                state.isLoading = false
                state.errorMessage = error.userMessage
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

            case let .removeResponse(id, .success):
                state.favorites.remove(id: id)
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
                state.favorites = IdentifiedArray(uniqueElements: items)
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
                state.favorites = IdentifiedArray(uniqueElements: favorites.sorted { $0.position < $1.position })
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
        state.isLoading = true
        state.errorMessage = nil
        let serverURL = state.serverURL
        let filesClient = self.filesClient
        return .run { send in
            await send(.favoritesResponse(try await apiResult { try await filesClient.favorites(serverURL) }))
        }
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
