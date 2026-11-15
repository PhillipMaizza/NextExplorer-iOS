import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation

/// The Mac search panel, as the web client's Spotlight: type to search below the folder on
/// screen, arrow keys move through the hits, Return opens the highlighted one. It owns only the
/// query and its answer; opening a hit is the parent's job, through the delegate.
@Reducer
public struct SpotlightFeature {
    @ObservableState
    public struct State: Equatable {
        public var query = ""
        /// `.loading` covers the typing wait and the request, so a search that has not started yet
        /// never reads as "no matches".
        public var phase: DataPhase = .idle
        public var results: IdentifiedArrayOf<SearchResultItem> = []
        /// The highlighted hit; `nil` until an arrow key moves there, when Return opens the first.
        public var activeIndex: Int?
        public var limit = FilesClient.searchLimitSteps[0]
        public var shortfall: SearchShortfall?
        let serverURL: URL
        /// The folder the search runs below: the one on screen in Browse, else the volume root.
        let basePath: String

        public init(serverURL: URL, basePath: String) {
            self.serverURL = serverURL
            self.basePath = basePath
        }

        var isTooShort: Bool {
            SearchTerm(query).isTooShort
        }

        var canShowMore: Bool {
            guard case .firstOnly = shortfall, let last = FilesClient.searchLimitSteps.last else { return false }
            return limit < last
        }

        /// The hit Return opens: the highlighted one, else the first.
        var returnTarget: SearchResultItem? {
            results[safe: activeIndex ?? 0]
        }
    }

    public enum Action: Equatable, Sendable {
        case queryChanged(String)
        case searchResponse(Result<SearchPage, FilesClientError>)
        case showMoreTapped
        case selectionMoved(Direction)
        case highlighted(Int?)
        case submitted
        case resultTapped(SearchResultItem)
        case closeRequested
        case delegate(Delegate)

        public enum Direction: Equatable, Sendable {
            case up, down
        }

        public enum Delegate: Equatable, Sendable {
            case openResult(SearchResultItem)
            case closed
        }
    }

    @Dependency(\.filesClient) var filesClient
    @Dependency(\.continuousClock) var clock

    private enum CancelID { case search }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .queryChanged(query):
                let isNewTerm = SearchTerm(query) != SearchTerm(state.query)
                state.query = query
                state.activeIndex = nil
                if isNewTerm {
                    state.limit = FilesClient.searchLimitSteps[0]
                }
                guard SearchTerm(query).isSearchable else {
                    state.results = []
                    state.shortfall = nil
                    state.phase = .idle
                    return .cancel(id: CancelID.search)
                }
                state.phase = .loading
                return search(state, isDebounced: true)

            case let .searchResponse(.success(page)):
                state.results = IdentifiedArray(page.items, uniquingIDsWith: { first, _ in first })
                state.shortfall = SearchShortfall(page)
                state.activeIndex = nil
                state.phase = .loaded
                return .none

            case let .searchResponse(.failure(error)):
                state.results = []
                state.shortfall = nil
                state.activeIndex = nil
                state.phase = .failed(searchFailureMessage(error))
                return .none

            case .showMoreTapped:
                guard state.canShowMore else { return .none }
                state.limit = FilesClient.searchLimitSteps.first { $0 > state.limit } ?? state.limit
                state.phase = .loading
                return search(state, isDebounced: false)

            case let .selectionMoved(direction):
                let count = state.results.count
                guard count > 0 else { return .none }
                switch direction {
                case .down: state.activeIndex = ((state.activeIndex ?? -1) + 1) % count
                case .up: state.activeIndex = ((state.activeIndex ?? 0) - 1 + count) % count
                }
                return .none

            case let .highlighted(index):
                state.activeIndex = index
                return .none

            case .submitted:
                guard let target = state.returnTarget else { return .none }
                return .send(.delegate(.openResult(target)))

            case let .resultTapped(result):
                return .send(.delegate(.openResult(result)))

            case .closeRequested:
                return .merge(.cancel(id: CancelID.search), .send(.delegate(.closed)))

            case .delegate:
                return .none
            }
        }
    }

    private func search(_ state: State, isDebounced: Bool) -> Effect<Action> {
        let filesClient = filesClient
        let clock = clock
        let serverURL = state.serverURL
        let basePath = state.basePath
        let term = SearchTerm(state.query).text
        let limit = state.limit
        return .api(
            cancelID: CancelID.search,
            operation: {
                if isDebounced {
                    try await clock.sleep(for: FilesClient.searchDebounce)
                }
                return try await filesClient.search(serverURL, basePath, term, limit)
            },
            response: Action.searchResponse
        )
    }
}

private extension IdentifiedArray where Element: Identifiable, ID == Element.ID {
    subscript(safe index: Int?) -> Element? {
        guard let index, indices.contains(index) else { return nil }
        return self[index]
    }
}
