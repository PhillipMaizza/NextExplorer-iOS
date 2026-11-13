import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

/// What Browse shows while a search answers: an earlier answer stays until the newer term's
/// arrives, the instant matches stand in when there is none, and a failure is said with Retry.
@Suite(.isolatedDependencies)
@MainActor
struct BrowseSearchAnswerTests {
    private enum Constants {
        static let term = "vac"
        static let longerTerm = "vaca"
        static let shortTerm = "va"
        static let refreshedName = "vacation-3.jpg"
    }

    private let photo = BrowseFixtures.file(TestFile.vacationPhoto, in: TestFolder.photos)
    private let deepHit = SearchResultItem(name: "vacation-2.jpg", path: "Photos/Trips", kind: "file", isNameMatch: true)
    private let newerHit = SearchResultItem(name: Constants.refreshedName, path: TestFolder.photos, kind: "file", isNameMatch: true)

    private var photoMatch: SearchResultItem {
        SearchResultItem(name: TestFile.vacationPhoto, path: TestFolder.photos, kind: "file")
    }

    /// The photos folder, loaded with `photo`, showing the server's answer `deepHit` to `term`.
    private func answeredState(answer: [SearchResultItem]? = nil) -> BrowseFeature.State {
        var state = BrowseFixtures.state(TestFolder.photos, title: TestFolder.photos, items: [photo])
        state.phase = .loaded
        state.searchQuery = Constants.term
        state.searchResults = IdentifiedArray(uniqueElements: answer ?? [deepHit])
        state.searchAnsweredTerm = Constants.term
        state.searchPhase = .loaded
        return state
    }

    private func store(
        _ state: BrowseFeature.State,
        clock: TestClock<Duration>,
        answer: @escaping @Sendable (String) throws -> SearchPage
    ) -> TestStoreOf<BrowseFeature> {
        BrowseFixtures.store(state) {
            $0.continuousClock = clock
            $0.filesClient.search = { _, _, query, _ in try answer(query) }
        }
    }

    @Test("A newer term keeps the earlier answer on screen until its own arrives")
    func aNewerTermKeepsTheEarlierAnswer() async {
        let clock = TestClock()
        let newerHit = newerHit
        let store = store(answeredState(), clock: clock) { _ in [newerHit] }

        await store.send(.searchQueryChanged(Constants.longerTerm)) {
            $0.searchQuery = Constants.longerTerm
            $0.searchPhase = .loading
        }
        #expect(store.state.searchResults == [deepHit])
        #expect(store.state.isSearchPending)

        await clock.advance(by: FilesClient.searchDebounce)
        await store.receive(\.searchResultsResponse.success) {
            $0.searchPhase = .loaded
            $0.searchResults = [newerHit]
            $0.searchAnsweredTerm = Constants.longerTerm
        }
    }

    @Test("An earlier answer that found nothing gives way to the newer term's instant matches")
    func anEmptyEarlierAnswerGivesWayToInstantMatches() async {
        let clock = TestClock()
        let store = store(answeredState(answer: []), clock: clock) { _ in [] }

        await store.send(.searchQueryChanged(Constants.longerTerm)) {
            $0.searchQuery = Constants.longerTerm
            $0.searchPhase = .loading
            $0.searchResults = [photoMatch]
            $0.searchAnsweredTerm = nil
        }
        await clock.advance(by: FilesClient.searchDebounce)
        await store.receive(\.searchResultsResponse.success) {
            $0.searchPhase = .loaded
            $0.searchResults = []
            $0.searchAnsweredTerm = Constants.longerTerm
        }
    }

    @Test("Shortening the term below what the server searches swaps the answer for the instant matches")
    func aShortTermSwapsTheAnswerForInstantMatches() async {
        let store = store(answeredState(), clock: TestClock()) { _ in [] }

        await store.send(.searchQueryChanged(Constants.shortTerm)) {
            $0.searchQuery = Constants.shortTerm
            $0.searchPhase = .idle
            $0.searchResults = [photoMatch]
            $0.searchAnsweredTerm = nil
        }
    }

