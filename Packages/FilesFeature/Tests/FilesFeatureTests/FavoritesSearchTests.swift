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

        await clock.advance(by: .seconds(1))
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
        await clock.advance(by: .seconds(1))
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
        await clock.advance(by: .seconds(1))
        await store.finish()
    }
}
