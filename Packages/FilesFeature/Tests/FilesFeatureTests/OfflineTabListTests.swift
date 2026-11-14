import ComposableArchitecture
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// Search, sort and multi select of the Downloads tab. Pure state, so no effect ever runs.
@Suite(.isolatedDependencies)
@MainActor
struct OfflineTabListTests {
    private enum Constants {
        static let zebra = "zebra.pdf"
        static let apple = "Apple.pdf"
        static let mango = "mango.txt"
        static let folderPath = "/tmp/Downloads/"
        static let pinnedFolder = TestFolder.documents
        static let pinnedFile = TestPath.photosPhoto
    }

    private func download(_ name: String, size: Int64, modifiedOffset: TimeInterval) -> LocalDownload {
        LocalDownload(
            url: URL(fileURLWithPath: "\(Constants.folderPath)\(name)"),
            fileName: name,
            size: size,
            modifiedDate: MockDate.date.addingTimeInterval(modifiedOffset)
        )
    }

    /// Zebra is the biggest and oldest, Apple the smallest and newest, Mango sits between on both.
    private var zebra: LocalDownload {
        download(Constants.zebra, size: 900, modifiedOffset: 0)
    }

    private var apple: LocalDownload {
        download(Constants.apple, size: 100, modifiedOffset: 200)
    }

    private var mango: LocalDownload {
        download(Constants.mango, size: 500, modifiedOffset: 100)
    }

    private func state(searchQuery: String = "") -> OfflineTabFeature.State {
        var state = OfflineTabFeature.State()
        state.downloads = [zebra, apple, mango]
        state.searchQuery = searchQuery
        return state
    }

    struct SortCase: Sendable {
        let option: OfflineTabFeature.SortOption
        let direction: BrowseFeature.SortDirection
        let expected: [String]
    }

    nonisolated static let sortCases = [
        SortCase(option: .name, direction: .ascending, expected: [Constants.apple, Constants.mango, Constants.zebra]),
        SortCase(option: .name, direction: .descending, expected: [Constants.zebra, Constants.mango, Constants.apple]),
        SortCase(option: .size, direction: .ascending, expected: [Constants.apple, Constants.mango, Constants.zebra]),
        SortCase(option: .size, direction: .descending, expected: [Constants.zebra, Constants.mango, Constants.apple]),
        SortCase(
            option: .dateAdded,
            direction: .ascending,
            expected: [Constants.zebra, Constants.mango, Constants.apple]
        ),
        SortCase(
            option: .dateAdded,
            direction: .descending,
            expected: [Constants.apple, Constants.mango, Constants.zebra]
        ),
    ]

    @Test(arguments: sortCases)
    func downloadsAreOrderedByTheChosenOptionAndDirection(_ testCase: SortCase) {
        var state = state()
        state.sortOption = testCase.option
        state.sortDirection = testCase.direction

        #expect(state.displayedDownloads.map(\.fileName) == testCase.expected)
    }

    @Test
    func theNameSortIgnoresCase() {
        #expect(state().displayedDownloads.map(\.fileName).first == Constants.apple)
    }

    struct SearchCase: Sendable {
        let query: String
        let expected: [String]
    }

    nonisolated static let searchCases = [
        SearchCase(query: "", expected: [Constants.apple, Constants.mango, Constants.zebra]),
        SearchCase(query: "PDF", expected: [Constants.apple, Constants.zebra]),
        SearchCase(query: "ang", expected: [Constants.mango]),
        SearchCase(query: "nothing", expected: []),
    ]

    @Test(arguments: searchCases)
    func searchKeepsOnlyNamesContainingTheQueryWhateverTheCase(_ testCase: SearchCase) {
        #expect(state(searchQuery: testCase.query).displayedDownloads.map(\.fileName) == testCase.expected)
    }

    @Test
    func searchSortAndDirectionAreAppliedTogether() {
        var state = state(searchQuery: "pdf")
        state.sortOption = .size
        state.sortDirection = .descending

        #expect(state.displayedDownloads.map(\.fileName) == [Constants.zebra, Constants.apple])
    }

    @Test
    func theReducerStoresTheSearchQuerySortOptionAndDirection() async {
        let store = TestStore(initialState: OfflineTabFeature.State()) { OfflineTabFeature() }

        await store.send(.searchQueryChanged("pdf")) { $0.searchQuery = "pdf" }
        await store.send(.sortOptionChanged(.size)) { $0.sortOption = .size }
        await store.send(.sortDirectionChanged(.descending)) { $0.sortDirection = .descending }
    }

    // MARK: selection

    @Test
    func togglingSelectModeAlwaysStartsFromAnEmptySelection() async {
        var initial = state()
        initial.selectedDownloadIDs = [zebra.id]
        let store = TestStore(initialState: initial) { OfflineTabFeature() }

        await store.send(.selectModeToggled) {
            $0.isSelecting = true
            $0.selectedDownloadIDs = []
        }
        await store.send(.itemSelectionToggled(apple.id)) { $0.selectedDownloadIDs = [apple.id] }
        await store.send(.selectModeToggled) {
            $0.isSelecting = false
            $0.selectedDownloadIDs = []
        }
    }

