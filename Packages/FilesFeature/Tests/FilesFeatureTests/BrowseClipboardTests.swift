import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

/// Copy, paste and duplicate. A transfer answer writes the shared clipboard and undo stack, so the
/// fakes hold their answer until the test has asserted the send that started the transfer.
@Suite(.isolatedDependencies)
@MainActor
struct BrowseClipboardTests {
    private let incoming = BrowseFixtures.file(TestFile.aText, in: TestFolder.inbox)
    private let landed = BrowseFixtures.file(TestFile.aText, in: TestFolder.documents)

    private func makeState(
        _ path: String = TestFolder.documents,
        access: FileAccess = BrowseFixtures.writableAccess
    ) -> BrowseFeature.State {
        BrowseFixtures.state(path, title: TestFolder.docs, access: access)
    }

    private func pasteRetry(clearClipboard: Bool) -> BrowseFeature.TransferRetry {
        BrowseFeature.TransferRetry(
            items: [incoming], destination: TestFolder.documents, operation: .copy, clearClipboard: clearClipboard,
            resolution: .keepBoth
        )
    }

    // MARK: Staging

    @Test("Copy stages the item and confirms with a toast")
    func copyTappedStagesTheItemAndConfirmsWithAToast() async {
        let store = BrowseFixtures.store(makeState())

        await store.send(.copyTapped(incoming)) {
            $0.$clipboard.withLock { $0 = FileClipboard(items: [incoming], operation: .copy) }
            $0.clipboardStagedMessage = L10n.Browse.clipboardCopiedOne("a.txt")
        }
    }

    @Test("Bulk copy stages the selection in listing order with a count toast and leaves select mode")
    func bulkCopyStagesTheSelectionWithACountToastAndExitsSelectMode() async {
        let first = BrowseFixtures.file(TestFile.aText, in: TestFolder.documents)
        let second = BrowseFixtures.file(TestFile.bText, in: TestFolder.documents)
        var state = makeState()
        state.items = [first, second]
        state.isSelecting = true
        state.selectedItemIDs = [first.id, second.id]
        let store = BrowseFixtures.store(state)

        await store.send(.bulkCopyTapped) {
            $0.$clipboard.withLock { $0 = FileClipboard(items: [first, second], operation: .copy) }
            $0.clipboardStagedMessage = L10n.Browse.clipboardCopiedMany(2)
            $0.isSelecting = false
            $0.selectedItemIDs = []
        }
    }

    @Test("Bulk copy of a single selected item names it instead of counting it")
    func bulkCopyOfOneItemNamesIt() async {
        let only = BrowseFixtures.file(TestFile.aText, in: TestFolder.documents)
        var state = makeState()
        state.items = [only, BrowseFixtures.file(TestFile.bText, in: TestFolder.documents)]
        state.isSelecting = true
        state.selectedItemIDs = [only.id]
        let store = BrowseFixtures.store(state)

        await store.send(.bulkCopyTapped) {
            $0.$clipboard.withLock { $0 = FileClipboard(items: [only], operation: .copy) }
            $0.clipboardStagedMessage = L10n.Browse.clipboardCopiedOne(only.name)
            $0.isSelecting = false
            $0.selectedItemIDs = []
        }
    }

    // MARK: Paste

    @Test("Paste copies into the current folder, lists the copy, and empties the clipboard when keep is off")
    func pasteCopiesIntoTheCurrentFolderAndClearsTheClipboardWhenKeepIsOff() async {
        let state = makeState()
        state.$clipboard.withLock { $0 = FileClipboard(items: [incoming], operation: .copy) }
        let gate = AsyncGate()
        let requests = LockIsolated<[String]>([])
        let store = BrowseFixtures.store(state) {
            $0.filesClient.transferItems = { _, items, destination, operation, _ in
                requests
                    .withValue {
                        $0.append("\(items.map(\.id).joined(separator: ",")) to \(destination) as \(operation)")
                    }
                try await gate.wait()
                return BrowseFixtures.transferResult(items, to: destination)
            }
        }

        await store.send(.pasteTapped(keepItemsAfterCopy: false)) {
            $0.isPerformingFileAction = true
            $0.transferProgress = 0
            $0.pendingTransferRetry = pasteRetry(clearClipboard: true)
        }
        gate.open()
        await BrowseFixtures.receiveCopyIntoOpenFolder(
            store, listed: [landed], message: L10n.Browse.transferCopied(1), clearsClipboard: true
        )
        #expect(requests.value == ["Inbox/a.txt to Documents as copy"])
    }

