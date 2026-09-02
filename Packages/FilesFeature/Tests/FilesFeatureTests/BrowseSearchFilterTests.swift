import ComposableArchitecture
import CoreModels
import Foundation
import Testing

@testable import FilesFeature

@MainActor
@Suite
struct BrowseSearchFilterTests {
    private let serverURL = URL(string: "https://cloud.example.com")!

    private func searchingState(_ results: [SearchResultItem]) -> BrowseFeature.State {
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Files")
        state.searchQuery = "a"
        state.searchResults = IdentifiedArray(uniqueElements: results)
        return state
    }

    private let image = SearchResultItem(name: "photo.jpg", path: "", kind: "file")
    private let document = SearchResultItem(name: "report.pdf", path: "", kind: "file")
    private let video = SearchResultItem(name: "clip.mp4", path: "", kind: "file")

    @Test
    func availableCategoriesReflectOnlyTheKindsPresentInResults() {
        let state = searchingState([image, document, video])
        // allCases display order is folder, image, video, audio, document, archive, other.
        #expect(state.availableSearchCategories == [.image, .video, .document])
    }

    @Test
    func togglingACategoryNarrowsTheDisplayedResults() async {
        let store = TestStore(initialState: searchingState([image, document, video])) {
            BrowseFeature()
        }
        store.exhaustivity = .off

        await store.send(.searchCategoryToggled(.image)) {
            $0.selectedSearchCategories = [.image]
        }
        #expect(store.state.displayedSearchResults?.map(\.id) == [image.id])

        // A second category is additive (multi-select).
        await store.send(.searchCategoryToggled(.video)) {
            $0.selectedSearchCategories = [.image, .video]
        }
        #expect(Set(store.state.displayedSearchResults?.map(\.id) ?? []) == [image.id, video.id])
    }

    @Test
    func togglingTheSameCategoryTwiceReturnsToAll() async {
        let store = TestStore(initialState: searchingState([image, document, video])) {
            BrowseFeature()
        }
        store.exhaustivity = .off

        await store.send(.searchCategoryToggled(.image))
        await store.send(.searchCategoryToggled(.image))
        #expect(store.state.selectedSearchCategories.isEmpty)
        #expect(store.state.displayedSearchResults?.count == 3)
    }

    @Test
    func clearingTheFilterResetsToAll() async {
        var state = searchingState([image, document, video])
        state.selectedSearchCategories = [.image]
        let store = TestStore(initialState: state) { BrowseFeature() }
        store.exhaustivity = .off

        await store.send(.searchFilterCleared) {
            $0.selectedSearchCategories = []
        }
        #expect(store.state.displayedSearchResults?.count == 3)
    }

    @Test
    func clearingTheSearchQueryAlsoClearsTheTypeFilter() async {
        var state = searchingState([image, document])
        state.selectedSearchCategories = [.image]
        let store = TestStore(initialState: state) { BrowseFeature() }
        store.exhaustivity = .off

        await store.send(.searchQueryChanged("")) {
            $0.searchQuery = ""
            $0.searchResults = nil
            $0.selectedSearchCategories = []
        }
    }

    @Test
    func theInstantPreFillDoesNotDropASelectedCategoryTheCurrentFolderLacks() async {
        // Regression: the pre-fill only sees the current folder, so pruning the selection against
        // it would wrongly clear a category the backend subtree contains but this folder doesn't.
        let videoHit = SearchResultItem(name: "clip.mp4", path: "Photos/Trips", kind: "file")
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos", title: "Photos")
        state.items = [FileItem(name: "report.pdf", path: "Photos", dateModified: Date(), size: 0, kind: "pdf")]
        state.searchResults = IdentifiedArray(uniqueElements: [videoHit])
        state.selectedSearchCategories = [.video]
        let clock = TestClock()
        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.filesClient.search = { _, _, _, _ in [videoHit] }
        }
        store.exhaustivity = .off

        await store.send(.searchQueryChanged("clip"))
        // The Video filter survives the pre-fill (this folder has only a PDF).
        #expect(store.state.selectedSearchCategories == [.video])
        // Cancel the pending debounced request.
        await store.send(.searchQueryChanged(""))
    }

    @Test
    func aNewResultSetPrunesSelectedCategoriesNoLongerPresent() async {
        var state = searchingState([image, video])
        state.selectedSearchCategories = [.image, .video]
        let store = TestStore(initialState: state) { BrowseFeature() }
        store.exhaustivity = .off

        // The refreshed results contain only a document, so image/video are pruned from the
        // selection instead of stranding the list on an empty, unofferable filter.
        await store.send(.searchResultsResponse(.success([document])))
        #expect(store.state.selectedSearchCategories.isEmpty)
        #expect(store.state.availableSearchCategories == [.document])
        #expect(store.state.displayedSearchResults?.map(\.id) == [document.id])
    }
}
