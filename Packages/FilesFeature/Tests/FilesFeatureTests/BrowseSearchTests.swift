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
struct BrowseSearchTests {
    private enum Constants {
        static let reportTerm = "report"
        static let payslips = "Payslips"
        static let vacation2024 = "Vacation 2024"
        static let zeta = "zeta"
        static let zetas = "zetas"
        static let clip = "clip.mp4"
    }

    // MARK: Recursive backend search, instant client pre-fill

    @Test(
        "Searching this folder fills in matches from the loaded items at once, then asks the server scoped to the folder"
    )
    func thisFolderSearchPreFillsFromLoadedItemsThenHitsTheBackendScopedToTheCurrentDirectory() async {
        let loadedMatch = BrowseFixtures.file(TestFile.vacationPhoto, in: TestFolder.photos)
        let loadedNonMatch = BrowseFixtures.file(TestFile.notes, in: TestFolder.photos)
        let deepHit = BrowseFixtures.deepSearchHit
        let clock = TestClock()
        let scopePath = LockIsolated<[String]>([])
        let store = BrowseFixtures.store(BrowseFixtures.state(
            TestFolder.photos,
            title: TestFolder.photos,
            items: [loadedMatch, loadedNonMatch]
        )) {
            $0.continuousClock = clock
            $0.filesClient.search = { _, path, _, _ in
                scopePath.withValue { $0.append(path) }
                return [deepHit]
            }
        }

        await store.send(.searchQueryChanged(TestSearch.term)) {
            $0.searchQuery = TestSearch.term
            $0.searchResults = [SearchResultItem(
                name: TestFile.vacationPhoto,
                path: TestFolder.photos,
                kind: SearchResultItem.fileKind
            )]
            $0.searchPhase = .loading
        }
        await clock.advance(by: FilesClient.searchDebounce)
        await store.receive(\.searchResultsResponse.success) {
            $0.searchAnsweredTerm = TestSearch.term
            $0.searchPhase = .loaded
            $0.searchResults = [deepHit]
        }
        #expect(scopePath.value == [TestFolder.photos])
    }

    @Test("A query shorter than the server minimum keeps the instant matches and never asks the server")
    func queriesShorterThanTheServerMinimumKeepTheInstantMatchesWithoutASearchRequest() async {
        let clock = TestClock()
        let calls = LockIsolated(0)
        let store = BrowseFixtures.store(BrowseFixtures.state(
            title: TestFolder.files,
            items: [BrowseFixtures.folder(Constants.payslips)]
        )) {
            $0.continuousClock = clock
            $0.filesClient.search = { _, _, _, _ in
                calls.withValue { $0 += 1 }
                return []
            }
        }

        // The backend answers 400 under three characters, so the instant match is all there is.
        await store.send(.searchQueryChanged("pa")) {
            $0.searchQuery = "pa"
            $0.searchResults = [SearchResultItem(
                name: Constants.payslips,
                path: "",
                kind: SearchResultItem.directoryKind
            )]
        }
        await store.receive(\.searchSavedItemsLoaded) {
            $0.searchSavedItems = [:]
        }
        await clock.advance(by: FilesClient.searchDebounce)
        await store.finish()
        #expect(calls.value == 0)
    }

    @Test("Favorites matching the query show at once within the scope, before the server answers")
    func matchingFavoritesShowInstantlyWithinTheScope() async {
        var state = BrowseFixtures.state(TestFolder.photos, title: TestFolder.photos)
        state.favoritePaths = ["Photos/Trips/Vacation 2024", "Work/Vacation Plans", "Photos/Album"]
        let clock = TestClock()
        let store = BrowseFixtures.store(state) {
            $0.continuousClock = clock
            $0.filesClient.search = { _, _, _, _ in [] }
        }

        // "This Folder": only the favorite under Photos, ready to open before the backend answers.
        await store.send(.searchQueryChanged(TestSearch.term)) {
            $0.searchQuery = TestSearch.term
            $0.searchResults = [SearchResultItem(
                name: Constants.vacation2024,
                path: TestSearch.deepHitPath,
                kind: SearchResultItem.directoryKind
            )]
            $0.searchPhase = .loading
        }
        // "Everywhere": every matching favorite. A tap asks at once, replacing the pending search.
        await store.send(.searchScopeChanged(.everywhere)) {
            $0.searchScope = .everywhere
            $0.searchResults = [
                SearchResultItem(
                    name: Constants.vacation2024,
                    path: TestSearch.deepHitPath,
                    kind: SearchResultItem.directoryKind
                ),
                SearchResultItem(
                    name: "Vacation Plans",
                    path: FilesFeatureTestValue.workFolder,
                    kind: SearchResultItem.directoryKind
                ),
            ]
        }
        await store.receive(\.searchResultsResponse.success) {
            $0.searchAnsweredTerm = TestSearch.term
            $0.searchPhase = .loaded
            $0.searchResults = []
        }
    }