    @Test("A running paste reports its progress to the bar")
    func pasteReportsItsProgress() async {
        let state = makeState()
        state.$clipboard.withLock { $0 = FileClipboard(items: [incoming], operation: .copy) }
        let gate = AsyncGate()
        let store = BrowseFixtures.store(state) {
            $0.filesClient.transferItems = { _, items, destination, _, onProgress in
                onProgress?(0.5)
                try await gate.wait()
                return BrowseFixtures.transferResult(items, to: destination)
            }
        }

        await store.send(.pasteTapped(keepItemsAfterCopy: false)) {
            $0.isPerformingFileAction = true
            $0.transferProgress = 0
            $0.pendingTransferRetry = pasteRetry(clearClipboard: true)
        }
        await store.receive(\.transferProgressed) {
            $0.transferProgress = 0.5
        }
        gate.open()
        await BrowseFixtures.receiveCopyIntoOpenFolder(
            store, listed: [landed], message: L10n.Browse.transferCopied(1), clearsClipboard: true
        )
    }

    @Test("Cancel during a transfer ends the run and reads the folder again")
    func transferCancelEndsTheRunAndReloads() async {
        var state = makeState()
        state.isPerformingFileAction = true
        state.transferProgress = 0.3
        state.pendingTransferRetry = pasteRetry(clearClipboard: false)
        let favorites = AsyncGate()
        let store = BrowseFixtures.store(state) {
            $0.serveEmptyFolders()
            $0.serveListing([])
            $0.holdFavorites(favorites)
        }

        await store.send(.transferCancelTapped) {
            $0.isPerformingFileAction = false
            $0.transferProgress = nil
            $0.pendingTransferRetry = nil
            $0.phase = .loading
        }
        await store.receive(\.itemsResponse.success) {
            $0.phase = .loaded
            $0.access = BrowseTestSupport.readOnlyAccess
            $0.items = []
        }
        favorites.open()
        await store.receive(\.favoritesResponse) {
            $0.hasLoadedFavorites = true
        }
        await store.finish()
    }

    @Test("Cancel with no transfer running does nothing")
    func transferCancelWithNothingRunningDoesNothing() async {
        let store = BrowseFixtures.store(makeState())

        await store.send(.transferCancelTapped)
    }

    @Test("Paste keeps the clipboard when keep items after copy is on")
    func pasteKeepsTheClipboardWhenKeepItemsAfterCopyIsOn() async {
        let state = makeState()
        state.$clipboard.withLock { $0 = FileClipboard(items: [incoming], operation: .copy) }
        let gate = AsyncGate()
        let store = BrowseFixtures.store(state) {
            $0.filesClient.transferItems = { _, items, destination, _, _ in
                try await gate.wait()
                return BrowseFixtures.transferResult(items, to: destination)
            }
        }

        await store.send(.pasteTapped(keepItemsAfterCopy: true)) {
            $0.isPerformingFileAction = true
            $0.transferProgress = 0
            $0.pendingTransferRetry = pasteRetry(clearClipboard: false)
        }
        gate.open()
        await BrowseFixtures.receiveCopyIntoOpenFolder(
            store, listed: [landed], message: L10n.Browse.transferCopied(1), clearsClipboard: false
        )
    }

    @Test("The paste message reports how many copies the server skipped")
    func pasteSuccessMessageReportsSkippedCopies() async {
        let second = BrowseFixtures.file(TestFile.bText, in: TestFolder.inbox)
        let third = BrowseFixtures.file("c.txt", in: TestFolder.inbox)
        let state = makeState()
        state.$clipboard.withLock { $0 = FileClipboard(items: [incoming, second, third], operation: .copy) }
        let gate = AsyncGate()
        let store = BrowseFixtures.store(state) {
            $0.filesClient.transferItems = { _, items, destination, _, _ in
                try await gate.wait()
                return BrowseFixtures.transferResult([items[0], items[1]], to: destination, skipping: [items[2]])
            }
        }

        await store.send(.pasteTapped(keepItemsAfterCopy: false)) {
            $0.isPerformingFileAction = true
            $0.transferProgress = 0
            $0.pendingTransferRetry = BrowseFeature.TransferRetry(
                items: [incoming, second, third], destination: TestFolder.documents, operation: .copy,
                clearClipboard: true, resolution: .keepBoth
            )
        }
        gate.open()
        await BrowseFixtures.receiveCopyIntoOpenFolder(
            store,
            listed: [landed, BrowseFixtures.file(TestFile.bText, in: TestFolder.documents)],
            message: L10n.Browse.transferCopiedWithSkipped(2, 1),
            clearsClipboard: true
        )
    }

    @Test("A failed paste keeps the clipboard and shows the server's message")
    func pasteFailureKeepsTheClipboardAndSurfacesAReadableError() async {
        let state = makeState()
        state.$clipboard.withLock { $0 = FileClipboard(items: [incoming], operation: .copy) }
        let store = BrowseFixtures.store(state) {
            $0.filesClient.transferItems = { _, _, _, _, _ in throw FilesClientError.serverMessage(
                statusCode: 500,
                message: "Nope."
            ) }
        }

        await store.send(.pasteTapped(keepItemsAfterCopy: false)) {
            $0.isPerformingFileAction = true
            $0.transferProgress = 0
            $0.pendingTransferRetry = pasteRetry(clearClipboard: true)
        }
        await store.receive(\.transferResponse.failure) {
            $0.isPerformingFileAction = false
            $0.transferProgress = nil
            $0.transferErrorMessage = "Nope."
        }
    }

