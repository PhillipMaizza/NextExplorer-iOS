import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// The Mac search panel: typing waits out the debounce, only the newest term is answered, Show more
/// widens at once, the arrow keys wrap, and Return opens the highlighted hit or the first.
@Suite(.isolatedDependencies)
@MainActor
struct SpotlightFeatureTests {
    private enum Constants {
        static let term = TestSearch.term
        static let longerTerm = TestSearch.longerTerm
        static let shortTerm = TestSearch.shortTerm
        static let basePath = TestFolder.documents
        static let secondStep = 300
        static let lastStep = 500
    }

    private let folderHit = SearchResultItem(
        name: TestFolder.photos,
        path: "",
        kind: SearchResultItem.directoryKind
    )
    private let fileHit = SearchResultItem(
        name: TestFile.vacationPhoto,
        path: TestFolder.photos,
        kind: SearchResultItem.fileKind
    )
    private let otherHit = SearchResultItem(
        name: TestFile.notes,
        path: TestFolder.documents,
        kind: SearchResultItem.fileKind
    )

    private func state(basePath: String = Constants.basePath) -> SpotlightFeature.State {
        SpotlightFeature.State(serverURL: TestHost.serverURL, basePath: basePath)
    }

    private struct Ask: Equatable {
        let path: String
        let query: String
        let limit: Int?
    }

    private func store(
        _ state: SpotlightFeature.State,
        clock: TestClock<Duration>,
        asked: LockIsolated<[Ask]> = LockIsolated([]),
        page: SearchPage
    ) -> TestStoreOf<SpotlightFeature> {
        TestStore(initialState: state) {
            SpotlightFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.offlineFileStore = .inMemory(copyMetadata: [:])
            $0.filesClient.search = { _, path, query, limit in
                asked.withValue { $0.append(Ask(path: path, query: query, limit: limit)) }
                return page
            }
        }
    }

    private func loaded(
        _ hits: [SearchResultItem],
        activeIndex: Int? = nil,
        shortfall: SearchShortfall? = nil,
        limit: Int = FilesClient.searchLimitSteps[0]
    ) -> SpotlightFeature.State {
        var state = state()
        state.query = Constants.term
        state.phase = .loaded
        state.results = IdentifiedArray(hits, uniquingIDsWith: { first, _ in first })
        state.activeIndex = activeIndex
        state.shortfall = shortfall
        state.limit = limit
        return state
    }

    @Test("A term shorter than the server accepts is never sent and clears the answer")
    func shortTermAsksNothing() async {
        let clock = TestClock<Duration>()
        let asked = LockIsolated<[Ask]>([])
        var start = loaded([fileHit])
        start.query = Constants.term
        let store = store(start, clock: clock, asked: asked, page: SearchPage(items: [fileHit]))

        await store.send(.queryChanged(Constants.shortTerm)) {
            $0.query = Constants.shortTerm
            $0.results = []
            $0.phase = .idle
        }
        await clock.advance(by: .seconds(1))
        #expect(asked.value.isEmpty)
    }

    @Test("An earlier term's answer landing late is dropped and the typed term is asked at once")
    func anEarlierTermsLateAnswerIsDroppedAndTheTypedTermAskedAgain() async {
        let clock = TestClock<Duration>()
        let asked = LockIsolated<[Ask]>([])
        let store = store(state(basePath: ""), clock: clock, asked: asked, page: SearchPage(items: [fileHit]))

        await store.send(.queryChanged(Constants.longerTerm)) {
            $0.query = Constants.longerTerm
            $0.phase = .loading
        }
        await store.send(.searchResponse(.success(SearchPage(items: [otherHit])), term: Constants.term))
        await store.receive(\.searchResponse) {
            $0.results = [fileHit]
            $0.phase = .loaded
        }
        await store.receive(\.onDeviceComputed)
        #expect(asked.value.map(\.query) == [Constants.longerTerm], "asked without waiting out the debounce")
    }