    @Test("Sending the same query again changes nothing and does not search again, so results do not flash")
    func reSendingTheSameQueryIsANoOpSoResultsDoNotFlash() async {
        let deepHit = BrowseFixtures.deepSearchHit
        let clock = TestClock()
        let calls = LockIsolated(0)
        let store = BrowseFixtures.store(BrowseFixtures.state(TestFolder.photos, title: TestFolder.photos)) {
            $0.continuousClock = clock
            $0.filesClient.search = { _, _, _, _ in
                calls.withValue { $0 += 1 }
                return [deepHit]
            }
        }

        await store.send(.searchQueryChanged(TestSearch.term)) {
            $0.searchQuery = TestSearch.term
            $0.searchResults = []
            $0.searchPhase = .loading
        }
        await clock.advance(by: FilesClient.searchDebounce)
        await store.receive(\.searchResultsResponse.success) {
            $0.searchAnsweredTerm = TestSearch.term
            $0.searchPhase = .loaded
            $0.searchResults = [deepHit]
        }
        // A focus change or keyboard dismiss re-sends the same text through the binding.
        await store.send(.searchQueryChanged(TestSearch.term))
        await clock.advance(by: FilesClient.searchDebounce)
        await store.finish()
        #expect(calls.value == 1)
    }

    @Test("A whitespace only query counts as empty and never reaches the server")
    func aWhitespaceOnlyQueryIsTreatedAsEmptyAndNeverHitsTheBackend() async {
        let clock = TestClock()
        let calls = LockIsolated(0)
        let store = BrowseFixtures.store {
            $0.continuousClock = clock
            $0.filesClient.search = { _, _, _, _ in
                calls.withValue { $0 += 1 }
                return []
            }
        }

        await store.send(.searchQueryChanged(TestValue.blank)) {
            $0.searchQuery = TestValue.blank
        }
        await clock.advance(by: FilesClient.searchDebounce)
        await store.finish()
        #expect(calls.value == 0)
    }

    @Test("Searching everywhere asks the server from the root, whatever folder is open")
    func everywhereSearchHitsTheBackendFromTheRoot() async {
        var state = BrowseFixtures.state(TestFolder.photos, title: TestFolder.photos)
        state.searchScope = .everywhere
        let result = SearchResultItem(
            name: TestFile.vacationPhoto,
            path: TestFolder.photos,
            kind: SearchResultItem.fileKind
        )
        let clock = TestClock()
        let scopePath = LockIsolated<[String]>([])
        let store = BrowseFixtures.store(state) {
            $0.continuousClock = clock
            $0.filesClient.search = { _, path, _, _ in
                scopePath.withValue { $0.append(path) }
                return [result]
            }
        }

        // No loaded items, so the pre-fill is empty; the network result fills the list.
        await store.send(.searchQueryChanged(TestSearch.term)) {
            $0.searchQuery = TestSearch.term
            $0.searchResults = []
            $0.searchPhase = .loading
        }
        await clock.advance(by: FilesClient.searchDebounce)
        await store.receive(\.searchResultsResponse.success) {
            $0.searchAnsweredTerm = TestSearch.term
            $0.searchPhase = .loaded
            $0.searchResults = [result]
        }
        #expect(scopePath.value == [""])
    }

