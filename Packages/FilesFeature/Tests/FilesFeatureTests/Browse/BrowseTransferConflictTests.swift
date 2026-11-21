import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

/// Pasting into a folder that already holds an item with the same name. The transfer answer writes
/// the shared clipboard and undo stack, so the fakes hold it until the test has asserted the send.
@Suite(.isolatedDependencies)
@MainActor
struct BrowseTransferConflictTests {
    private let incoming = BrowseFixtures.file(TestFile.aText, in: TestFolder.inbox)
    private let existing = BrowseFixtures.file(TestFile.aText, in: TestFolder.documents)

    private func conflictState(clipboard: [FileItem]? = nil) -> BrowseFeature.State {
        let state = BrowseFixtures.state(
            TestFolder.documents,
            title: TestFolder.docs,
            items: [existing],
            access: BrowseFixtures.writableAccess
        )
        state.$clipboard.withLock { $0 = FileClipboard(items: clipboard ?? [incoming], operation: .copy) }
        return state
    }

    private var askRetry: BrowseFeature.TransferRetry {
        BrowseFeature.TransferRetry(
            items: [incoming],
            destination: TestFolder.documents,
            operation: .copy,
            shouldClearClipboard: true
        )
    }

    private func pasteAndStopAtThePrompt(_ store: TestStoreOf<BrowseFeature>) async {
        await store.send(.pasteTapped(keepItemsAfterCopy: false)) {
            $0.pendingTransferRetry = askRetry
            $0.transferConflict = BrowseFeature.TransferConflict(retry: askRetry, collidingItems: [existing])
        }
    }

    @Test("Paste asks what to do when the folder already holds a same named item")
    func pastePromptsWhenTheCurrentFolderAlreadyHasASameNamedItem() async {
        // No transferItems override: a request before the answer fails the test as unimplemented.
        let store = BrowseFixtures.store(conflictState())

        await pasteAndStopAtThePrompt(store)
    }

    @Test("Replace deletes the clashing item first, then transfers onto the freed name")
    func replaceDeletesTheClashingItemThenTransfers() async {
        let gate = AsyncGate()
        let calls = LockIsolated<[String]>([])
        let store = BrowseFixtures.store(conflictState()) {
            $0.filesClient.deleteItems = { _, items, _, _ in
                calls.withValue { $0.append("delete \(items.map(\.id))") }
                return DeleteOutcome()
            }
            $0.filesClient.transferItems = { _, items, destination, _, _ in
                calls.withValue { $0.append("transfer \(items.map(\.id))") }
                try await gate.wait()
                return BrowseFixtures.transferResult(items, to: destination)
            }
        }

        await pasteAndStopAtThePrompt(store)
        await store.send(.transferConflictResolved(.replace)) {
            $0.transferConflict = nil
            $0.isPerformingFileAction = true
            $0.transferProgress = 0
            $0.pendingTransferRetry = BrowseFeature.TransferRetry(
                items: [incoming], destination: TestFolder.documents, operation: .copy, shouldClearClipboard: true,
                resolution: .replace, itemsToReplace: [existing]
            )
        }
        gate.open()
        // The clashing row is still listed until the refresh, so the copy takes its place without a new row.
        await BrowseFixtures.receiveCopyIntoOpenFolder(
            store, listed: [], alreadyListed: [existing], message: L10n.Browse.transferCopied(1), clearsClipboard: true
        )
        #expect(calls.value == ["delete [\"Documents/a.txt\"]", "transfer [\"Inbox/a.txt\"]"])
    }

