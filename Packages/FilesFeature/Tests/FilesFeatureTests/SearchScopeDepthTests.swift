import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// Which subtree a search runs over: the root searches everywhere, a folder at any depth searches
/// itself and can be widened to everywhere until the search is cleared or a folder is opened.
@Suite(.isolatedDependencies)
@MainActor
struct SearchScopeDepthTests {
    private enum Constants {
        static let query = "tax"
        static let taxesFolder = "Files/Documents/Taxes"
        static let otherFolder = "Files/Other"
        static let taxes = "Taxes"
    }

    private func state(_ path: String, scope: BrowseFeature.SearchScope = .thisFolder) -> BrowseFeature.State {
        var state = BrowseFixtures.state(path)
        state.searchScope = scope
        return state
    }

    private func searchingStore(
        _ initial: BrowseFeature.State,
        clock: TestClock<Duration>,
        searchedPaths: LockIsolated<[String]>
    ) -> TestStoreOf<BrowseFeature> {
        BrowseFixtures.store(initial) {
            $0.continuousClock = clock
            $0.filesClient.search = { _, path, _, _ in
                searchedPaths.withValue { $0.append(path) }
                return []
            }
        }
    }

    /// Types the query and lets the debounced server search answer with nothing.
    private func searchForQuery(_ store: TestStoreOf<BrowseFeature>, clock: TestClock<Duration>) async {
        await store.send(.searchQueryChanged(Constants.query)) {
            $0.searchQuery = Constants.query
            $0.searchResults = []
            $0.searchPhase = .loading
        }
        await clock.advance(by: FilesClient.searchDebounce)
        await store.receive(\.searchResultsResponse.success) {
            $0.searchAnsweredTerm = Constants.query
            $0.searchPhase = .loaded
        }
    }

    @Test
    func theRootCannotBeWidenedBecauseItAlreadySearchesEverywhere() {
        #expect(!state("").canWidenSearch)
        #expect(state("").effectiveSearchScope == .everywhere)
    }

    @Test(arguments: [TestFolder.files, TestPath.filesDocuments, Constants.taxesFolder])
    func aFolderAtAnyDepthSearchesItselfAndCanBeWidened(path: String) {
        #expect(state(path).effectiveSearchScope == .thisFolder)
        #expect(state(path).canWidenSearch)
    }

    @Test(arguments: [TestFolder.files, Constants.taxesFolder])
    func aWidenedSearchRunsEverywhereAndOffersNoFurtherWidening(path: String) {
        let widened = state(path, scope: .everywhere)
        #expect(widened.effectiveSearchScope == .everywhere)
        #expect(!widened.canWidenSearch)
    }

    @Test
    func aFolderSearchRequestsItsOwnSubtree() async {
        let clock = TestClock()
        let searchedPaths = LockIsolated<[String]>([])
        let store = searchingStore(state(TestPath.filesDocuments), clock: clock, searchedPaths: searchedPaths)

        await searchForQuery(store, clock: clock)
        #expect(searchedPaths.value == [TestPath.filesDocuments])
    }

    @Test
    func wideningRequestsFromTheRoot() async {
        let clock = TestClock()
        let searchedPaths = LockIsolated<[String]>([])
        let store = searchingStore(state(TestPath.filesDocuments), clock: clock, searchedPaths: searchedPaths)

        await searchForQuery(store, clock: clock)
        // The folder's answer was empty, so there is nothing to keep: the instant matches stand in.
        await store.send(.searchScopeChanged(.everywhere)) {
            $0.searchScope = .everywhere
            $0.searchPhase = .loading
            $0.searchAnsweredTerm = nil
        }
        await store.receive(\.searchResultsResponse.success) {
            $0.searchPhase = .loaded
            $0.searchAnsweredTerm = Constants.query
        }
        #expect(searchedPaths.value == [TestPath.filesDocuments, ""])
    }

    @Test
    func theRootRequestsFromTheTop() async {
        let clock = TestClock()
        let searchedPaths = LockIsolated<[String]>([])
        let store = searchingStore(state(""), clock: clock, searchedPaths: searchedPaths)

        await searchForQuery(store, clock: clock)
        #expect(searchedPaths.value == [""])
    }

    @Test
    func clearingTheSearchReturnsAWidenedFolderToItsOwnScope() async {
        var initial = state(TestPath.filesDocuments, scope: .everywhere)
        initial.searchQuery = Constants.query
        let store = BrowseFixtures.store(initial)

        await store.send(.searchQueryChanged("")) {
            $0.searchQuery = ""
            $0.searchScope = .thisFolder
        }
        #expect(store.state.canWidenSearch)
    }

    @Test
    func openingAFolderFromWidenedResultsEndsTheWidening() async {
        var initial = state(TestPath.filesDocuments, scope: .everywhere)
        initial.searchQuery = Constants.query
        let store = BrowseFixtures.store(initial)

        await store.send(.searchResultTapped(SearchResultItem(
            name: Constants.taxes,
            path: Constants.otherFolder,
            kind: SearchResultItem.directoryKind
        ))) {
            $0.searchQuery = ""
            $0.searchScope = .thisFolder
        }
        await store.receive(\.delegate, .openPath(path: "Files/Other/Taxes", title: Constants.taxes))
    }
}
