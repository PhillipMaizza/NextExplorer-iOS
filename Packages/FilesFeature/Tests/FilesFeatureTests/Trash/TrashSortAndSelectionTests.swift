import ComposableArchitecture
import CoreModels
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct TrashSortAndSelectionTests {
    private enum Constants {
        static let earlier = MockDate.date
        static let later = MockDate.date.addingTimeInterval(86400)
    }

    private let big = TrashItem(id: "t1", name: "big.zip", size: 9000, deletedAt: Constants.earlier)
    private let small = TrashItem(id: "t2", name: "a small.txt", size: 10, deletedAt: Constants.later)
    private let undated = TrashItem(id: "t3", name: "m undated.txt")

    private func store(isSelecting: Bool = false) -> TestStoreOf<TrashFeature> {
        var state = TrashFeature.State(serverURL: TestHost.serverURL)
        state.phase = .loaded
        state.items = IdentifiedArray(uniqueElements: [big, small, undated])
        state.isSelecting = isSelecting
        return TestStore(initialState: state) { TrashFeature() }
    }

    @Test("The trash lists the newest deletions first until another order is picked")
    func newestFirst() {
        #expect(store().state.displayedItems.map(\.id) == [small.id, big.id, undated.id])
    }

    @Test("Sorting by size or name orders the list that way, in the chosen direction")
    func sortsBySizeAndName() async {
        let store = store()
        await store.send(.sortOptionChanged(.size)) { $0.sortOption = .size }
        #expect(store.state.displayedItems.map(\.id) == [big.id, small.id, undated.id])
        await store.send(.sortDirectionChanged(.ascending)) { $0.sortDirection = .ascending }
        #expect(store.state.displayedItems.map(\.id) == [undated.id, small.id, big.id])
        await store.send(.sortOptionChanged(.name)) { $0.sortOption = .name }
        #expect(store.state.displayedItems.map(\.id) == [small.id, big.id, undated.id])
    }

    @Test("Searching keeps the items whose name holds the term, in the list's order")
    func searchFiltersByName() async {
        let store = store()
        await store.send(.searchQueryChanged(" TXT ")) { $0.searchQuery = " TXT " }
        #expect(store.state.displayedItems.map(\.id) == [small.id, undated.id])
        await store.send(.searchQueryChanged("")) { $0.searchQuery = "" }
        #expect(store.state.displayedItems.count == 3)
    }

    @Test("A search drops the selection it hides, so an action never reaches a row out of sight")
    func searchDropsHiddenSelection() async {
        let store = store(isSelecting: true)
        await store.send(.selectAllTapped) { $0.selectedIDs = [big.id, small.id, undated.id] }
        await store.send(.searchQueryChanged("txt")) {
            $0.searchQuery = "txt"
            $0.selectedIDs = [small.id, undated.id]
        }
        #expect(store.state.isAllSelected)
        await store.send(.selectAllTapped) { $0.selectedIDs = [] }
        await store.send(.selectAllTapped) { $0.selectedIDs = [small.id, undated.id] }
    }

    @Test("A search that matches nothing says so, and clearing it brings the list back")
    func searchMissSaysSo() async {
        let store = store()
        #expect(store.state.searchMiss == nil)
        await store.send(.searchQueryChanged("zzz")) { $0.searchQuery = "zzz" }
        #expect(store.state.searchMiss == L10n.EmptyState.noSearchMatches("zzz"))
        await store.send(.searchQueryChanged("  ")) { $0.searchQuery = "  " }
        #expect(store.state.searchMiss == nil)
    }

    @Test("A finger sweep selects what it crossed, never an id the trash does not hold")
    func sweepSelects() async {
        let store = store(isSelecting: true)
        await store.send(.selectionSwept([big.id, "elsewhere"])) { $0.selectedIDs = [big.id] }
    }

    @Test("A sweep outside select mode changes nothing")
    func sweepIgnoredOutsideSelectMode() async {
        await store().send(.selectionSwept([big.id]))
    }

    @Test("Select All picks every item, and again clears them")
    func selectAllToggles() async {
        let store = store(isSelecting: true)
        await store.send(.selectAllTapped) { $0.selectedIDs = [big.id, small.id, undated.id] }
        #expect(store.state.isAllSelected)
        await store.send(.selectAllTapped) { $0.selectedIDs = [] }
    }
}
