import ComposableArchitecture
import CoreModels
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// The file type filter over search results: which categories are offered, how toggling narrows the
/// list, and when a selected category is dropped.
@Suite(.isolatedDependencies)
@MainActor
struct BrowseSearchFilterTests {
    private let image = SearchResultItem(name: TestFile.photo, path: "", kind: "file")
    private let document = SearchResultItem(name: TestFile.report, path: "", kind: "file")
    private let video = SearchResultItem(name: "clip.mp4", path: "", kind: "file")

    private func searchingState(_ results: [SearchResultItem]) -> BrowseFeature.State {
        var state = BrowseFixtures.state("", title: TestFolder.files)
        state.searchQuery = "a"
        state.searchResults = IdentifiedArray(uniqueElements: results)
        return state
    }

    @Test("The categories offered are only the kinds present in the results, in display order")
    func availableCategoriesReflectOnlyTheKindsPresentInResults() {
        let state = searchingState([image, document, video])

        #expect(state.availableSearchCategories == [.image, .video, .document])
    }

    @Test("Toggling a category narrows the displayed results, and a second category adds to it")
    func togglingACategoryNarrowsTheDisplayedResults() async {
        let store = BrowseFixtures.store(searchingState([image, document, video]))

        await store.send(.searchCategoryToggled(.image)) {
            $0.selectedSearchCategories = [.image]
        }
        #expect(store.state.displayedSearchResults?.map(\.id) == [image.id])

        await store.send(.searchCategoryToggled(.video)) {
            $0.selectedSearchCategories = [.image, .video]
        }
        #expect(Set(store.state.displayedSearchResults?.map(\.id) ?? []) == [image.id, video.id])
    }

    @Test("Toggling the same category twice shows every result again")
    func togglingTheSameCategoryTwiceReturnsToAll() async {
        let store = BrowseFixtures.store(searchingState([image, document, video]))

        await store.send(.searchCategoryToggled(.image)) {
            $0.selectedSearchCategories = [.image]
        }
        await store.send(.searchCategoryToggled(.image)) {
            $0.selectedSearchCategories = []
        }
        #expect(store.state.displayedSearchResults?.count == 3)
    }

    @Test("Clearing the filter shows every result again")
    func clearingTheFilterResetsToAll() async {
        var state = searchingState([image, document, video])
        state.selectedSearchCategories = [.image]
        let store = BrowseFixtures.store(state)

        await store.send(.searchFilterCleared) {
            $0.selectedSearchCategories = []
        }
        #expect(store.state.displayedSearchResults?.count == 3)
    }

    @Test("Clearing the search query also clears the type filter")
    func clearingTheSearchQueryAlsoClearsTheTypeFilter() async {
        var state = searchingState([image, document])
        state.selectedSearchCategories = [.image]
        let store = BrowseFixtures.store(state)

        await store.send(.searchQueryChanged("")) {
            $0.searchQuery = ""
            $0.searchResults = nil
            $0.selectedSearchCategories = []
        }
    }

    @Test("The instant pre-fill keeps a selected category the current folder lacks, and so does the server answer")
    func theInstantPreFillDoesNotDropASelectedCategoryTheCurrentFolderLacks() async {
        // The pre-fill only sees the current folder, so pruning the selection against it would
        // wrongly clear a category that the server's subtree contains and this folder does not.
        let videoHit = SearchResultItem(name: "clip.mp4", path: "Photos/Trips", kind: "file")
        var state = BrowseFixtures.state("Photos", title: "Photos", items: [BrowseFixtures.file(TestFile.report, in: "Photos")])
        state.selectedSearchCategories = [.video]
        let clock = TestClock()
        let store = BrowseFixtures.store(state) {
            $0.continuousClock = clock
            $0.filesClient.search = { _, _, _, _ in [videoHit] }
        }

        await store.send(.searchQueryChanged("clip")) {
            $0.searchQuery = "clip"
            $0.searchResults = []
            $0.isSearchingRemotely = true
        }
        await clock.advance(by: BrowseFeature.Constants.searchDebounce)
        await store.receive(\.searchResultsResponse.success) {
            $0.isSearchingRemotely = false
            $0.searchResults = [videoHit]
        }
        #expect(store.state.selectedSearchCategories == [.video])
        #expect(store.state.displayedSearchResults?.map(\.id) == [videoHit.id])
    }

    @Test("A new result set drops the selected categories it no longer contains")
    func aNewResultSetPrunesSelectedCategoriesNoLongerPresent() async {
        var state = searchingState([image, video])
        state.selectedSearchCategories = [.image, .video]
        let store = BrowseFixtures.store(state)

        // Image and video are pruned instead of stranding the list on an empty, unofferable filter.
        await store.send(.searchResultsResponse(.success([document]))) {
            $0.searchResults = [document]
            $0.selectedSearchCategories = []
        }
        #expect(store.state.availableSearchCategories == [.document])
        #expect(store.state.displayedSearchResults?.map(\.id) == [document.id])
    }
}
