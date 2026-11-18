import Foundation

/// One finger slide across a list or grid in select mode, as in Photos: it starts on an item, and every
/// item between that one and the one under the finger takes the starting item's new state. Starting on
/// an unselected item selects the range, starting on a selected one deselects it. Items the slide passes
/// and then leaves again go back to how they were before it started.
struct DragSelectionSweep: Equatable {
    let anchorID: String
    let isSelecting: Bool
    let baseline: Set<String>

    init(anchorID: String, selection: Set<String>) {
        self.anchorID = anchorID
        isSelecting = !selection.contains(anchorID)
        baseline = selection
    }

    /// The selection with the finger over `currentID`, in the screen's item `order`. An id missing from
    /// `order` (gone from the listing) leaves the selection as it was before the slide.
    func selection(order: [String], currentID: String) -> Set<String> {
        guard let start = order.firstIndex(of: anchorID), let end = order.firstIndex(of: currentID) else {
            return baseline
        }
        let range = Set(order[min(start, end) ... max(start, end)])
        return isSelecting ? baseline.union(range) : baseline.subtracting(range)
    }
}