    @Test("Clearing the query before the debounce ends cancels the pending search and clears the results")
    func clearingTheSearchQueryCancelsAnInFlightSearchAndClearsResults() async {
        let clock = TestClock()
        let calls = LockIsolated(0)
        let store = BrowseFixtures.store(BrowseFixtures.state(items: [BrowseFixtures.file(TestFile.vacationPhoto)])) {
            $0.continuousClock = clock
            $0.filesClient.search = { _, _, _, _ in
                calls.withValue { $0 += 1 }
                return []
            }
        }

        await store.send(.searchQueryChanged(TestSearch.term)) {
            $0.searchQuery = TestSearch.term
            $0.searchResults = [SearchResultItem(
                name: TestFile.vacationPhoto,
                path: "",
                kind: SearchResultItem.fileKind
            )]
            $0.searchPhase = .loading
        }
        await store.send(.searchQueryChanged("")) {
            $0.searchQuery = ""
            $0.searchResults = nil
            $0.searchPhase = .idle
        }
        await clock.advance(by: FilesClient.searchDebounce)
        await store.finish()
        #expect(calls.value == 0)
    }

    @Test("Retyping before the debounce ends searches only for the latest text")
    func rapidRetypingOnlyDeliversResultsForTheLatestQuery() async {
        // Regression: cancelling the previous keystroke's debounced request must leave only the latest one.
        let result = SearchResultItem(name: "vacation-2.jpg", path: "Trips", kind: SearchResultItem.fileKind)
        let clock = TestClock()
        let queries = LockIsolated<[String]>([])
        let store = BrowseFixtures.store(BrowseFixtures.state(items: [BrowseFixtures.file(TestFile.vacationPhoto)])) {
            $0.continuousClock = clock
            $0.filesClient.search = { _, _, query, _ in
                queries.withValue { $0.append(query) }
                return [result]
            }
        }

        // Both at least the server's three characters, so both would really be sent.
        await store.send(.searchQueryChanged(TestSearch.term)) {
            $0.searchQuery = TestSearch.term
            $0.searchResults = [SearchResultItem(
                name: TestFile.vacationPhoto,
                path: "",
                kind: SearchResultItem.fileKind
            )]
            $0.searchPhase = .loading
        }
        await store.send(.searchQueryChanged(TestSearch.longerTerm)) {
            $0.searchQuery = TestSearch.longerTerm
        }
        await clock.advance(by: FilesClient.searchDebounce)
        await store.receive(\.searchResultsResponse.success) {
            $0.searchAnsweredTerm = TestSearch.longerTerm
            $0.searchPhase = .loaded
            $0.searchResults = [result]
        }
        await store.finish()
        #expect(queries.value == [TestSearch.longerTerm])
    }

    @Test("A failed search says so with Retry instead of looking like no matches")
    func aFailedSearchSaysSoInsteadOfLookingLikeNoMatches() async {
        let clock = TestClock()
        let store = BrowseFixtures.store {
            $0.continuousClock = clock
            $0.filesClient.search = { _, _, _, _ in throw FilesClientError.rateLimited }
        }

        await store.send(.searchQueryChanged(TestSearch.term)) {
            $0.searchQuery = TestSearch.term
            $0.searchResults = []
            $0.searchPhase = .loading
        }
        await clock.advance(by: FilesClient.searchDebounce)
        await store.receive(\.searchResultsResponse.failure) {
            $0.searchPhase = .failed(L10n.Browse.searchFailed)
        }
        #expect(store.state.searchFailureMessage == L10n.Browse.searchFailed)
        #expect(store.state.fileActionErrorMessage == nil)
    }

    @Test("Switching to Everywhere with a query already typed searches at once, without the typing wait")
    func changingScopeToEverywhereWithAnExistingQueryTriggersANetworkSearch() async {
        var state = BrowseFixtures.state()
        state.searchQuery = TestSearch.term
        let result = SearchResultItem(
            name: TestFile.vacationPhoto,
            path: TestFolder.photos,
            kind: SearchResultItem.fileKind
        )
        let clock = TestClock()
        let store = BrowseFixtures.store(state) {
            $0.continuousClock = clock
            $0.filesClient.search = { _, _, _, _ in [result] }
        }

        await store.send(.searchScopeChanged(.everywhere)) {
            $0.searchScope = .everywhere
            $0.searchResults = []
            $0.searchPhase = .loading
        }
        await store.receive(\.searchResultsResponse.success) {
            $0.searchPhase = .loaded
            $0.searchAnsweredTerm = TestSearch.term
            $0.searchResults = [result]
        }
    }

