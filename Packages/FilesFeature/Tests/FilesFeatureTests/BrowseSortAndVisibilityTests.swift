import ComposableArchitecture
import CoreModels
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// The pure `displayedItems` and `displayedSearchResults` properties, checked against hand built
/// state rather than through the reducer: sorting and filtering are derived, so no action produces them.
@Suite(.isolatedDependencies)
@MainActor
struct BrowseSortAndVisibilityTests {
    private func makeState(
        showHiddenFiles: Bool = true,
        sortOption: BrowseFeature.SortOption = .name,
        sortDirection: BrowseFeature.SortDirection = .ascending,
        items: [FileItem] = []
    ) -> BrowseFeature.State {
        var state = BrowseFixtures.state(items: items)
        state.$preferences.withLock { $0 = UserPreferences(showHiddenFiles: showHiddenFiles, showThumbnails: true) }
        state.sortOption = sortOption
        state.sortDirection = sortDirection
        return state
    }

    // MARK: Sorting

    struct SortCase: Sendable, CustomTestStringConvertible {
        let option: BrowseFeature.SortOption
        let direction: BrowseFeature.SortDirection
        /// Listed in the opposite order of `expected`, so the sort has to move them.
        let items: [FileItem]
        let expected: [String]

        var testDescription: String {
            "\(option) \(direction)"
        }
    }

    private nonisolated static let older = BrowseFixtures.file("older.txt", modified: MockDate.date)
    private nonisolated static let newer = BrowseFixtures.file("newer.txt", modified: MockDate.date.addingTimeInterval(1_000))
    private nonisolated static let small = BrowseFixtures.file("small.txt", size: 10)
    private nonisolated static let large = BrowseFixtures.file("large.txt", size: 1_000)
    private nonisolated static let photo = BrowseFixtures.file(TestFile.photo)
    private nonisolated static let notes = BrowseFixtures.file(TestFile.notes)
    private nonisolated static let fileA = BrowseFixtures.file(TestFile.aText)
    private nonisolated static let fileB = BrowseFixtures.file(TestFile.bText)

    @Test(
        "Files sort within their group by the chosen option and direction",
        arguments: [
            SortCase(option: .name, direction: .ascending, items: [fileB, fileA], expected: [TestFile.aText, TestFile.bText]),
            SortCase(option: .name, direction: .descending, items: [fileA, fileB], expected: [TestFile.bText, TestFile.aText]),
            SortCase(option: .size, direction: .ascending, items: [large, small], expected: ["small.txt", "large.txt"]),
            SortCase(option: .size, direction: .descending, items: [small, large], expected: ["large.txt", "small.txt"]),
            SortCase(option: .dateModified, direction: .ascending, items: [newer, older], expected: ["older.txt", "newer.txt"]),
            SortCase(option: .dateModified, direction: .descending, items: [older, newer], expected: ["newer.txt", "older.txt"]),
            SortCase(option: .kind, direction: .ascending, items: [notes, photo], expected: [TestFile.photo, TestFile.notes]),
            SortCase(option: .kind, direction: .descending, items: [photo, notes], expected: [TestFile.notes, TestFile.photo]),
        ]
    )
    func filesSortWithinTheirGroup(_ sort: SortCase) {
        let state = makeState(sortOption: sort.option, sortDirection: sort.direction, items: sort.items)

        #expect(state.displayedItems.map(\.name) == sort.expected)
    }

    @Test(
        "Folders sort before files whatever the option and direction",
        arguments: [BrowseFeature.SortOption.name, .size, .dateModified, .kind],
        [BrowseFeature.SortDirection.ascending, .descending]
    )
    func foldersAlwaysSortBeforeFiles(option: BrowseFeature.SortOption, direction: BrowseFeature.SortDirection) {
        let state = makeState(
            sortOption: option,
            sortDirection: direction,
            items: [BrowseFixtures.file("aaa.txt"), BrowseFixtures.folder("zzz")]
        )

        #expect(state.displayedItems.map(\.name) == ["zzz", "aaa.txt"])
    }

    @Test("Items of equal size sorted descending are neither lost nor duplicated")
    func equalSizesDoNotCrashOrReorderUnpredictablyWhenDescending() {
        // Regression: negating a `<` comparator to build `>` breaks `sorted`'s strict weak ordering
        // exactly when two elements compare equal. Only the membership is asserted, not the tie order.
        let state = makeState(
            sortOption: .size,
            sortDirection: .descending,
            items: [BrowseFixtures.file(TestFile.aText, size: 100), BrowseFixtures.file(TestFile.bText, size: 100)]
        )

        #expect(Set(state.displayedItems.map(\.name)) == [TestFile.aText, TestFile.bText])
        #expect(state.displayedItems.count == 2)
    }

    // MARK: Hidden files

    struct HiddenCase: Sendable, CustomTestStringConvertible {
        let showHiddenFiles: Bool
        let expected: Set<String>

        var testDescription: String {
            "showHiddenFiles \(showHiddenFiles)"
        }
    }

    private nonisolated static let hiddenCases = [
        HiddenCase(showHiddenFiles: false, expected: ["visible.txt"]),
        HiddenCase(showHiddenFiles: true, expected: ["visible.txt", ".hidden"]),
    ]

    @Test("Hidden files show only when the preference is on", arguments: hiddenCases)
    func hiddenFilesFollowThePreference(_ hidden: HiddenCase) {
        let state = makeState(
            showHiddenFiles: hidden.showHiddenFiles,
            items: [BrowseFixtures.file("visible.txt"), BrowseFixtures.file(".hidden", kind: TestKind.text)]
        )

        #expect(Set(state.displayedItems.map(\.name)) == hidden.expected)
        #expect(state.displayedItems.count == hidden.expected.count)
    }

    @Test("Hidden search results show only when the preference is on", arguments: hiddenCases)
    func displayedSearchResultsFollowThePreference(_ hidden: HiddenCase) {
        var state = makeState(showHiddenFiles: hidden.showHiddenFiles)
        state.searchResults = [
            SearchResultItem(name: "visible.txt", path: "", kind: TestKind.text),
            SearchResultItem(name: ".hidden", path: "", kind: TestKind.text),
        ]

        #expect(Set(state.displayedSearchResults?.map(\.name) ?? []) == hidden.expected)
        #expect(state.displayedSearchResults?.count == hidden.expected.count)
    }

    @Test("A search that returned no matches shows an empty list, not no search")
    func displayedSearchResultsIsEmptyWhenSearchReturnedNoMatches() {
        var state = makeState()
        state.searchResults = []

        #expect(state.displayedSearchResults?.isEmpty == true)
    }
}
