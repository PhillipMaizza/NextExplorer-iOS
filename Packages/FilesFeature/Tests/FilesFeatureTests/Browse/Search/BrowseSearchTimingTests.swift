import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// When Browse asks the server: typing waits out the debounce, a term the server would read the
/// same never asks again, and a tap asks at once.
@Suite(.isolatedDependencies)
@MainActor
struct BrowseSearchTimingTests {
    private enum Constants {
        static let term = TestSearch.term
        static let longerTerm = TestSearch.longerTerm
        static let termWithSpace = "vac "
        static let shortTerm = TestSearch.shortTerm
        /// Two emoji: two characters to Swift, four UTF16 units to the server's `q.length`.
        static let emojiTerm = "👍👍"
    }

    private let hit = SearchResultItem(
        name: TestFile.vacationPhoto,
        path: TestFolder.photos,
        kind: SearchResultItem.fileKind
    )

    /// A store whose server search records each term it was asked and answers `page`.
    private func searchingStore(
        _ state: BrowseFeature.State = BrowseFixtures.state(),
        clock: TestClock<Duration>,
        queries: LockIsolated<[String]>,
        page: SearchPage? = nil
    ) -> TestStoreOf<BrowseFeature> {
        let answer = page ?? SearchPage(items: [hit])
        return BrowseFixtures.store(state) {
            $0.continuousClock = clock
            $0.filesClient.search = { _, _, query, _ in
                queries.withValue { $0.append(query) }
                return answer
            }
        }
    }

    private func type(_ query: String, into store: TestStoreOf<BrowseFeature>) async {
        await store.send(.searchQueryChanged(query)) {
            $0.searchQuery = query
            $0.searchResults = []
            $0.searchPhase = .loading
        }
    }

    @Test("Typing waits 350 ms before asking the server, and not a moment less")
    func typingWaitsOutTheDebounceExactly() async {
        let clock = TestClock()
        let queries = LockIsolated<[String]>([])
        let store = searchingStore(clock: clock, queries: queries)

        await type(Constants.term, into: store)
        await clock.advance(by: TestSearchTiming.justBeforeDebounce)
        #expect(queries.value.isEmpty)

        await clock.advance(by: TestSearchTiming.lastMoment)
        await store.receive(\.searchResultsResponse.success) {
            $0.searchAnsweredTerm = Constants.term
            $0.searchPhase = .loaded
            $0.searchResults = [hit]
        }
        #expect(queries.value == [Constants.term])
    }

    @Test("Each keystroke restarts the wait, so a burst of typing asks once, for the last term")
    func eachKeystrokeRestartsTheWait() async {
        let clock = TestClock()
        let queries = LockIsolated<[String]>([])
        let store = searchingStore(clock: clock, queries: queries)

        await type(Constants.term, into: store)
        await clock.advance(by: TestSearchTiming.partOfDebounce)
        await store.send(.searchQueryChanged(Constants.longerTerm)) {
            $0.searchQuery = Constants.longerTerm
        }
        await clock.advance(by: TestSearchTiming.partOfDebounce)
        #expect(queries.value.isEmpty)

        await clock.advance(by: TestSearchTiming.restOfDebounce)
        await store.receive(\.searchResultsResponse.success) {
            $0.searchAnsweredTerm = Constants.longerTerm
            $0.searchPhase = .loaded
            $0.searchResults = [hit]
        }
        #expect(queries.value == [Constants.longerTerm])
    }

    @Test("A typed space leaves the server's term unchanged, so the pending search keeps its wait")
    func aTypedSpaceKeepsThePendingSearch() async {
        let clock = TestClock()
        let queries = LockIsolated<[String]>([])
        let store = searchingStore(clock: clock, queries: queries)

        await type(Constants.term, into: store)
        await clock.advance(by: TestSearchTiming.partOfDebounce)
        await store.send(.searchQueryChanged(Constants.termWithSpace)) {
            $0.searchQuery = Constants.termWithSpace
        }
        await clock.advance(by: TestSearchTiming.restOfDebounce)
        await store.receive(\.searchResultsResponse.success) {
            $0.searchAnsweredTerm = Constants.term
            $0.searchPhase = .loaded
            $0.searchResults = [hit]
        }
        #expect(queries.value == [Constants.term])
    }