    // MARK: Ranking, show more, shortfalls

    @Test("The server's ranking is kept, Show more widens it without a debounce, and a new query starts over")
    func searchKeepsTheServerRankingAndShowMoreWidensIt() async {
        var state = BrowseFixtures.state()
        state.searchScope = .everywhere
        let closest = SearchResultItem(
            name: Constants.zeta,
            path: "",
            kind: SearchResultItem.directoryKind,
            isNameMatch: true
        )
        let content = SearchResultItem(
            name: "alpha.txt",
            path: TestFolder.docs,
            kind: SearchResultItem.fileKind,
            matchLine: Constants.zeta,
            matchLineNumber: 3,
            isContentMatch: true
        )
        let more = SearchResultItem(
            name: "beta.txt",
            path: TestFolder.docs,
            kind: SearchResultItem.fileKind,
            isContentMatch: true
        )
        let limits = LockIsolated<[Int?]>([])
        let clock = TestClock()
        let store = BrowseFixtures.store(state) {
            $0.continuousClock = clock
            $0.filesClient.search = { _, _, _, limit in
                limits.withValue { $0.append(limit) }
                return limit == 100
                    ? SearchPage(items: [closest, content], isComplete: false, limit: 100)
                    : SearchPage(items: [closest, content, more], limit: 300)
            }
        }

        await store.send(.searchQueryChanged(Constants.zeta)) {
            $0.searchQuery = Constants.zeta
            $0.searchResults = []
            $0.searchPhase = .loading
        }
        await clock.advance(by: FilesClient.searchDebounce)
        await store.receive(\.searchResultsResponse.success) {
            $0.searchAnsweredTerm = Constants.zeta
            $0.searchPhase = .loaded
            $0.searchResults = [closest, content]
            $0.searchShortfall = .firstOnly(count: 100)
        }
        #expect(store.state.canShowMoreSearchResults)

        // Widens straight away, no debounce, and keeps the results on screen meanwhile.
        await store.send(.searchShowMoreTapped) {
            $0.searchLimit = 300
            $0.searchPhase = .loading
        }
        await store.receive(\.searchResultsResponse.success) {
            $0.searchAnsweredTerm = Constants.zeta
            $0.searchPhase = .loaded
            $0.searchResults = [closest, content, more]
            $0.searchShortfall = nil
        }
        #expect(limits.value == [100, 300])

        // A new query starts over from the first step and waits out the debounce again, keeping
        // the earlier answer on screen until its own arrives.
        await store.send(.searchQueryChanged(Constants.zetas)) {
            $0.searchQuery = Constants.zetas
            $0.searchLimit = 100
            $0.searchPhase = .loading
        }
        await clock.advance(by: FilesClient.searchDebounce)
        await store.receive(\.searchResultsResponse.success) {
            $0.searchAnsweredTerm = Constants.zetas
            $0.searchPhase = .loaded
            $0.searchResults = [closest, content]
            $0.searchShortfall = .firstOnly(count: 100)
        }
        #expect(limits.value == [100, 300, 100])
    }

    @Test("A search that stopped at its time limit says so, and cannot be widened")
    func aSearchStoppedAtItsTimeLimitSaysSo() async {
        var state = BrowseFixtures.state()
        state.searchScope = .everywhere
        let hit = SearchResultItem(
            name: TestFile.vacationPhoto,
            path: TestFolder.photos,
            kind: SearchResultItem.fileKind,
            isNameMatch: true
        )
        let clock = TestClock()
        let store = BrowseFixtures.store(state) {
            $0.continuousClock = clock
            $0.filesClient.search = { _, _, _, _ in SearchPage(
                items: [hit],
                isTruncated: true,
                isComplete: true,
                limit: 100
            ) }
        }

        await store.send(.searchQueryChanged(TestSearch.term)) {
            $0.searchQuery = TestSearch.term
            $0.searchResults = []
            $0.searchPhase = .loading
        }
        await clock.advance(by: FilesClient.searchDebounce)
        await store.receive(\.searchResultsResponse.success) {
            $0.searchAnsweredTerm = TestSearch.term
            $0.searchPhase = .loaded
            $0.searchResults = [hit]
            $0.searchShortfall = .stoppedEarly
        }
        #expect(!store.state.canShowMoreSearchResults)
    }

