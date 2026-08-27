import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Foundation
import SwiftUI

@Reducer
public struct FavoritesFeature {
    public enum SortOption: String, Hashable, Sendable, CaseIterable {
        case name, dateAdded

        var title: String {
            switch self {
            case .name: "Name"
            case .dateAdded: "Date Added"
            }
        }

        var icon: Image {
            switch self {
            case .name: IconKit.textformat
            case .dateAdded: IconKit.calendar
            }
        }
    }

    @ObservableState
    public struct State: Equatable {
        public var serverURL: URL
        public var favorites: IdentifiedArrayOf<Favorite> = []
        public var isLoading = false
        public var errorMessage: String?
        public var searchQuery = ""
        public var sortOption: SortOption = .name
        public var sortDirection: BrowseFeature.SortDirection = .ascending
        public var isSelecting = false
        public var selectedFavoriteIDs: Set<Favorite.ID> = []
        public var bulkRemoveConfirmationIsPresented = false
        /// Browsing into a favorited folder pushes here, same shape as `BrowseTabFeature` —
        /// this keeps navigation inside the Favorites tab rather than jumping to Browse.
        public var path = StackState<BrowseFeature.State>()

        public init(serverURL: URL) {
            self.serverURL = serverURL
        }

        /// Client-side filter + sort over the already-loaded list — the server returns
        /// favorites in insertion order (`position ASC, created_at ASC`), which isn't a
        /// useful display order once sort/search are in play.
        public var displayedFavorites: [Favorite] {
            let matches = searchQuery.isEmpty
                ? Array(favorites)
                : favorites.filter { FuzzyMatch.matches(query: searchQuery, in: $0.displayName) }
            let sorted = matches.sorted { lhs, rhs in
                switch sortOption {
                case .name:
                    lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                case .dateAdded:
                    lhs.createdAt < rhs.createdAt
                }
            }
            return sortDirection == .ascending ? sorted : sorted.reversed()
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case refreshButtonTapped
        case favoritesResponse(Result<[Favorite], FilesClientError>)
        case rowTapped(Favorite)
        case removeTapped(Favorite)
        case removeResponse(String)
        case searchQueryChanged(String)
        case sortOptionChanged(SortOption)
        case sortDirectionChanged(BrowseFeature.SortDirection)
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
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case favoritesChanged
            case openDownloadsTapped
        }
    }

    @Dependency(\.filesClient) var filesClient

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
                state.favorites = IdentifiedArray(uniqueElements: favorites)
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
                let serverURL = state.serverURL
                let filesClient = self.filesClient
                return .run { send in
                    if (try? await filesClient.removeFavorite(serverURL, favorite.path)) != nil {
                        await send(.removeResponse(favorite.path), animation: .default)
                    }
                }

            case let .removeResponse(path):
                state.favorites.removeAll { $0.path == path }
                return .none

            case let .searchQueryChanged(query):
                state.searchQuery = query
                return .none

            case let .sortOptionChanged(option):
                state.sortOption = option
                return .none

            case let .sortDirectionChanged(direction):
                state.sortDirection = direction
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
                return confirmBulkRemove(&state)

            case let .bulkRemoveResponse(removedPaths):
                state.favorites.removeAll { removedPaths.contains($0.path) }
                state.isSelecting = false
                state.selectedFavoriteIDs = []
                return .none

            case let .path(.element(id: _, action: .delegate(.openFolder(item)))):
                state.path.append(BrowseFeature.State(serverURL: state.serverURL, directoryPath: item.id, title: item.name))
                return .none

            case let .path(.element(id: _, action: .delegate(.openPath(path, title)))):
                return .send(.navigateToDirectory(path: path, title: title))

            case .path(.element(id: _, action: .delegate(.favoritesChanged))):
                return .send(.delegate(.favoritesChanged))

            case .path(.element(id: _, action: .delegate(.openDownloadsTapped))):
                return .send(.delegate(.openDownloadsTapped))

            case let .navigateToDirectory(path, title):
                state.path.removeAll()
                guard !path.isEmpty else { return .none }
                state.path.append(BrowseFeature.State(serverURL: state.serverURL, directoryPath: path, title: title))
                return .none

            case .syncPathStack:
                return .merge(state.path.ids.map { .send(.path(.element(id: $0, action: .refreshButtonTapped))) })

            case .path, .delegate:
                return .none
            }
        }
        .forEach(\.path, action: \.path) {
            BrowseFeature()
        }
    }

    private func load(_ state: inout State) -> Effect<Action> {
        state.isLoading = true
        state.errorMessage = nil
        let serverURL = state.serverURL
        let filesClient = self.filesClient
        return .run { send in
            do {
                let favorites = try await filesClient.favorites(serverURL)
                await send(.favoritesResponse(.success(favorites)))
            } catch {
                await send(.favoritesResponse(.failure((error as? FilesClientError) ?? .network(String(describing: error)))))
            }
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
