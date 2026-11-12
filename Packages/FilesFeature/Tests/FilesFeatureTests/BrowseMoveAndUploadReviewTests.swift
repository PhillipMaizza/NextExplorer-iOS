import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import FolderPickerFeature
import Foundation
import Localization
import Testing
import TestUtils

/// Moving through the destination picker and the upload review sheet. A move answer writes the shared
/// undo stack, so the fake holds its answer until the test has asserted the send that started it.
@Suite(.isolatedDependencies)
@MainActor
struct BrowseMoveAndUploadReviewTests {
    private let incoming = BrowseFixtures.file(TestFile.aText, in: TestFolder.inbox)

    private func makeState() -> BrowseFeature.State {
        BrowseFixtures.state(TestFolder.documents, title: TestFolder.docs, access: BrowseFixtures.writableAccess)
    }

    private func picked(_ name: String, id: UUID) -> PickedFile {
        PickedFile(id: id, fileURL: URL(fileURLWithPath: "/tmp/\(name)"), fileName: name, size: 10)
    }

    // MARK: Destination picker

    @Test("Move presents the destination picker for the item")
    func moveTappedPresentsTheDestinationPicker() async {
        let store = BrowseFixtures.store(makeState())

        await store.send(.moveTapped(incoming)) {
            $0.destinationPicker = DestinationPickerFeature.State(serverURL: BrowseTestSupport.serverURL, items: [incoming])
        }
    }

    @Test("Bulk move presents the picker with the selection in listing order and leaves select mode")
    func bulkMovePresentsThePickerWithTheSelectionAndExitsSelectMode() async {
        let first = BrowseFixtures.file(TestFile.aText, in: TestFolder.documents)
        let second = BrowseFixtures.file(TestFile.bText, in: TestFolder.documents)
        var state = makeState()
        state.items = [first, second]
        state.isSelecting = true
        state.selectedItemIDs = [first.id, second.id]
        let store = BrowseFixtures.store(state)

        await store.send(.bulkMoveTapped) {
            $0.destinationPicker = DestinationPickerFeature.State(serverURL: BrowseTestSupport.serverURL, items: [first, second])
            $0.isSelecting = false
            $0.selectedItemIDs = []
        }
    }

    @Test("Cancelling the picker dismisses it and transfers nothing")
    func destinationPickerCancelDismissesWithoutTransferring() async {
        var state = makeState()
        state.destinationPicker = DestinationPickerFeature.State(serverURL: BrowseTestSupport.serverURL, items: [incoming])
        // No transferItems override: a request fails the test as unimplemented.
        let store = BrowseFixtures.store(state)

        await store.send(.destinationPicker(.presented(.delegate(.cancelled)))) {
            $0.destinationPicker = nil
        }
    }

    /// A move to another folder checks that folder for name clashes first, then transfers, and records
    /// where each item came from so undo can move it back.
    private func receiveMoveToArchive(_ store: TestStoreOf<BrowseFeature>, moved: [String], message: String, gate: AsyncGate) async {
        await store.receive(\.transferConflictCheckResponse) {
            $0.pendingTransferRetry?.resolution = .keepBoth
        }
        gate.open()
        await store.receive(\.transferResponse.success) {
            $0.isPerformingFileAction = false
            $0.fileActionProgressMessage = nil
            $0.pendingTransferRetry = nil
            $0.transferSuccessMessage = message
            $0.$undoStack.withLock {
                $0.record(FileUndoEntry(.moved(moved.map {
                    FileUndoEntry.MovedItem(item: BrowseFixtures.file($0, in: TestFolder.archive), originalParent: TestFolder.inbox)
                })))
            }
        }
        await store.receive(.delegate(.directoryContentsChanged))
    }

    @Test("Confirming the picker moves the items to the chosen folder and leaves the copy clipboard alone")
    func destinationPickerConfirmRunsAMoveTransfer() async {
        var state = makeState()
        state.$clipboard.withLock { $0 = FileClipboard(items: [BrowseFixtures.file("copied.txt", in: TestFolder.inbox)], operation: .copy) }
        state.destinationPicker = DestinationPickerFeature.State(serverURL: BrowseTestSupport.serverURL, items: [incoming])
        let gate = AsyncGate()
        let events = LockIsolated<[String]>([])
        let store = BrowseFixtures.store(state) {
            $0.filesClient.browse = { _, path in
                events.withValue { $0.append("list \(path)") }
                return BrowseResult(items: [], access: BrowseTestSupport.readOnlyAccess, path: path)
            }
            $0.filesClient.transferItems = { _, items, destination, operation in
                events.withValue { $0.append("\(operation) \(items.map(\.id)) to \(destination)") }
                try await gate.wait()
                return BrowseFixtures.transferResult(items, to: destination)
            }
        }

        await store.send(.destinationPicker(.presented(.delegate(.confirmed(destination: TestFolder.archive))))) {
            $0.destinationPicker = nil
            $0.isPerformingFileAction = true
            $0.fileActionProgressMessage = L10n.Browse.progressMoving
            $0.pendingTransferRetry = BrowseFeature.TransferRetry(
                items: [incoming], destination: TestFolder.archive, operation: .move, clearClipboard: false
            )
        }
        await receiveMoveToArchive(store, moved: ["a.txt"], message: L10n.Browse.transferMoved(1), gate: gate)
        #expect(events.value == ["list Archive", "move [\"Inbox/a.txt\"] to Archive"])
    }

