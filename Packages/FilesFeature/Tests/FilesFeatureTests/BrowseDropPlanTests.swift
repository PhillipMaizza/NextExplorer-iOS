import CoreModels
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

private let receiver = BrowseDropFixtures.receiver

private func entry(_ name: String, in path: String = TestFolder.docs, isFolder: Bool = false) -> FileItem {
    BrowseDropFixtures.entry(name, in: path, isFolder: isFolder)
}

/// What a drop comes to: which rows move, which files upload, and what is refused.
@Suite(.isolatedDependencies)
struct BrowseDropPlanTests {
    @Test("Listed rows move by id and rows of another window move by value")
    func listedRowsMoveByIDAndOthersByValue() {
        let listed = entry(TestFile.aPDF)
        let foreign = entry("z.pdf", in: TestFolder.other)
        let plan = BrowseDropPlan(
            drops: [.items([listed, foreign], origin: receiver)],
            listed: [listed.id],
            destination: "Docs/Archive",
            receiver: receiver
        )

        #expect(plan.listedIDs == [listed.id])
        #expect(plan.foreignItems == [foreign])
        #expect(plan.fileURLs.isEmpty)
    }

    @Test("A folder dropped on itself is refused")
    func aFolderDroppedOnItselfIsRefused() {
        let folder = entry(TestFolder.archive, isFolder: true)
        let plan = BrowseDropPlan(
            drops: [.items([folder], origin: receiver)],
            listed: [folder.id],
            destination: folder.id,
            receiver: receiver
        )

        #expect(plan.isEmpty)
    }

    @Test("A folder dropped on one of its own descendants is refused")
    func aFolderDroppedOnADescendantIsRefused() {
        let folder = entry(TestFolder.archive, isFolder: true)
        let plan = BrowseDropPlan(
            drops: [.items([folder], origin: receiver)],
            listed: [folder.id],
            destination: "Docs/Archive/2024/Q1",
            receiver: receiver
        )

        #expect(plan.isEmpty)
    }

    @Test("A folder whose name only shares a prefix with the destination is not its ancestor")
    func aFolderWhoseNameOnlySharesAPrefixIsNotAnAncestor() {
        let folder = entry("Arch", isFolder: true)
        let plan = BrowseDropPlan(
            drops: [.items([folder], origin: receiver)],
            listed: [folder.id],
            destination: "Docs/Archive",
            receiver: receiver
        )

        #expect(plan.listedIDs == [folder.id])
    }

    @Test("Rows already in the destination are a no op")
    func rowsAlreadyInTheDestinationAreANoOp() {
        let inside = entry(TestFile.aPDF, in: "Docs/Archive")
        let plan = BrowseDropPlan(
            drops: [.items([inside], origin: receiver)],
            listed: [],
            destination: "Docs/Archive",
            receiver: receiver
        )

        #expect(plan.isEmpty)
    }

    @Test("The same row dropped twice moves once")
    func theSameRowDroppedTwiceMovesOnce() {
        let a = entry(TestFile.aPDF)
        let plan = BrowseDropPlan(
            drops: [.items([a], origin: receiver), .items([a], origin: receiver)],
            listed: [a.id],
            destination: "Docs/Archive",
            receiver: receiver
        )

        #expect(plan.listedIDs == [a.id])
    }

    @Test("Only file URLs are uploaded")
    func onlyFileURLsAreUploaded() throws {
        let local = URL(fileURLWithPath: "/tmp/a.jpg")
        let remote = try #require(URL(string: "https://example.com/a.jpg"))
        let plan = BrowseDropPlan(
            drops: [.file(local), .file(remote)],
            listed: [],
            destination: TestFolder.docs,
            receiver: receiver
        )

        #expect(plan.fileURLs == [local])
    }

    @Test(
        "Rows dragged from another account or server are refused",
        arguments: [BrowseDropFixtures.otherAccount, BrowseDropFixtures.otherServer]
    )
    func rowsDraggedFromAnotherAccountOrServerAreRefused(origin: DragOrigin) {
        let same = entry(TestFile.aPDF)
        let plan = BrowseDropPlan(
            drops: [.items([same], origin: origin)], listed: [same.id], destination: "Docs/Archive", receiver: receiver
        )

        #expect(plan.isEmpty)
    }

    @Test("Rows without an identity are refused")
    func rowsWithoutAnIdentityAreRefused() {
        let foreign = entry("z.pdf", in: TestFolder.other)
        let plan = BrowseDropPlan(
            drops: [.items([foreign], origin: nil)], listed: [], destination: TestFolder.docs, receiver: receiver
        )

        #expect(plan.isEmpty)
    }

