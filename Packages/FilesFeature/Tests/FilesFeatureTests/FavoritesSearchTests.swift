import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct FavoritesSearchTests: FavoritesTestSupport {
    private enum Constants {
        static let term = "internet"
        static let termWithSpace = "internet "
    }

    private let hit = SearchResultItem(name: "internet.pdf", path: "Bills", kind: "file")

    /// One favorite, `Bills`, whose search records each term it was asked and answers `hit`.
    private func searchingStore(_ state: FavoritesFeature.State? = nil, clock: TestClock<Duration>, queries: LockIsolated<[String]>) -> TestStoreOf<FavoritesFeature> {
        var initial = state ?? FavoritesFeature.State(serverURL: serverURL)
        initial.favorites = [makeFavorite(id: "1", path: "Bills")]
        let hit = hit
        return TestStore(initialState: initial) {
            FavoritesFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.filesClient.search = { _, _, query, _ in
                queries.withValue { $0.append(query) }
                return [hit]
            }
        }
    }

    @Test
    func searchQueryChangedFiltersDisplayedFavorites() async {
        let vacation = makeFavorite(id: "1", path: "Photos/Vacation")
        let work = makeFavorite(id: "2", path: TestPath.documentsWork)
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [vacation, work]

        let clock = TestClock()
        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.filesClient.search = { _, _, _, _ in [] }
        }

        // The name filter over the favorite folders still applies (a query also kicks off the
        // recursive file search fan out, exercised in its own test).
        await store.send(.searchQueryChanged("vaca")) {
            $0.searchQuery = "vaca"
            $0.searchPhase = .loading
        }
        #expect(store.state.displayedFavorites == [vacation])

        await clock.advance(by: FilesClient.searchDebounce)
        await store.receive(\.fileSearchResponse.success) {
            $0.fileSearchResults = []
            $0.searchPhase = .loaded
        }
    }

    @Test
    func rootSearchFansOutAcrossEveryFavoriteAndMergesResults() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [makeFavorite(id: "1", path: "Bills"), makeFavorite(id: "2", path: TestFolder.photos)]

        let billsHit = SearchResultItem(name: "internet.pdf", path: "Bills", kind: "file")
        let photosHit = SearchResultItem(name: "photos-internet.png", path: TestFolder.photos, kind: "file")
        let clock = TestClock()
        let searchedPaths = LockIsolated<Set<String>>([])

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.filesClient.search = { _, path, _, _ in
                searchedPaths.withValue { $0.insert(path) }
                switch path {
                case "Bills": return [billsHit]
                case TestFolder.photos: return [photosHit]
                default: return []
                }
            }
        }

        await store.send(.searchQueryChanged("internet")) {
            $0.searchQuery = "internet"
            $0.searchPhase = .loading
        }
        await clock.advance(by: FilesClient.searchDebounce)
        // Both hits merged into the results, alphabetically.
        await store.receive(\.fileSearchResponse.success) {
            $0.fileSearchResults = [billsHit, photosHit]
            $0.searchPhase = .loaded
        }

        // One backend search per favorite.
        #expect(searchedPaths.value == ["Bills", TestFolder.photos])
    }

    @Test
    func clearingTheQueryCancelsTheSearchAndClearsResults() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [makeFavorite(id: "1", path: "Bills")]
        state.searchQuery = "internet"
        state.fileSearchResults = [SearchResultItem(name: "internet.pdf", path: "Bills", kind: "file")]
        state.searchPhase = .loaded
        let clock = TestClock()

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.filesClient.search = { _, _, _, _ in [] }
        }

        await store.send(.searchQueryChanged("")) {
            $0.searchQuery = ""
            $0.fileSearchResults = nil
            $0.searchPhase = .idle
        }
        await clock.advance(by: FilesClient.searchDebounce)
        await store.finish()
    }

    @Test("Typing waits 350 ms before searching the favorites, and not a moment less")
    func typingWaitsOutTheDebounceExactly() async {
        let clock = TestClock()
        let queries = LockIsolated<[String]>([])
        let store = searchingStore(clock: clock, queries: queries)

        await store.send(.searchQueryChanged(Constants.term)) {
            $0.searchQuery = Constants.term
            $0.searchPhase = .loading
        }
        await clock.advance(by: TestSearchTiming.justBeforeDebounce)
        #expect(queries.value.isEmpty)

        await clock.advance(by: TestSearchTiming.lastMoment)
        await store.receive(\.fileSearchResponse.success) {
            $0.fileSearchResults = [hit]
            $0.searchPhase = .loaded
        }
        #expect(queries.value == [Constants.term])
    }

    @Test("A typed space leaves the server's term unchanged, so the pending search keeps its wait")
    func aTypedSpaceKeepsThePendingSearch() async {
        let clock = TestClock()
        let queries = LockIsolated<[String]>([])
        let store = searchingStore(clock: clock, queries: queries)

        await store.send(.searchQueryChanged(Constants.term)) {
            $0.searchQuery = Constants.term
            $0.searchPhase = .loading
        }
        await clock.advance(by: TestSearchTiming.partOfDebounce)
        await store.send(.searchQueryChanged(Constants.termWithSpace)) {
            $0.searchQuery = Constants.termWithSpace
        }
        await clock.advance(by: TestSearchTiming.restOfDebounce)
        await store.receive(\.fileSearchResponse.success) {
            $0.fileSearchResults = [hit]
            $0.searchPhase = .loaded
        }
        #expect(queries.value == [Constants.term])
    }

    @Test("Retry searches at once, without the typing wait")
    func retrySearchesAtOnce() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.searchQuery = Constants.term
        state.searchPhase = .failed(FilesClientError.offline.userMessage)
        let clock = TestClock()
        let queries = LockIsolated<[String]>([])
        let store = searchingStore(state, clock: clock, queries: queries)

        await store.send(.searchRetryTapped) {
            $0.searchPhase = .loading
        }
        await store.receive(\.fileSearchResponse.success) {
            $0.fileSearchResults = [hit]
            $0.searchPhase = .loaded
        }
        #expect(queries.value == [Constants.term])
    }
}