    @Test("The move message reports how many items the server skipped")
    func moveViaPickerSuccessMessageReportsSkippedItems() async {
        let second = BrowseFixtures.file(TestFile.bText, in: TestFolder.inbox)
        let third = BrowseFixtures.file("c.txt", in: TestFolder.inbox)
        var state = makeState()
        state.destinationPicker = DestinationPickerFeature.State(serverURL: BrowseTestSupport.serverURL, items: [incoming, second, third])
        let gate = AsyncGate()
        let store = BrowseFixtures.store(state) {
            $0.filesClient.browse = { _, path in BrowseResult(items: [], access: BrowseTestSupport.readOnlyAccess, path: path) }
            $0.filesClient.transferItems = { _, items, destination, _ in
                try await gate.wait()
                return BrowseFixtures.transferResult([items[0], items[1]], to: destination, skipping: [items[2]])
            }
        }

        await store.send(.destinationPicker(.presented(.delegate(.confirmed(destination: TestFolder.archive))))) {
            $0.destinationPicker = nil
            $0.isPerformingFileAction = true
            $0.fileActionProgressMessage = L10n.Browse.progressMoving
            $0.pendingTransferRetry = BrowseFeature.TransferRetry(
                items: [incoming, second, third], destination: TestFolder.archive, operation: .move, clearClipboard: false
            )
        }
        await receiveMoveToArchive(store, moved: ["a.txt", "b.txt"], message: L10n.Browse.transferMovedWithSkipped(2, 1), gate: gate)
    }

    // MARK: Upload review

    @Test("Confirming the review sheet hands the files to the upload queue with the chosen destination")
    func confirmingTheReviewSheetEnqueuesWithTheChosenDestination() async {
        var state = makeState()
        let files = [picked(TestFile.aPhoto, id: UUID(0)), picked(TestFile.bText, id: UUID(1))]
        state.uploadReview = UploadReviewFeature.State(serverURL: BrowseTestSupport.serverURL, files: files, startingDestination: TestFolder.documents)
        let store = BrowseFixtures.store(state)

        await store.send(.uploadReview(.presented(.delegate(.confirmed(files: files, destination: "Documents/Trips"))))) {
            $0.uploadReview = nil
        }
        await store.receive(.delegate(.uploadRequested([
            PendingUpload(id: UUID(0), fileURL: URL(fileURLWithPath: "/tmp/a.jpg"), fileName: TestFile.aPhoto, destination: "Documents/Trips"),
            PendingUpload(id: UUID(1), fileURL: URL(fileURLWithPath: "/tmp/b.txt"), fileName: TestFile.bText, destination: "Documents/Trips"),
        ])))
    }

    @Test("Cancelling a review that is still preparing closes it with nothing to discard")
    func cancellingTheUploadReviewSheetClosesIt() async {
        var state = makeState()
        state.uploadReview = UploadReviewFeature.State(
            serverURL: BrowseTestSupport.serverURL, startingDestination: TestFolder.documents, preparingCount: 1
        )
        // No uploadStaging override: a discard fails the test as unimplemented.
        let store = BrowseFixtures.store(state)

        await store.send(.uploadReview(.presented(.delegate(.cancelled)))) {
            $0.uploadReview = nil
        }
    }

    @Test("Cancelling a review discards the files staging already copied")
    func cancellingTheUploadReviewSheetDiscardsTheStagedFiles() async {
        var state = makeState()
        let files = [picked(TestFile.aPhoto, id: UUID(0)), picked(TestFile.bText, id: UUID(1))]
        state.uploadReview = UploadReviewFeature.State(serverURL: BrowseTestSupport.serverURL, files: files, startingDestination: TestFolder.documents)
        let discarded = LockIsolated<[[URL]]>([])
        let store = BrowseFixtures.store(state) {
            $0.uploadStaging.discard = { urls in discarded.withValue { $0.append(urls) } }
        }

        await store.send(.uploadReview(.presented(.delegate(.cancelled)))) {
            $0.uploadReview = nil
        }
        await store.finish()
        #expect(discarded.value == [[URL(fileURLWithPath: "/tmp/a.jpg"), URL(fileURLWithPath: "/tmp/b.txt")]])
    }

    #if os(iOS)
        @Test("Beginning an upload opens the review sheet and stages every file into it")
        func beginningUploadOpensTheReviewSheetAndStartsStaging() async {
            let urls = [URL(fileURLWithPath: "/tmp/a.jpg"), URL(fileURLWithPath: "/tmp/b.jpg")]
            let first = picked(TestFile.aPhoto, id: UUID(0))
            let second = picked(TestFile.bPhoto, id: UUID(1))
            let store = BrowseFixtures.store(makeState()) {
                $0.uploadStaging.stageDocuments = { _ in
                    AsyncStream<PickedFile> { continuation in
                        continuation.yield(first)
                        continuation.yield(second)
                        continuation.finish()
                    }
                }
            }

            await store.send(.beginUpload(.documents(urls))) {
                $0.uploadReview = UploadReviewFeature.State(serverURL: BrowseTestSupport.serverURL, startingDestination: TestFolder.documents)
            }
            await store.receive(\.uploadReview.presented.stage) {
                $0.uploadReview?.preparingCount = 2
            }
            await store.receive(\.uploadReview.presented.filePrepared) {
                $0.uploadReview?.files.append(first)
                $0.uploadReview?.preparingCount = 1
            }
            await store.receive(\.uploadReview.presented.filePrepared) {
                $0.uploadReview?.files.append(second)
                $0.uploadReview?.preparingCount = 0
            }
            await store.receive(\.uploadReview.presented.stagingBatchFinished)
        }
    #endif
}