    @Test("Typing waits 350 ms, then asks the folder and everywhere with the first limit")
    func typingWaitsThenAsks() async {
        let clock = TestClock<Duration>()
        let asked = LockIsolated<[Ask]>([])
        let store = store(state(), clock: clock, asked: asked, page: SearchPage(items: [folderHit, fileHit]))

        await store.send(.queryChanged(Constants.term)) {
            $0.query = Constants.term
            $0.phase = .loading
        }
        await clock.advance(by: TestSearchTiming.justBeforeDebounce)
        #expect(asked.value.isEmpty)

        await clock.advance(by: TestSearchTiming.lastMoment)
        await store.receive(\.searchResponse) {
            $0.results = [folderHit, fileHit]
            $0.phase = .loaded
        }
        await store.receive(\.onDeviceComputed)
        #expect(Set(asked.value.map(\.path)) == ["", Constants.basePath])
        #expect(asked.value.allSatisfy { $0.query == Constants.term && $0.limit == FilesClient.searchLimitSteps[0] })
    }

    @Test("The folder's hits come first, then the rest, each listed once")
    func folderHitsComeFirst() async {
        let clock = TestClock<Duration>()
        let store = TestStore(initialState: state()) {
            SpotlightFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.offlineFileStore = .inMemory(copyMetadata: [:])
            $0.filesClient.search = { [folderHit, fileHit, otherHit] _, path, _, _ in
                path.isEmpty ? SearchPage(items: [folderHit, fileHit, otherHit]) : SearchPage(items: [otherHit])
            }
        }

        await store.send(.queryChanged(Constants.term)) {
            $0.query = Constants.term
            $0.phase = .loading
        }
        await clock.advance(by: .milliseconds(350))
        await store.receive(\.searchResponse) {
            $0.results = [otherHit, folderHit, fileHit]
            $0.phase = .loaded
        }
        await store.receive(\.onDeviceComputed)
    }

    @Test("A folder that cannot be searched still lists everything the wider search found")
    func folderSearchFailureKeepsTheWiderAnswer() async {
        let clock = TestClock<Duration>()
        let store = TestStore(initialState: state()) {
            SpotlightFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.offlineFileStore = .inMemory(copyMetadata: [:])
            $0.filesClient.search = { [folderHit, fileHit] _, path, _, _ in
                guard path.isEmpty else { throw FilesClientError.forbidden(message: nil) }
                return SearchPage(items: [folderHit, fileHit])
            }
        }

        await store.send(.queryChanged(Constants.term)) {
            $0.query = Constants.term
            $0.phase = .loading
        }
        await clock.advance(by: .milliseconds(350))
        await store.receive(\.searchResponse) {
            $0.results = [folderHit, fileHit]
            $0.phase = .loaded
        }
        await store.receive(\.onDeviceComputed)
    }

    @Test("At the root one search asks everywhere")
    func rootAsksOnce() async {
        let clock = TestClock<Duration>()
        let asked = LockIsolated<[Ask]>([])
        let store = store(state(basePath: ""), clock: clock, asked: asked, page: SearchPage(items: [fileHit]))

        await store.send(.queryChanged(Constants.term)) {
            $0.query = Constants.term
            $0.phase = .loading
        }
        await clock.advance(by: .milliseconds(350))
        await store.receive(\.searchResponse) {
            $0.results = [fileHit]
            $0.phase = .loaded
        }
        await store.receive(\.onDeviceComputed)
        #expect(asked.value.map(\.path) == [""])
    }

