import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// A listing of the folder on screen landing during a search (live after the saved copy, a
/// refresh, a failure) only feeds the instant matches of a term too short for the server; it never
/// restarts the server search. An explicit refresh while searching refreshes the results at once.
@Suite(.isolatedDependencies)
@MainActor
struct BrowseSearchRefreshTests {
    private enum Constants {
        static let term = "vac"
        static let shortTerm = "va"
        static let refreshedName = "vacation-3.jpg"
    }

    private let photo = BrowseFixtures.file(TestFile.vacationPhoto, in: TestFolder.photos)
    private let deepHit = SearchResultItem(name: "vacation-2.jpg", path: "Photos/Trips", kind: "file")

    private var photoMatch: SearchResultItem {
        SearchResultItem(name: TestFile.vacationPhoto, path: TestFolder.photos, kind: "file")
    }

    private func listed(_ items: [FileItem]) -> BrowseResult {
        BrowseResult(items: items, access: BrowseTestSupport.readOnlyAccess, path: TestFolder.photos)
    }

    private func loadedState() -> BrowseFeature.State {
        var state = BrowseFixtures.state(TestFolder.photos, title: TestFolder.photos)
        state.phase = .loaded
        return state
    }

    /// A store whose server search records each term it was asked and answers `deepHit`.
    private func searchingStore(_ state: BrowseFeature.State, clock: TestClock<Duration>, queries: LockIsolated<[String]>) -> TestStoreOf<BrowseFeature> {
        let deepHit = deepHit
        return BrowseFixtures.store(state) {
            $0.continuousClock = clock
            $0.filesClient.search = { _, _, query, _ in
                queries.withValue { $0.append(query) }
                return [deepHit]
            }
        }
    }

    @Test("A listing that lands while the server search waits leaves the results and the wait alone")
    func aListingDuringThePendingSearchLeavesItAlone() async {
        let clock = TestClock()
        let queries = LockIsolated<[String]>([])
        let store = searchingStore(loadedState(), clock: clock, queries: queries)

        await store.send(.searchQueryChanged(Constants.term)) {
            $0.searchQuery = Constants.term
            $0.searchResults = []
            $0.isSearchingRemotely = true
        }
        await clock.advance(by: TestSearchTiming.partOfDebounce)
        await store.send(.itemsResponse(.success(listed([photo])))) {
            $0.items = [photo]
            $0.access = BrowseTestSupport.readOnlyAccess
        }
        await store.receive(\.offlineAvailabilityComputed)
        await clock.advance(by: TestSearchTiming.restOfDebounce)
        await store.receive(\.searchResultsResponse.success) {
            $0.isSearchingRemotely = false
            $0.searchResults = [deepHit]
        }
        #expect(queries.value == [Constants.term])
    }

    @Test("A listing that lands after the server answered keeps its results and asks nothing")
    func aListingAfterTheAnswerKeepsTheResults() async {
        var state = loadedState()
        state.searchQuery = Constants.term
        state.searchResults = [deepHit]
        let clock = TestClock()
        let queries = LockIsolated<[String]>([])
        let store = searchingStore(state, clock: clock, queries: queries)

        await store.send(.itemsResponse(.success(listed([photo])))) {
            $0.items = [photo]
            $0.access = BrowseTestSupport.readOnlyAccess
        }
        await store.receive(\.offlineAvailabilityComputed)
        await clock.advance(by: FilesClient.searchDebounce)
        await store.finish()
        #expect(queries.value.isEmpty)
    }

    @Test("A term too short for the server shows the new listing's matches as soon as it lands")
    func aShortTermFollowsTheNewListing() async {
        let clock = TestClock()
        let queries = LockIsolated<[String]>([])
        let store = searchingStore(loadedState(), clock: clock, queries: queries)

        await store.send(.searchQueryChanged(Constants.shortTerm)) {
            $0.searchQuery = Constants.shortTerm
            $0.searchResults = []
        }
        await store.send(.itemsResponse(.success(listed([photo])))) {
            $0.items = [photo]
            $0.access = BrowseTestSupport.readOnlyAccess
            $0.searchResults = [photoMatch]
        }
        await store.receive(\.offlineAvailabilityComputed)
        #expect(queries.value.isEmpty)
    }

    @Test("A term too short for the server shows the saved copy's matches as soon as it paints")
    func aShortTermFollowsTheSavedCopy() async {
        var state = BrowseFixtures.state(TestFolder.photos, title: TestFolder.photos)
        state.phase = .loading
        state.searchQuery = Constants.shortTerm
        state.searchResults = []
        let store = BrowseFixtures.store(state)

        await store.send(.cachedListingPainted(CachedDirectory(path: TestFolder.photos, items: [photo], access: BrowseTestSupport.readOnlyAccess, fetchedAt: MockDate.date))) {
            $0.items = [photo]
            $0.access = BrowseTestSupport.readOnlyAccess
            $0.isShowingCachePaint = true
            $0.searchResults = [photoMatch]
        }
    }

    @Test("A failure that clears an unconfirmed saved copy clears its matches for a short term too")
    func aShortTermLosesTheMatchesOfAClearedSavedCopy() async {
        var state = BrowseFixtures.state(TestFolder.photos, title: TestFolder.photos, items: [photo])
        state.phase = .loading
        state.isShowingCachePaint = true
        state.searchQuery = Constants.shortTerm
        state.searchResults = [photoMatch]
        let error = FilesClientError.server(statusCode: 500)
        let store = BrowseFixtures.store(state)

        await store.send(.itemsResponse(.failure(error))) {
            $0.isShowingCachePaint = false
            $0.items = []
            $0.access = nil
            $0.phase = .failed(error.userMessage)
            $0.searchResults = []
        }
    }

    @Test("Refreshing while searching refreshes the results at once and keeps them on screen meanwhile")
    func refreshingWhileSearchingRefreshesTheResults() async {
        var state = loadedState()
        state.items = [photo]
        state.searchQuery = Constants.term
        state.searchResults = [deepHit]
        let refreshed = SearchResultItem(name: Constants.refreshedName, path: TestFolder.photos, kind: "file")
        let search = AsyncGate()
        let favorites = AsyncGate()
        let queries = LockIsolated<[String]>([])
        let store = BrowseFixtures.store(state) {
            $0.continuousClock = TestClock()
            $0.serveEmptyFolders()
            $0.serveListing([photo])
            $0.holdFavorites(favorites)
            $0.filesClient.search = { _, _, query, _ in
                queries.withValue { $0.append(query) }
                try await search.wait()
                return [refreshed]
            }
        }

        await store.send(.refreshButtonTapped) {
            $0.phase = .loading
            $0.isSearchingRemotely = true
        }
        await store.receive(\.itemsResponse.success) {
            $0.phase = .loaded
            $0.access = BrowseTestSupport.readOnlyAccess
        }
        await store.receive(\.offlineAvailabilityComputed)
        search.open()
        await store.receive(\.searchResultsResponse.success) {
            $0.isSearchingRemotely = false
            $0.searchResults = [refreshed]
        }
        favorites.open()
        await store.receive(\.favoritesResponse) {
            $0.hasLoadedFavorites = true
        }
        #expect(queries.value == [Constants.term])
    }
}
