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

        await store.send(.selectAllTapped) { $0.selectedDownloadIDs = [zebra.id, apple.id] }
        await store.send(.deselectAllTapped) { $0.selectedDownloadIDs = [] }
    }
}