    @Test
    func tappingAnItemTwiceSelectsThenDeselectsIt() async {
        let store = TestStore(initialState: state()) { OfflineTabFeature() }

        await store.send(.itemSelectionToggled(zebra.id)) { $0.selectedDownloadIDs = [zebra.id] }
        await store.send(.itemSelectionToggled(apple.id)) { $0.selectedDownloadIDs = [zebra.id, apple.id] }
        await store.send(.itemSelectionToggled(zebra.id)) { $0.selectedDownloadIDs = [apple.id] }
    }

    @Test
    func selectAllOnlySelectsWhatTheSearchStillShows() async {
        let store = TestStore(initialState: state(searchQuery: "pdf")) { OfflineTabFeature() }

        await store.send(.selectAllTapped(pinnedPaths: [])) { $0.selectedDownloadIDs = [zebra.id, apple.id] }
        await store.send(.deselectAllTapped) { $0.selectedDownloadIDs = [] }
    }

    // MARK: pinned items in the selection

    @Test("A pinned item is picked and unpicked next to the saved files")
    func tappingAPinnedItemTwiceSelectsThenDeselectsIt() async {
        let store = TestStore(initialState: state()) { OfflineTabFeature() }

        await store.send(.pinnedSelectionToggled(path: Constants.pinnedFolder)) {
            $0.selectedPinnedPaths = [Constants.pinnedFolder]
        }
        await store.send(.itemSelectionToggled(zebra.id)) { $0.selectedDownloadIDs = [zebra.id] }
        #expect(store.state.selectedCount == 2)
        await store.send(.pinnedSelectionToggled(path: Constants.pinnedFolder)) { $0.selectedPinnedPaths = [] }
        #expect(store.state.selectedCount == 1)
    }

    @Test("Select All picks the pinned items the tab shows along with the saved files")
    func selectAllPicksPinnedItemsToo() async {
        let store = TestStore(initialState: state(searchQuery: "pdf")) { OfflineTabFeature() }

        await store.send(.selectAllTapped(pinnedPaths: [Constants.pinnedFile])) {
            $0.selectedDownloadIDs = [zebra.id, apple.id]
            $0.selectedPinnedPaths = [Constants.pinnedFile]
        }
        await store.send(.deselectAllTapped) {
            $0.selectedDownloadIDs = []
            $0.selectedPinnedPaths = []
        }
    }

    @Test("Select All with nothing pinned on screen picks no pinned item")
    func selectAllWithNoPinnedItems() async {
        let store = TestStore(initialState: state(searchQuery: "pdf")) { OfflineTabFeature() }

        await store.send(.selectAllTapped(pinnedPaths: [])) { $0.selectedDownloadIDs = [zebra.id, apple.id] }
        #expect(store.state.selectedPinnedPaths.isEmpty)
    }

    @Test("Leaving and entering select mode drops picked pinned items")
    func togglingSelectModeDropsPinnedItems() async {
        var initial = state()
        initial.isSelecting = true
        initial.selectedPinnedPaths = [Constants.pinnedFolder]
        let store = TestStore(initialState: initial) { OfflineTabFeature() }

        await store.send(.selectModeToggled) {
            $0.isSelecting = false
            $0.selectedPinnedPaths = []
        }
    }

    @Test("Removing the picked pinned items from offline ends select mode")
    func removingPinnedItemsEndsSelectMode() async {
        var initial = state()
        initial.isSelecting = true
        initial.selectedPinnedPaths = [Constants.pinnedFolder, Constants.pinnedFile]
        initial.selectedDownloadIDs = [zebra.id]
        let store = TestStore(initialState: initial) { OfflineTabFeature() }

        await store.send(.pinnedSelectionRemoved) {
            $0.isSelecting = false
            $0.selectedPinnedPaths = []
            $0.selectedDownloadIDs = []
        }
    }

    @Test("A picked pinned item no longer shown leaves the selection; the others stay")
    func pinnedItemsNoLongerShownLeaveTheSelection() async {
        var initial = state()
        initial.isSelecting = true
        initial.selectedPinnedPaths = [Constants.pinnedFolder, Constants.pinnedFile]
        let store = TestStore(initialState: initial) { OfflineTabFeature() }

        await store.send(.shownPinnedPathsChanged([Constants.pinnedFile, TestFolder.inbox])) {
            $0.selectedPinnedPaths = [Constants.pinnedFile]
        }
        #expect(store.state.selectedCount == 1)
        await store.send(.shownPinnedPathsChanged([])) { $0.selectedPinnedPaths = [] }
    }

    @Test("Deleting the saved files also clears picked pinned items as select mode ends")
    func bulkDeleteEndsSelectModeWithPinnedItems() async {
        var initial = state()
        initial.isSelecting = true
        initial.selectedPinnedPaths = [Constants.pinnedFile]
        initial.selectedDownloadIDs = [zebra.id]
        let store = TestStore(initialState: initial) { OfflineTabFeature() }

        await store.send(.bulkDeleteResponse([zebra.id])) {
            $0.downloads.remove(id: zebra.id)
            $0.isSelecting = false
            $0.selectedPinnedPaths = []
            $0.selectedDownloadIDs = []
        }
    }
}
