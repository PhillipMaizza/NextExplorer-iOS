import ComposableArchitecture
import FilesClient
@testable import FilesFeature
import Foundation
import Testing

/// Which pinned items the Offline tab shows and in what order, for the list and the grid alike.
struct OfflineTabPinnedOrderTests {
    private enum Constants {
        static let banana = "Docs/banana.txt"
        static let apple = "Photos/Apple"
        static let cherry = "cherry.jpg"
        static let bananaSize: Int64 = 300
        static let appleSize: Int64 = 100
        static let cherrySize: Int64 = 200
    }

    /// Pinned in this order: banana, apple, cherry.
    private let usages: IdentifiedArrayOf<OfflinePinnedRootUsage> = [
        OfflinePinnedRootUsage(
            root: OfflinePinnedRoot(path: Constants.banana, isDirectory: false), sizeBytes: Constants.bananaSize
        ),
        OfflinePinnedRootUsage(
            root: OfflinePinnedRoot(path: Constants.apple, isDirectory: true), sizeBytes: Constants.appleSize
        ),
        OfflinePinnedRootUsage(
            root: OfflinePinnedRoot(path: Constants.cherry, isDirectory: false), sizeBytes: Constants.cherrySize
        ),
    ]

    private func order(
        query: String = "",
        _ sort: OfflineTabFeature.SortOption,
        _ direction: BrowseFeature.SortDirection = .ascending
    ) -> [String] {
        OfflineTabFeature.displayedPinned(usages, searchQuery: query, sortOption: sort, sortDirection: direction)
            .map(\.root.path)
    }

    @Test
    func sortingByNameUsesTheLastPathComponent() {
        #expect(order(.name) == [Constants.apple, Constants.banana, Constants.cherry])
        #expect(order(.name, .descending) == [Constants.cherry, Constants.banana, Constants.apple])
    }

    @Test
    func sortingBySizeOrdersBySpaceUsed() {
        #expect(order(.size) == [Constants.apple, Constants.cherry, Constants.banana])
        #expect(order(.size, .descending) == [Constants.banana, Constants.cherry, Constants.apple])
    }

    @Test
    func dateAddedKeepsThePinOrder() {
        #expect(order(.dateAdded) == [Constants.banana, Constants.apple, Constants.cherry])
        #expect(order(.dateAdded, .descending) == [Constants.cherry, Constants.apple, Constants.banana])
    }

    @Test
    func searchKeepsOnlyMatchingNamesAndNeverMatchesTheFolderPath() {
        #expect(order(query: "app", .name) == [Constants.apple])
        #expect(order(query: "Photos", .name).isEmpty, "Only the item's own name is searched")
        #expect(order(query: "zzz", .name).isEmpty)
    }

    @Test
    func nothingPinnedShowsNothing() {
        let shown = OfflineTabFeature.displayedPinned(
            [], searchQuery: "", sortOption: .name, sortDirection: .ascending
        )
        #expect(shown.isEmpty)
    }
}
