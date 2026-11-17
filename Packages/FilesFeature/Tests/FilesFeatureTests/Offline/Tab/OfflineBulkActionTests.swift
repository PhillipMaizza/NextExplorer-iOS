@testable import FilesFeature
import Testing
import TestUtils

/// What the selection bar's Available Offline button does (add, remove, or stay disabled), and which
/// paths a removal takes off the device.
struct OfflineBulkActionTests {
    private enum Constants {
        static let first = "A"
        static let second = "B"
        static let third = "C"
        static let tripsFolder = "Trips"
        static let tripsPath = "Docs/Trips"
        static let tripsPhoto = "Docs/Trips/a.jpg"
        static let docsPhoto = "Docs/a.jpg"
    }

    @Test
    func nothingSelectedDisablesTheButton() {
        let action = OfflineBulkAction.resolve(selectedIDs: [], offlineIDs: [Constants.first])

        #expect(action == nil)
    }

    @Test
    func anythingNotOfflineYetMeansAdd() {
        let action = OfflineBulkAction.resolve(
            selectedIDs: [Constants.first, Constants.second],
            offlineIDs: [Constants.first]
        )

        #expect(action == .add)
    }

    @Test
    func everythingOfflineMeansRemove() {
        let action = OfflineBulkAction.resolve(
            selectedIDs: [Constants.first, Constants.second],
            offlineIDs: [Constants.first, Constants.second]
        )

        #expect(action == .remove)
    }

    @Test("Items kept only through a pinned folder still offer the removal")
    func itemsOfflineOnlyThroughAFolderMeanRemove() {
        let action = OfflineBulkAction.resolve(selectedIDs: [Constants.third], offlineIDs: [Constants.third])

        #expect(action == .remove)
    }

    @Test
    func theTitleAndIconFollowTheAction() {
        #expect(OfflineBulkAction.add.title != OfflineBulkAction.remove.title)
    }

    @Test("A pinned item comes off itself, under its own name")
    func aPinnedItemComesOffItself() {
        let request = OfflineRemovalRequest.removing(
            [(path: Constants.docsPhoto, name: TestFile.aPhoto)],
            pinnedPaths: [Constants.docsPhoto],
            coveringRoot: { _ in TestFolder.docs }
        )

        #expect(request == OfflineRemovalRequest(paths: [Constants.docsPhoto], names: [TestFile.aPhoto]))
    }

    @Test("An item kept through a pinned folder comes off on its own, under its own name")
    func aCoveredItemComesOffItself() {
        let request = OfflineRemovalRequest.removing(
            [(path: Constants.tripsPhoto, name: TestFile.aPhoto)],
            pinnedPaths: [],
            coveringRoot: { _ in Constants.tripsPath }
        )

        #expect(request == OfflineRemovalRequest(paths: [Constants.tripsPhoto], names: [TestFile.aPhoto]))
    }

    @Test("A pinned item and covered ones picked together each come off, in the order picked")
    func pinnedAndCoveredItemsEachComeOff() {
        let bPhoto = "\(Constants.tripsPath)/\(TestFile.bPhoto)"
        let request = OfflineRemovalRequest.removing(
            [
                (path: Constants.docsPhoto, name: TestFile.aPhoto),
                (path: Constants.tripsPhoto, name: TestFile.aPhoto),
                (path: bPhoto, name: TestFile.bPhoto),
            ],
            pinnedPaths: [Constants.docsPhoto],
            coveringRoot: { _ in Constants.tripsPath }
        )

        #expect(request == OfflineRemovalRequest(
            paths: [Constants.docsPhoto, Constants.tripsPhoto, bPhoto],
            names: [TestFile.aPhoto, TestFile.aPhoto, TestFile.bPhoto]
        ))
    }

    @Test("A folder picked with a file inside it comes off once, the file going with it")
    func aFolderAndItsFileComeOffOnce() {
        let request = OfflineRemovalRequest.removing(
            [
                (path: Constants.tripsPhoto, name: TestFile.aPhoto),
                (path: Constants.tripsPath, name: Constants.tripsFolder),
            ],
            pinnedPaths: [Constants.tripsPath],
            coveringRoot: { _ in nil }
        )

        #expect(request == OfflineRemovalRequest(paths: [Constants.tripsPath], names: [Constants.tripsFolder]))
    }

    @Test("The same item picked twice is named once")
    func aDuplicateIsNamedOnce() {
        let request = OfflineRemovalRequest.removing(
            [(path: Constants.docsPhoto, name: TestFile.aPhoto), (path: Constants.docsPhoto, name: TestFile.aPhoto)],
            pinnedPaths: [Constants.docsPhoto],
            coveringRoot: { _ in nil }
        )

        #expect(request == OfflineRemovalRequest(paths: [Constants.docsPhoto], names: [TestFile.aPhoto]))
    }

    @Test("Nothing pinned and no pinned folder around leaves nothing to remove")
    func nothingRemovableGivesNoRequest() {
        let request = OfflineRemovalRequest.removing(
            [(path: Constants.docsPhoto, name: TestFile.aPhoto)],
            pinnedPaths: [],
            coveringRoot: { _ in nil }
        )

        #expect(request == nil)
    }

    @Test("Nothing picked gives no request")
    func emptyGivesNoRequest() {
        let request = OfflineRemovalRequest.removing([], pinnedPaths: [], coveringRoot: { _ in TestFolder.docs })

        #expect(request == nil)
    }
}
