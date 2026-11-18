import ComposableArchitecture
import CoreModels
@testable import FilesFeature
import Foundation
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
