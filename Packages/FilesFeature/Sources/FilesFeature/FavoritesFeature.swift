import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation

@Reducer
public struct FavoritesFeature {
    @ObservableState
    public struct State: Equatable {
        public var serverURL: URL
        public var favorites: IdentifiedArrayOf<Favorite> = []
        public var isLoading = false
        public var errorMessage: String?

        public init(serverURL: URL) {
            self.serverURL = serverURL
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case refreshButtonTapped
        case favoritesResponse(Result<[Favorite], FilesClientError>)
        case rowTapped(Favorite)
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case didSelectDirectory(path: String, title: String)
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
                return .send(.delegate(.didSelectDirectory(path: favorite.path, title: favorite.displayName)))

            case .delegate:
                return .none
            }
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
}