    @Test("A mixed drop keeps only the rows of the receiving account")
    func aMixedDropKeepsOnlyTheRowsOfTheReceivingAccount() {
        let mine = entry("mine.pdf")
        let theirs = entry("theirs.pdf", in: TestFolder.other)
        let plan = BrowseDropPlan(
            drops: [.items([theirs], origin: BrowseDropFixtures.otherAccount), .items([mine], origin: receiver)],
            listed: [],
            destination: "Elsewhere",
            receiver: receiver
        )

        #expect(plan.foreignItems == [mine])
    }
}

/// The reducer actions a drop is turned into, for a folder row and for the folder background.
@Suite(.isolatedDependencies)
struct BrowseDropRouterTests {
    private let folder = entry(TestFolder.archive, isFolder: true)
    private let local = URL(fileURLWithPath: "/tmp/a.jpg")

    @Test("A folder drop sends the moves and the uploads to the folder")
    func aFolderDropSendsMovesAndUploadsToTheFolder() {
        let foreign = entry("z.pdf", in: TestFolder.other)
        let plan = BrowseDropPlan(
            drops: [.items([entry(TestFile.aPDF), foreign], origin: receiver), .file(local)],
            listed: ["Docs/a.pdf"],
            destination: folder.id,
            receiver: receiver
        )

        let actions = BrowseDropRouter.actions(
            for: plan,
            folder: folder,
            directoryPath: TestFolder.docs,
            canMove: true,
            canUpload: true
        )

        #expect(actions == [
            .itemsDroppedOnFolder(ids: ["Docs/a.pdf"], folder: folder),
            .itemsDroppedFromOtherWindow([foreign], destination: folder.id),
            .filesDroppedOnFolder([local], folder: folder),
        ])
    }

    @Test("Without the rights nothing is sent")
    func withoutRightsNothingIsSent() {
        let plan = BrowseDropPlan(
            drops: [.items([entry(TestFile.aPDF)], origin: receiver), .file(local)],
            listed: ["Docs/a.pdf"],
            destination: folder.id,
            receiver: receiver
        )

        #expect(BrowseDropRouter.actions(
            for: plan,
            folder: folder,
            directoryPath: TestFolder.docs,
            canMove: false,
            canUpload: false
        ).isEmpty)
    }

    @Test("A file row is not a folder drop target")
    func aFileIsNotAFolderDropTarget() {
        let file = entry(TestFile.aPDF)
        let plan = BrowseDropPlan(drops: [.file(local)], listed: [], destination: file.id, receiver: receiver)

        #expect(BrowseDropRouter.actions(
            for: plan,
            folder: file,
            directoryPath: TestFolder.docs,
            canMove: true,
            canUpload: true
        ).isEmpty)
    }

    @Test("The background uploads through the regular flow")
    func theBackgroundUploadsThroughTheRegularFlow() {
        let plan = BrowseDropPlan(drops: [.file(local)], listed: [], destination: TestFolder.docs, receiver: receiver)

        let actions = BrowseDropRouter.actions(
            for: plan,
            folder: nil,
            directoryPath: TestFolder.docs,
            canMove: true,
            canUpload: true
        )

        #expect(actions == [.beginUpload(.documents([local]))])
    }

    @Test("The background moves rows from another window into the folder on screen")
    func theBackgroundMovesRowsFromAnotherWindowIntoTheFolderOnScreen() {
        let foreign = entry("z.pdf", in: TestFolder.other)
        let plan = BrowseDropPlan(
            drops: [.items([foreign], origin: receiver)],
            listed: [],
            destination: TestFolder.docs,
            receiver: receiver
        )

        let actions = BrowseDropRouter.actions(
            for: plan,
            folder: nil,
            directoryPath: TestFolder.docs,
            canMove: true,
            canUpload: true
        )

        #expect(actions == [.itemsDroppedFromOtherWindow([foreign], destination: TestFolder.docs)])
    }

    @Test("The background ignores rows from the same folder")
    func theBackgroundIgnoresRowsFromTheSameFolder() {
        let plan = BrowseDropPlan(
            drops: [.items([entry(TestFile.aPDF)], origin: receiver)],
            listed: ["Docs/a.pdf"],
            destination: TestFolder.docs,
            receiver: receiver
        )

        #expect(BrowseDropRouter.actions(
            for: plan,
            folder: nil,
            directoryPath: TestFolder.docs,
            canMove: true,
            canUpload: true
        ).isEmpty)
    }

    @Test("The root listing takes no moved rows")
    func theRootListingTakesNoMovedRows() {
        let foreign = entry("z.pdf", in: TestFolder.other)
        let plan = BrowseDropPlan(
            drops: [.items([foreign], origin: receiver)],
            listed: [],
            destination: "",
            receiver: receiver
        )

        #expect(BrowseDropRouter.actions(for: plan, folder: nil, directoryPath: "", canMove: true, canUpload: true)
            .isEmpty)
    }
}

