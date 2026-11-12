import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing

@MainActor
struct SearchScopeDepthTests {
    private let serverURL = URL(string: "https://example.com")!

    private func state(_ path: String, scope: BrowseFeature.SearchScope = .thisFolder) -> BrowseFeature.State {
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: path, title: "T")
        state.searchScope = scope
        return state
    }

    private func searchedPath(from initial: BrowseFeature.State, actions: (TestStoreOf<BrowseFeature>, TestClock<Duration>) async -> Void) async -> String? {
        let clock = TestClock()
        let scopePath = LockIsolated<String?>(nil)
        let store = TestStore(initialState: initial) {
            BrowseFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.filesClient.search = { _, path, _, _ in
                scopePath.setValue(path)
                return []
            }
        }
        store.exhaustivity = .off
        await actions(store, clock)
        return scopePath.value
    }

    @Test
    func theRootCannotBeWidenedBecauseItAlreadySearchesEverywhere() {
        #expect(!state("").canWidenSearch)
        #expect(state("").effectiveSearchScope == .everywhere)
    }

    @Test(arguments: ["Files", "Files/Documents", "Files/Documents/Taxes"])
    func aFolderAtAnyDepthSearchesItselfAndCanBeWidened(path: String) {
        #expect(state(path).effectiveSearchScope == .thisFolder)
        #expect(state(path).canWidenSearch)
    }

    @Test(arguments: ["Files", "Files/Documents/Taxes"])
    func aWidenedSearchRunsEverywhereAndOffersNoFurtherWidening(path: String) {
        let widened = state(path, scope: .everywhere)
        #expect(widened.effectiveSearchScope == .everywhere)
        #expect(!widened.canWidenSearch)
    }

    @Test
    func aFolderSearchRequestsItsOwnSubtree() async {
        let path = await searchedPath(from: state("Files/Documents")) { store, clock in
            await store.send(.searchQueryChanged("tax"))
            await clock.advance(by: .seconds(1))
            await store.receive(\.searchResultsResponse.success)
        }
        #expect(path == "Files/Documents")
    }

    @Test
    func wideningRequestsFromTheRoot() async {
        let path = await searchedPath(from: state("Files/Documents")) { store, clock in
            await store.send(.searchQueryChanged("tax"))
            await clock.advance(by: .seconds(1))
            await store.receive(\.searchResultsResponse.success)
            await store.send(.searchScopeChanged(.everywhere))
            await clock.advance(by: .seconds(1))
            await store.receive(\.searchResultsResponse.success)
        }
        #expect(path == "")
    }

    @Test
    func theRootRequestsFromTheTop() async {
        let path = await searchedPath(from: state("")) { store, clock in
            await store.send(.searchQueryChanged("tax"))
            await clock.advance(by: .seconds(1))
            await store.receive(\.searchResultsResponse.success)
        }
        #expect(path == "")
    }

    @Test
    func clearingTheSearchReturnsAWidenedFolderToItsOwnScope() async {
        var initial = state("Files/Documents", scope: .everywhere)
        initial.searchQuery = "tax"
        let store = TestStore(initialState: initial) {
            BrowseFeature()
        }
        store.exhaustivity = .off

        await store.send(.searchQueryChanged(""))
        #expect(store.state.searchScope == .thisFolder)
        #expect(store.state.canWidenSearch)
    }

    @Test
    func openingAFolderFromWidenedResultsEndsTheWidening() async {
        var initial = state("Files/Documents", scope: .everywhere)
        initial.searchQuery = "tax"
        let store = TestStore(initialState: initial) {
            BrowseFeature()
        }
        store.exhaustivity = .off

        await store.send(.searchResultTapped(SearchResultItem(name: "Taxes", path: "Files/Other", kind: "dir")))
        #expect(store.state.searchScope == .thisFolder)
    }
}