    @Test("Offline matches keep the folder's first, in their ranked order")
    func folderFirstPartition() {
        #expect(SpotlightFeature.folderFirst([folderHit, fileHit, otherHit], below: Constants.basePath)
            == [otherHit, folderHit, fileHit])
        #expect(SpotlightFeature.folderFirst([folderHit, fileHit], below: "") == [folderHit, fileHit])
    }

    @Test("A newer term replaces the one still waiting, so only it is asked")
    func newestTermWins() async {
        let clock = TestClock<Duration>()
        let asked = LockIsolated<[Ask]>([])
        let store = store(state(), clock: clock, asked: asked, page: SearchPage(items: [fileHit]))

        await store.send(.queryChanged(Constants.term)) {
            $0.query = Constants.term
            $0.phase = .loading
        }
        await clock.advance(by: TestSearchTiming.partOfDebounce)
        await store.send(.queryChanged(Constants.longerTerm)) {
            $0.query = Constants.longerTerm
        }
        await clock.advance(by: .milliseconds(350))
        await store.receive(\.searchResponse) {
            $0.results = [fileHit]
            $0.phase = .loaded
        }
        await store.receive(\.onDeviceComputed)
        #expect(Set(asked.value.map(\.query)) == [Constants.longerTerm])
    }

    @Test("A failed search says why and clears the list")
    func failureShowsMessage() async {
        let clock = TestClock<Duration>()
        let store = TestStore(initialState: loaded([fileHit])) {
            SpotlightFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.filesClient.search = { _, _, _, _ in throw FilesClientError.network(TestHost.example) }
        }

        await store.send(.queryChanged(Constants.longerTerm)) {
            $0.query = Constants.longerTerm
            $0.phase = .loading
        }
        await clock.advance(by: .milliseconds(350))
        await store.receive(\.searchResponse) {
            $0.results = []
            $0.phase = .failed(searchFailureMessage(.network(TestHost.example)))
        }
    }

    @Test("Hits the server repeats are listed once")
    func duplicateHitsAreListedOnce() async {
        let clock = TestClock<Duration>()
        let store = store(state(), clock: clock, page: SearchPage(items: [fileHit, fileHit, otherHit]))

        await store.send(.queryChanged(Constants.term)) {
            $0.query = Constants.term
            $0.phase = .loading
        }
        await clock.advance(by: .milliseconds(350))
        await store.receive(\.searchResponse) {
            $0.results = [fileHit, otherHit]
            $0.phase = .loaded
        }
        await store.receive(\.onDeviceComputed)
    }

    @Test("Hits kept on the device are listed first, and the arrow keys follow that order")
    func onDeviceHitsComeFirst() async {
        var state = loaded([folderHit, fileHit, otherHit])
        state.onDeviceIDs = [otherHit.id]
        let store = TestStore(initialState: state) { SpotlightFeature() }

        #expect(store.state.displayed == [otherHit, folderHit, fileHit])
        await store.send(.selectionMoved(.down)) { $0.activeIndex = 0 }
        await store.send(.submitted)
        await store.receive(.delegate(.openResult(otherHit)))
    }

    @Test("Without a connection the search answers from the device, never from the server")
    func offlineAnswersFromTheDevice() async {
        let clock = TestClock<Duration>()
        let store = TestStore(initialState: state()) {
            SpotlightFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.offlineFileStore = .inMemory(copyMetadata: [:])
            $0.directoryCacheStore = .inMemory()
            $0.filesClient.search = { _, _, _, _ in throw FilesClientError.offline }
        }

        await store.send(.queryChanged(Constants.term)) {
            $0.query = Constants.term
            $0.phase = .loading
        }
        await clock.advance(by: .milliseconds(350))
        await store.receive(\.searchResponse)
        await store.receive(\.savedMatchesLoaded) { $0.phase = .loaded }
    }

    @Test("Show more asks at once with the next step, keeping the list while it loads")
    func showMoreWidensWithoutWaiting() async {
        let clock = TestClock<Duration>()
        let asked = LockIsolated<[Ask]>([])
        let first = SearchShortfall.firstOnly(count: FilesClient.searchLimitSteps[0])
        let store = store(
            loaded([fileHit], shortfall: first),
            clock: clock,
            asked: asked,
            page: SearchPage(items: [fileHit, otherHit])
        )

        await store.send(.showMoreTapped) {
            $0.limit = Constants.secondStep
            $0.phase = .loading
        }
        await store.receive(\.searchResponse) {
            $0.results = [fileHit, otherHit]
            $0.shortfall = nil
            $0.phase = .loaded
        }
        await store.receive(\.onDeviceComputed)
        #expect(Set(asked.value.map(\.limit)) == [Constants.secondStep])
    }

    @Test("Show more does nothing without a short answer, or at the last step")
    func showMoreIsBounded() async {
        let clock = TestClock<Duration>()
        let page = SearchPage(items: [])
        let complete = store(loaded([fileHit]), clock: clock, page: page)
        await complete.send(.showMoreTapped)

        let first = SearchShortfall.firstOnly(count: Constants.lastStep)
        let atLast = store(
            loaded([fileHit], shortfall: first, limit: Constants.lastStep),
            clock: clock,
            page: page
        )
        await atLast.send(.showMoreTapped)

        let stopped = store(loaded([fileHit], shortfall: .stoppedEarly), clock: clock, page: page)
        await stopped.send(.showMoreTapped)
    }

    @Test("Arrow keys wrap through the hits, down from nothing lands on the first, up on the last")
    func arrowKeysWrap() async {
        let clock = TestClock<Duration>()
        let store = store(
            loaded([folderHit, fileHit, otherHit]),
            clock: clock,
            page: SearchPage(items: [])
        )

        await store.send(.selectionMoved(.down)) { $0.activeIndex = 0 }
        await store.send(.selectionMoved(.up)) { $0.activeIndex = 2 }
        await store.send(.selectionMoved(.down)) { $0.activeIndex = 0 }
        await store.send(.selectionMoved(.down)) { $0.activeIndex = 1 }
        await store.send(.highlighted(nil)) { $0.activeIndex = nil }
        await store.send(.selectionMoved(.up)) { $0.activeIndex = 2 }
    }

    @Test("Arrow keys with no hits do nothing")
    func arrowKeysWithoutHits() async {
        let store = store(loaded([]), clock: TestClock<Duration>(), page: SearchPage(items: []))
        await store.send(.selectionMoved(.down))
        await store.send(.selectionMoved(.up))
    }

    @Test("Return opens the highlighted hit, else the first, else nothing")
    func returnOpensTarget() async {
        let clock = TestClock<Duration>()
        let page = SearchPage(items: [])
        let highlighted = store(
            loaded([folderHit, fileHit], activeIndex: 1),
            clock: clock,
            page: page
        )
        await highlighted.send(.submitted)
        await highlighted.receive(.delegate(.openResult(fileHit)))

        let none = store(loaded([folderHit, fileHit]), clock: clock, page: page)
        await none.send(.submitted)
        await none.receive(.delegate(.openResult(folderHit)))

        let empty = store(loaded([]), clock: clock, page: page)
        await empty.send(.submitted)
    }

    @Test("Return re sending the unchanged text keeps the highlight, so it opens that hit")
    func unchangedQueryKeepsTheHighlight() async {
        let store = store(
            loaded([folderHit, fileHit, otherHit], activeIndex: 2),
            clock: TestClock<Duration>(),
            page: SearchPage(items: [])
        )
        await store.send(.queryChanged(Constants.term))
        await store.send(.submitted)
        await store.receive(.delegate(.openResult(otherHit)))
    }

    @Test("Clicking a hit opens it")
    func clickOpensHit() async {
        let store = store(loaded([folderHit, fileHit]), clock: TestClock<Duration>(), page: SearchPage(items: []))
        await store.send(.resultTapped(otherHit))
        await store.receive(.delegate(.openResult(otherHit)))
    }

    @Test("Closing cancels the search still waiting and tells the parent")
    func closeCancelsPendingSearch() async {
        let clock = TestClock<Duration>()
        let asked = LockIsolated<[Ask]>([])
        let store = store(state(), clock: clock, asked: asked, page: SearchPage(items: [fileHit]))

        await store.send(.queryChanged(Constants.term)) {
            $0.query = Constants.term
            $0.phase = .loading
        }
        await store.send(.closeRequested)
        await store.receive(.delegate(.closed))
        await clock.advance(by: .seconds(1))
        #expect(asked.value.isEmpty)
    }
}