/// Whether a folder row outlines as a drop target while a drag is over it.
@Suite(.isolatedDependencies)
struct BrowseDropAcceptanceTests {
    private let folder = entry(TestFolder.archive, isFolder: true)

    private func canAccept(
        destination: String? = nil, isFolder: Bool = true, dragged: [FileItem] = [], canMove: Bool = true,
        canUpload: Bool = true
    ) -> Bool {
        BrowseDropAcceptance.canAccept(
            destination: destination ?? folder.id, isFolder: isFolder, draggedRows: dragged, canMove: canMove,
            canUpload: canUpload
        )
    }

    @Test("An external drag is accepted with upload rights")
    func anExternalDragIsAcceptedWithUploadRights() {
        #expect(canAccept(canMove: false, canUpload: true))
    }

    @Test("An external drag is accepted with move rights alone on a non root destination")
    func anExternalDragIsAcceptedWithMoveRightsAloneOnANonRootDestination() {
        #expect(canAccept(canMove: true, canUpload: false))
        #expect(!canAccept(destination: "", canMove: true, canUpload: false))
    }

    @Test("No rights means no outline")
    func noRightsMeansNoOutline() {
        #expect(!canAccept(canMove: false, canUpload: false))
    }

    @Test("A file row is not a target")
    func aFileRowIsNotATarget() {
        #expect(!canAccept(isFolder: false))
    }

    @Test("A folder dragged over itself is refused")
    func aFolderDraggedOverItselfIsRefused() {
        #expect(!canAccept(dragged: [folder]))
    }

    @Test("A folder dragged over its own descendant is refused")
    func aFolderDraggedOverItsOwnDescendantIsRefused() {
        let inside = entry("2024", in: folder.id, isFolder: true)
        #expect(!canAccept(destination: inside.id, dragged: [folder]))
    }

    @Test("Rows already inside the destination are refused")
    func rowsAlreadyInsideTheDestinationAreRefused() {
        #expect(!canAccept(dragged: [entry(TestFile.aPDF, in: folder.id)]))
    }

    @Test("Own rows need move rights even when uploads are allowed")
    func ownRowsNeedMoveRightsEvenWhenUploadsAreAllowed() {
        #expect(!canAccept(dragged: [entry(TestFile.aPDF)], canMove: false, canUpload: true))
        #expect(canAccept(dragged: [entry(TestFile.aPDF)], canMove: true, canUpload: false))
    }

    @Test("A selection with one movable row is accepted")
    func aSelectionWithOneMovableRowIsAccepted() {
        #expect(canAccept(dragged: [folder, entry(TestFile.aPDF)]))
    }
}

/// Any app can export the drag type, so a payload's rows are checked before they move.
@Suite(.isolatedDependencies)
struct BrowseDropUntrustedPayloadTests {
    private func plan(_ item: FileItem) -> BrowseDropPlan {
        BrowseDropPlan(
            drops: [.items([item], origin: receiver)],
            listed: [],
            destination: "Docs/Archive",
            receiver: receiver
        )
    }

    @Test("A well formed foreign row is moved")
    func aWellFormedForeignRowIsMoved() {
        #expect(plan(entry(TestFile.aPDF, in: "Other/Deep")).foreignItems.count == 1)
        #expect(plan(entry(TestFile.aPDF, in: "")).foreignItems.count == 1)
    }

    @Test(
        "A foreign row with an unsafe path is rejected",
        arguments: ["../secret", "Docs/../../etc", "/absolute", "a//b", "Docs/./x", "a\u{0}b", ".."]
    )
    func aForeignRowWithAnUnsafePathIsRejected(path: String) {
        #expect(plan(entry(TestFile.aPDF, in: path)).isEmpty)
    }

    @Test("A foreign row with an unsafe name is rejected", arguments: ["", ".", "..", "a/b", "a\u{0}b"])
    func aForeignRowWithAnUnsafeNameIsRejected(name: String) {
        #expect(plan(entry(name, in: TestFolder.other)).isEmpty)
    }

    @Test("An unsafe row is rejected but its safe neighbour still moves")
    func anUnsafeRowIsRejectedButItsSafeNeighbourStillMoves() {
        let drop = BrowseDropPlan(
            drops: [.items([entry(TestFile.aPDF, in: "../x"), entry("b.pdf", in: TestFolder.other)], origin: receiver)],
            listed: [], destination: "Docs/Archive", receiver: receiver
        )
        #expect(drop.foreignItems.map(\.name) == ["b.pdf"])
    }
}
