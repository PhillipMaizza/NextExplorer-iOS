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
        /// The hits kept on this device, listed first under their own heading.
        var onDeviceIDs: Set<String> = []
        /// The highlighted hit; `nil` until an arrow key moves there, when Return opens the first.
        public var activeIndex: Int?
        public var limit = FilesClient.searchLimitSteps[0]
        public var shortfall: SearchShortfall?
        let serverURL: URL
        /// The folder on screen in Browse, else the volume root: the search covers everything, and
        /// the hits inside this folder are listed first.
        let basePath: String
        /// Read for the Show Thumbnails setting, so image, video and audio hits show their picture.
        @Shared(.inMemory("userPreferences")) var preferences = UserPreferences()

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

        var sections: SearchResultSections {
            SearchResultSections(Array(results), onDeviceIDs: onDeviceIDs)
        }

        /// The hits in the order they are listed: on the device first, then the rest.
        var displayed: [SearchResultItem] {
            sections.onDevice + sections.remote
        }

        /// The hit Return opens: the highlighted one, else the first.
        var returnTarget: SearchResultItem? {
            displayed[safe: activeIndex ?? 0]
        }
    }

    public enum Action: Equatable, Sendable {
        case queryChanged(String)
        case searchResponse(Result<SearchPage, FilesClientError>, term: String)
        case savedMatchesLoaded([SearchResultItem])
        case onDeviceComputed(Set<String>)
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
    @Dependency(\.directoryCacheStore) var directoryCacheStore
    @Dependency(\.offlineFileStore) var offlineFileStore
    @Dependency(\.cacheScope) var cacheScope

    private enum CancelID { case search, onDevice }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .queryChanged(query):
                // Return re sends the field's unchanged text: it must keep the highlight Return opens.
                guard query != state.query else { return .none }
                let isNewTerm = SearchTerm(query) != SearchTerm(state.query)
                state.query = query
                state.activeIndex = nil
                if isNewTerm {
                    state.limit = FilesClient.searchLimitSteps[0]
                }
                guard SearchTerm(query).isSearchable else {
                    state.results = []
                    state.onDeviceIDs = []
                    state.shortfall = nil
                    state.phase = .idle
                    return .cancel(id: CancelID.search)
                }
                state.phase = .loading
                return search(state, isDebounced: true)

            case let .searchResponse(_, term) where term != SearchTerm(state.query).text:
                // The fetches of one burst of typing can start out of order, and the one that starts
                // last cancels the rest: drop an older term's answer and ask again for the typed one.
                return state.phase == .loading ? search(state, isDebounced: false) : .none

            case let .searchResponse(.success(page), _):
                state.results = IdentifiedArray(page.items, uniquingIDsWith: { first, _ in first })
                state.shortfall = SearchShortfall(page)
                state.activeIndex = nil
                state.phase = .loaded
                return findOnDevice(&state)

            case .searchResponse(.failure(.offline), _):
                // Without a connection what is kept on the device is still found, never invented.
                state.results = []
                state.shortfall = nil
                state.activeIndex = nil
                return savedMatches(state)

            case let .savedMatchesLoaded(matches):
                state.results = IdentifiedArray(matches, uniquingIDsWith: { first, _ in first })
                state.activeIndex = nil
                state.phase = .loaded
                return findOnDevice(&state)

            case let .onDeviceComputed(ids):
                state.onDeviceIDs = ids
                return .none

            case let .searchResponse(.failure(error), _):
                state.results = []
                state.onDeviceIDs = []
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
                let count = state.displayed.count
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

    private func findOnDevice(_ state: inout State) -> Effect<Action> {
        .searchOnDevice(
            Array(state.results),
            ids: &state.onDeviceIDs,
            store: offlineFileStore.pinned(to: cacheScope.current()),
            cancelID: CancelID.onDevice
        ) { .onDeviceComputed($0) }
    }

    /// What the device holds that the term matches, the folder on screen's first.
    private func savedMatches(_ state: State) -> Effect<Action> {
        let scope = cacheScope.current()
        let directoryCache = directoryCacheStore.bound(to: scope)
        let offline = offlineFileStore.pinned(to: scope)
        let serverURL = state.serverURL
        let base = state.basePath
        let term = SearchTerm(state.query)
        return .run { send in
            let matches = await Task.detached(priority: .userInitiated) {
                let items = BrowseFeature.savedAndKeptItems(
                    under: "",
                    serverURL: serverURL,
                    directoryCacheStore: directoryCache,
                    offlineFileStore: offline
                )
                let matches = term.ranked(BrowseFeature.searchMatches(items, term: term, below: ""))
                return SpotlightFeature.folderFirst(matches, below: base)
            }.value
            await send(.savedMatchesLoaded(matches))
        }
        .cancellable(id: CancelID.search, cancelInFlight: true)
    }

    /// The hits inside `base` (its whole subtree) first, each group keeping its order.
    static func folderFirst(_ hits: [SearchResultItem], below base: String) -> [SearchResultItem] {
        guard !base.isEmpty else { return hits }
        let isInside = { (hit: SearchResultItem) in hit.path == base || hit.path.hasPrefix(base + "/") }
        return hits.filter(isInside) + hits.filter { !isInside($0) }
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
                guard !basePath.isEmpty else {
                    return try await filesClient.search(serverURL, "", term, limit)
                }
                // The folder gets its own search: the volume wide page can fill up before reaching
                // its hits. Listed first, they win the duplicates the wider search repeats.
                async let inFolder = filesClient.search(serverURL, basePath, term, limit)
                async let everywhere = filesClient.search(serverURL, "", term, limit)
                // The wider answer decides: a folder that cannot be searched only loses its head start.
                let everywherePage = try await everywhere
                let folderItems = await (try? inFolder)?.items ?? []
                var page = everywherePage
                page.items = folderItems + everywherePage.items
                return page
            },
            response: { .searchResponse($0, term: term) }
        )
    }
}

private extension Array {
    subscript(safe index: Int?) -> Element? {
        guard let index, indices.contains(index) else { return nil }
        return self[index]
    }
}