    @Test("A failure for a newer term drops the earlier answer for its instant matches and offers Retry")
    func aFailureForANewerTermDropsTheEarlierAnswer() async {
        let clock = TestClock()
        var state = answeredState()
        state.searchShortfall = .firstOnly(count: 100)
        let store = store(state, clock: clock) { _ in throw FilesClientError.offline }

        await store.send(.searchQueryChanged(Constants.longerTerm)) {
            $0.searchQuery = Constants.longerTerm
            $0.searchPhase = .loading
        }
        await clock.advance(by: FilesClient.searchDebounce)
        await store.receive(\.searchResultsResponse.failure) {
            $0.searchPhase = .failed(L10n.Browse.searchFailed)
            $0.searchResults = [photoMatch]
            $0.searchAnsweredTerm = nil
            $0.searchShortfall = nil
        }
        #expect(store.state.searchFailureMessage == L10n.Browse.searchFailed)
    }

    @Test("A failed refresh keeps this term's own answer on screen and says it failed")
    func aFailedRefreshKeepsTheAnswer() async {
        let store = store(answeredState(), clock: TestClock()) { _ in throw FilesClientError.offline }

        await store.send(.searchRetryTapped) {
            $0.searchPhase = .loading
        }
        await store.receive(\.searchResultsResponse.failure) {
            $0.searchPhase = .failed(L10n.Browse.searchFailed)
        }
        #expect(store.state.searchResults == [deepHit])
    }

    @Test("Retry asks again at once, and an answer clears the failure")
    func retryAsksAgainAtOnce() async {
        var state = answeredState()
        state.searchPhase = .failed(L10n.Browse.searchFailed)
        let newerHit = newerHit
        let store = store(state, clock: TestClock()) { _ in [newerHit] }

        await store.send(.searchRetryTapped) {
            $0.searchPhase = .loading
        }
        await store.receive(\.searchResultsResponse.success) {
            $0.searchPhase = .loaded
            $0.searchResults = [newerHit]
        }
        #expect(store.state.searchFailureMessage == nil)
    }

    @Test("A session that expired during a search says so instead of blaming the connection")
    func anExpiredSessionSaysSo() async {
        let clock = TestClock()
        let store = store(answeredState(), clock: clock) { _ in throw FilesClientError.sessionExpired }

        await store.send(.searchRetryTapped) {
            $0.searchPhase = .loading
        }
        await store.receive(\.searchResultsResponse.failure) {
            $0.searchPhase = .failed(FilesClientError.sessionExpired.userMessage)
        }
    }

    @Test("Clearing the search after a failure forgets it")
    func clearingTheSearchForgetsTheFailure() async {
        var state = answeredState()
        state.searchPhase = .failed(L10n.Browse.searchFailed)
        let store = store(state, clock: TestClock()) { _ in [] }

        await store.send(.searchQueryChanged("")) {
            $0.searchQuery = ""
            $0.searchPhase = .idle
            $0.searchResults = nil
            $0.searchAnsweredTerm = nil
        }
        #expect(store.state.searchFailureMessage == nil)
    }

    @Test("The footer says a failure first, then a short term, then a partial answer")
    func theFooterSaysTheFailureFirst() {
        #expect(SearchStatusFooter.message(failure: L10n.Browse.searchFailed, isTooShort: true, shortfall: .stoppedEarly) == L10n.Browse.searchFailed)
        #expect(SearchStatusFooter.message(isTooShort: true, shortfall: .stoppedEarly) == SearchStatusFooter.tooShortMessage)
        #expect(SearchStatusFooter.message(isTooShort: false, shortfall: .stoppedEarly) == L10n.Browse.searchStoppedEarly)
        #expect(SearchStatusFooter.message(isTooShort: false, shortfall: nil) == nil)
    }
}