    @Test("Replace stops before the transfer when the trash keeps the item it would replace")
    func replaceStopsWhenTheTrashKeepsTheClashingItem() async {
        let existing = existing
        let store = BrowseFixtures.store(conflictState()) {
            $0.filesClient.deleteItems = { _, items, _, _ in
                DeleteOutcome(items: items.map { .init(path: $0.id, status: .kept, reason: .otherDevice) })
            }
            $0.filesClient.transferItems = { _, _, _, _, _ in
                Issue.record("Transferred over an item that is still there")
                return BrowseFixtures.transferResult([], to: TestFolder.documents)
            }
        }

        await pasteAndStopAtThePrompt(store)
        await store.send(.transferConflictResolved(.replace)) {
            $0.transferConflict = nil
            $0.isPerformingFileAction = true
            $0.transferProgress = 0
            $0.pendingTransferRetry = BrowseFeature.TransferRetry(
                items: [incoming], destination: TestFolder.documents, operation: .copy, shouldClearClipboard: true,
                resolution: .replace, itemsToReplace: [existing]
            )
        }
        await store.receive(\.transferResponse.failure) {
            $0.isPerformingFileAction = false
            $0.transferProgress = nil
            $0.transferErrorMessage = L10n.Trash.replaceKept(existing.name)
        }
    }

    @Test("Keep both transfers without deleting anything and lets the server number the copy")
    func keepBothTransfersWithoutDeletingAnything() async {
        let gate = AsyncGate()
        let store = BrowseFixtures.store(conflictState()) {
            $0.filesClient.deleteItems = { _, items, _, _ in
                Issue.record("Deleted \(items.map(\.id)) on keep both")
                return DeleteOutcome()
            }
            $0.filesClient.transferItems = { _, items, destination, _, _ in
                try await gate.wait()
                return BrowseFixtures.transferResult(items, to: destination, renamedTo: [TestFile.aText: "a 2.txt"])
            }
        }

        await pasteAndStopAtThePrompt(store)
        await store.send(.transferConflictResolved(.keepBoth)) {
            $0.transferConflict = nil
            $0.isPerformingFileAction = true
            $0.transferProgress = 0
            $0.pendingTransferRetry = BrowseFeature.TransferRetry(
                items: [incoming], destination: TestFolder.documents, operation: .copy, shouldClearClipboard: true,
                resolution: .keepBoth
            )
        }
        gate.open()
        await BrowseFixtures.receiveCopyIntoOpenFolder(
            store,
            listed: [BrowseFixtures.file("a 2.txt", in: TestFolder.documents)],
            message: L10n.Browse.transferCopied(1),
            clearsClipboard: true
        )
    }

    @Test("Cancelling the prompt keeps the clipboard and transfers nothing")
    func cancellingTheCollisionPromptKeepsTheClipboardAndTransfersNothing() async {
        let store = BrowseFixtures.store(conflictState())

        await pasteAndStopAtThePrompt(store)
        await store.send(.transferConflictResolved(nil)) {
            $0.transferConflict = nil
            $0.pendingTransferRetry = nil
        }
    }

    @Test("Pasting a file back into its own folder is not a collision, the server numbers the copy")
    func pastingAFileBackIntoItsOwnFolderIsNotTreatedAsACollision() async {
        let gate = AsyncGate()
        let store = BrowseFixtures.store(conflictState(clipboard: [existing])) {
            $0.filesClient.transferItems = { _, items, destination, _, _ in
                try await gate.wait()
                return BrowseFixtures.transferResult(items, to: destination, renamedTo: [TestFile.aText: "a 2.txt"])
            }
        }

        await store.send(.pasteTapped(keepItemsAfterCopy: true)) {
            $0.isPerformingFileAction = true
            $0.transferProgress = 0
            $0.pendingTransferRetry = BrowseFeature.TransferRetry(
                items: [existing], destination: TestFolder.documents, operation: .copy, shouldClearClipboard: false,
                resolution: .keepBoth
            )
        }
        gate.open()
        await BrowseFixtures.receiveCopyIntoOpenFolder(
            store,
            listed: [BrowseFixtures.file("a 2.txt", in: TestFolder.documents)],
            message: L10n.Browse.transferCopied(1),
            clearsClipboard: false
        )
    }
}