    @Test("Retrying a failed paste runs the same transfer again and empties the clipboard on success")
    func retryTransferReRunsTheFailedTransferAndClearsTheClipboardOnSuccess() async {
        let state = makeState()
        state.$clipboard.withLock { $0 = FileClipboard(items: [incoming], operation: .copy) }
        let attempts = LockIsolated(0)
        let gate = AsyncGate()
        let store = BrowseFixtures.store(state) {
            $0.filesClient.transferItems = { _, items, destination, _, _ in
                let attempt = attempts.withValue { value -> Int in
                    value += 1
                    return value
                }
                if attempt == 1 {
                    throw FilesClientError.serverMessage(statusCode: 500, message: "Nope.")
                }
                try await gate.wait()
                return BrowseFixtures.transferResult(items, to: destination)
            }
        }

        await store.send(.pasteTapped(keepItemsAfterCopy: false)) {
            $0.isPerformingFileAction = true
            $0.transferProgress = 0
            $0.pendingTransferRetry = pasteRetry(clearClipboard: true)
        }
        await store.receive(\.transferResponse.failure) {
            $0.isPerformingFileAction = false
            $0.transferProgress = nil
            $0.transferErrorMessage = "Nope."
        }
        await store.send(.retryTransferTapped) {
            $0.isPerformingFileAction = true
            $0.transferProgress = 0
            $0.transferErrorMessage = nil
        }
        gate.open()
        await BrowseFixtures.receiveCopyIntoOpenFolder(
            store, listed: [landed], message: L10n.Browse.transferCopied(1), clearsClipboard: true
        )
        #expect(attempts.value == 2)
    }

    @Test("Paste does nothing at the volume root")
    func pasteIsANoOpAtTheVolumeRoot() async {
        let state = makeState("")
        state.$clipboard.withLock { $0 = FileClipboard(items: [incoming], operation: .copy) }
        // No transferItems override: a request fails the test as unimplemented.
        let store = BrowseFixtures.store(state)

        await store.send(.pasteTapped(keepItemsAfterCopy: false))
    }

    @Test("Paste does nothing in a folder that is not writable")
    func pasteIsANoOpWhenTheFolderIsNotWritable() async {
        let state = makeState(access: BrowseTestSupport.readOnlyAccess)
        state.$clipboard.withLock { $0 = FileClipboard(items: [incoming], operation: .copy) }
        let store = BrowseFixtures.store(state)

        await store.send(.pasteTapped(keepItemsAfterCopy: false))
    }

    @Test("Pasting a folder into a subdirectory of itself does nothing, instead of sending a doomed request")
    func pasteIsANoOpWhenCopyingAFolderIntoASubdirectoryOfItself() async {
        // The server fails this with EINVAL ("Cannot copy to a subdirectory of self").
        let state = makeState("Media/Photos/2024")
        state.$clipboard.withLock { $0 = FileClipboard(
            items: [BrowseFixtures.folder(TestFolder.photos, in: TestFolder.media)],
            operation: .copy
        ) }
        let store = BrowseFixtures.store(state)

        await store.send(.pasteTapped(keepItemsAfterCopy: false))
    }

    // MARK: Duplicate

    @Test("Duplicate copies the selection into its own folder and lets the server number the copy")
    func duplicateCopiesTheSelectionIntoItsOwnFolderLettingTheServerRename() async {
        let original = BrowseFixtures.file(TestFile.aText, in: TestFolder.documents)
        var state = makeState()
        state.items = [original]
        state.selectedItemIDs = [original.id]
        let gate = AsyncGate()
        let requests = LockIsolated<[String]>([])
        let store = BrowseFixtures.store(state) {
            $0.filesClient.transferItems = { _, items, destination, operation, _ in
                requests
                    .withValue {
                        $0.append("\(items.map(\.id).joined(separator: ",")) to \(destination) as \(operation)")
                    }
                try await gate.wait()
                return BrowseFixtures.transferResult(items, to: destination, renamedTo: [TestFile.aText: "a 2.txt"])
            }
        }

        await store.send(.duplicateSelectionTapped) {
            $0.isPerformingFileAction = true
            $0.transferProgress = 0
            $0.pendingTransferRetry = BrowseFeature.TransferRetry(
                items: [original], destination: TestFolder.documents, operation: .copy, clearClipboard: false,
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
        #expect(requests.value == ["Documents/a.txt to Documents as copy"])
    }

    @Test("Duplicate does nothing at the root")
    func duplicateDoesNothingAtTheRoot() async {
        let volume = BrowseFixtures.folder(TestFolder.files)
        var state = makeState("")
        state.items = [volume]
        state.selectedItemIDs = [volume.id]
        let store = BrowseFixtures.store(state)

        await store.send(.duplicateSelectionTapped)
    }
}