    @Test("A space typed after Show more keeps the wider results and asks nothing")
    func aSpaceAfterShowMoreKeepsTheWiderResults() async {
        let clock = TestClock()
        let queries = LockIsolated<[String]>([])
        let store = searchingStore(
            clock: clock,
            queries: queries,
            page: SearchPage(items: [hit], isComplete: false, limit: 100)
        )

        await type(Constants.term, into: store)
        await clock.advance(by: FilesClient.searchDebounce)
        await store.receive(\.searchResultsResponse.success) {
            $0.searchAnsweredTerm = Constants.term
            $0.searchPhase = .loaded
            $0.searchResults = [hit]
            $0.searchShortfall = .firstOnly(count: 100)
        }
        await store.send(.searchShowMoreTapped) {
            $0.searchLimit = 300
            $0.searchPhase = .loading
        }
        await store.receive(\.searchResultsResponse.success) {
            $0.searchAnsweredTerm = Constants.term
            $0.searchPhase = .loaded
        }

        await store.send(.searchQueryChanged(Constants.termWithSpace)) {
            $0.searchQuery = Constants.termWithSpace
        }
        await clock.advance(by: FilesClient.searchDebounce)
        await store.finish()
        #expect(queries.value == [Constants.term, Constants.term])
    }

    @Test("Choosing the scope already in use changes nothing and asks nothing")
    func choosingTheSameScopeIsANoOp() async {
        var state = BrowseFixtures.state(TestFolder.photos)
        state.searchQuery = Constants.term
        state.searchResults = [hit]
        let clock = TestClock()
        let queries = LockIsolated<[String]>([])
        let store = searchingStore(state, clock: clock, queries: queries)

        await store.send(.searchScopeChanged(.thisFolder))
        await clock.advance(by: FilesClient.searchDebounce)
        await store.finish()
        #expect(queries.value.isEmpty)
    }

    @Test("A term is long enough the way the server counts it, so two emoji are searched")
    func lengthIsCountedLikeTheServer() async {
        let clock = TestClock()
        let queries = LockIsolated<[String]>([])
        let store = searchingStore(clock: clock, queries: queries)

        await type(Constants.emojiTerm, into: store)
        #expect(!store.state.isSearchTermTooShort)
        await clock.advance(by: FilesClient.searchDebounce)
        await store.receive(\.searchResultsResponse.success) {
            $0.searchAnsweredTerm = Constants.emojiTerm
            $0.searchPhase = .loaded
            $0.searchResults = [hit]
        }
        #expect(queries.value == [Constants.emojiTerm])
    }

    @Test("A search is pending from the keystroke until the server answers, and never for a short term")
    func aSearchIsPendingUntilTheServerAnswers() async {
        let clock = TestClock()
        let queries = LockIsolated<[String]>([])
        let store = searchingStore(clock: clock, queries: queries)

        await store.send(.searchQueryChanged(Constants.shortTerm)) {
            $0.searchQuery = Constants.shortTerm
            $0.searchResults = []
        }
        await store.receive(\.searchSavedItemsLoaded) {
            $0.searchSavedItems = [:]
        }
        #expect(!store.state.isSearchPending)

        await type(Constants.term, into: store)
        #expect(store.state.isSearchPending)
        await clock.advance(by: FilesClient.searchDebounce)
        await store.receive(\.searchResultsResponse.success) {
            $0.searchAnsweredTerm = Constants.term
            $0.searchPhase = .loaded
            $0.searchResults = [hit]
        }
        #expect(!store.state.isSearchPending)
    }
}
