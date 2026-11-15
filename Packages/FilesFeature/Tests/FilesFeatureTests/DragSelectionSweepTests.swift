@testable import FilesFeature
import Testing

/// The range a finger slide picks, before any screen applies it.
struct DragSelectionSweepTests {
    private enum Constants {
        static let order = ["a", "b", "c", "d", "e"]
    }

    @Test("Starting on an unselected item selects everything up to the finger, either direction")
    func startingUnselectedSelectsTheRange() {
        let sweep = DragSelectionSweep(anchorID: "b", selection: ["e"])
        #expect(sweep.isSelecting)
        #expect(sweep.selection(order: Constants.order, currentID: "d") == ["b", "c", "d", "e"])
        #expect(sweep.selection(order: Constants.order, currentID: "a") == ["a", "b", "e"])
    }

    @Test("Starting on a selected item deselects the range and leaves the rest")
    func startingSelectedDeselectsTheRange() {
        let sweep = DragSelectionSweep(anchorID: "c", selection: ["a", "b", "c", "d"])
        #expect(!sweep.isSelecting)
        #expect(sweep.selection(order: Constants.order, currentID: "d") == ["a", "b"])
    }

    @Test("Coming back over items gives them back their state from before the slide")
    func comingBackRestoresTheBaseline() {
        let sweep = DragSelectionSweep(anchorID: "a", selection: ["d"])
        #expect(sweep.selection(order: Constants.order, currentID: "e") == ["a", "b", "c", "d", "e"])
        #expect(sweep.selection(order: Constants.order, currentID: "b") == ["a", "b", "d"])
    }

    @Test("An item no longer listed leaves the selection as it was")
    func aMissingItemKeepsTheBaseline() {
        let sweep = DragSelectionSweep(anchorID: "a", selection: ["c"])
        #expect(sweep.selection(order: Constants.order, currentID: "z") == ["c"])
    }
}
