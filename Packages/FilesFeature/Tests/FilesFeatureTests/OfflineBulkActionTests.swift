@testable import FilesFeature
import Testing
import TestUtils

/// What the selection bar's Available Offline button does: add, remove, or stay disabled.
struct OfflineBulkActionTests {
    private enum Constants {
        static let first = "A"
        static let second = "B"
        static let third = "C"
    }

    @Test
    func nothingSelectedDisablesTheButton() {
        let action = OfflineBulkAction.resolve(selectedIDs: [], offlineIDs: [Constants.first], pinnedIDs: [])

        #expect(action == nil)
    }

    @Test
    func anythingNotOfflineYetMeansAdd() {
        let action = OfflineBulkAction.resolve(
            selectedIDs: [Constants.first, Constants.second],
            offlineIDs: [Constants.first],
            pinnedIDs: [Constants.first]
        )

        #expect(action == .add)
    }

    @Test
    func everythingOfflineAndPinnedMeansRemove() {
        let action = OfflineBulkAction.resolve(
            selectedIDs: [Constants.first, Constants.second],
            offlineIDs: [Constants.first, Constants.second],
            pinnedIDs: [Constants.first, Constants.second]
        )

        #expect(action == .remove)
    }

    @Test
    func removeOnlyTouchesWhatWasPinnedWhenSomeAreOfflineThroughAFolder() {
        let action = OfflineBulkAction.resolve(
            selectedIDs: [Constants.first, Constants.second],
            offlineIDs: [Constants.first, Constants.second],
            pinnedIDs: [Constants.first]
        )

        #expect(action == .remove)
    }

    @Test
    func itemsOfflineOnlyThroughAFolderLeaveNothingToDo() {
        let action = OfflineBulkAction.resolve(
            selectedIDs: [Constants.third],
            offlineIDs: [Constants.third],
            pinnedIDs: []
        )

        #expect(action == nil)
    }

    @Test
    func theTitleAndIconFollowTheAction() {
        #expect(OfflineBulkAction.add.title != OfflineBulkAction.remove.title)
    }
}