    @Test("A term under three characters is flagged as too short for the server, an empty one is not")
    func aTermTooShortForTheServerIsFlagged() {
        var state = BrowseFixtures.state()
        state.searchQuery = " p "
        #expect(state.isSearchTermTooShort)
        state.searchQuery = "pay"
        #expect(!state.isSearchTermTooShort)
        state.searchQuery = ""
        #expect(!state.isSearchTermTooShort)
    }

    // MARK: Opening a result

    @Test("Show in Enclosing Folder ends the search and opens the folder that holds the result")
    func showInEnclosingFolderEndsTheSearchAndOpensTheFolder() async {
        var state = BrowseFixtures.state()
        state.searchQuery = Constants.reportTerm
        let result = SearchResultItem(
            name: TestFile.report,
            path: TestPath.documentsWork,
            kind: SearchResultItem.fileKind,
            isNameMatch: true
        )
        let store = BrowseFixtures.store(state)

        await store.send(.searchResultEnclosingFolderTapped(result)) {
            $0.searchQuery = ""
        }
        await store.receive(.delegate(.openPath(path: TestPath.documentsWork, title: FilesFeatureTestValue.workFolder)))
    }

    @Test("Show in Enclosing Folder on a hit at the top opens the root under its own title")
    func showInEnclosingFolderAtTheTopOpensTheRoot() async {
        var state = BrowseFixtures.state(TestFolder.photos)
        state.searchQuery = Constants.reportTerm
        state.searchScope = .everywhere
        let result = SearchResultItem(
            name: TestFile.report,
            path: "",
            kind: SearchResultItem.fileKind,
            isNameMatch: true
        )
        let store = BrowseFixtures.store(state)

        await store.send(.searchResultEnclosingFolderTapped(result)) {
            $0.searchQuery = ""
            $0.searchScope = .thisFolder
        }
        await store.receive(.delegate(.openPath(path: "", title: L10n.Browse.navigationTitle)))
    }

    @Test("Opening a folder from the results ends the search")
    func openingAFolderFromSearchEndsTheSearch() async {
        let result = SearchResultItem(name: Constants.payslips, path: "", kind: SearchResultItem.directoryKind)
        var state = BrowseFixtures.state()
        state.searchQuery = "pay"
        state.searchResults = [result]
        state.searchPhase = .loading
        let store = BrowseFixtures.store(state)

        await store.send(.searchResultTapped(result)) {
            $0.searchQuery = ""
            $0.searchResults = nil
            $0.searchPhase = .idle
        }
        await store.receive(.delegate(.openPath(path: "Payslips", title: "Payslips")))
    }

    @Test("A folder result at the root builds its path from an empty parent")
    func searchResultTappedOnADirectoryAtTheRootBuildsThePathFromAnEmptyParent() async {
        let store = BrowseFixtures.store()

        await store.send(.searchResultTapped(SearchResultItem(
            name: TestFolder.docs,
            path: "",
            kind: SearchResultItem.directoryKind
        )))
        await store.receive(.delegate(.openPath(path: TestFolder.docs, title: TestFolder.docs)))
    }

    @Test("A file result opens its preview as a tapped row, with the type taken from its name")
    func searchResultTappedOnAFileOpensThePreviewViaRowTapped() async {
        let store = BrowseFixtures.store()
        let opened = FileItem(
            name: Constants.clip,
            path: TestFolder.media,
            dateModified: MockDate.date,
            size: 0,
            kind: TestKind.video
        )

        await store.send(.searchResultTapped(SearchResultItem(
            name: Constants.clip,
            path: TestFolder.media,
            kind: SearchResultItem.fileKind
        )))
        await store.receive(.rowTapped(opened)) {
            $0.previewItem = opened
        }
    }
}
