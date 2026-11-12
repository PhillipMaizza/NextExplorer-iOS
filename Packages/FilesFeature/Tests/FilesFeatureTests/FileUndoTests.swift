import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct FileUndoTests {
    private let serverURL = URL(fileURLWithPath: "/")
    private let access = FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true)
    private let now = MockDate.date.addingTimeInterval(100)

    private func folder(_ name: String, in path: String) -> FileItem {
        FileItem(name: name, path: path, dateModified: MockDate.date, size: 0, kind: "directory")
    }

    private func state(_ path: String, items: [FileItem]) -> BrowseFeature.State {
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: path, title: path)
        state.items = IdentifiedArray(uniqueElements: items)
        state.access = access
        state.phase = .loaded
        return state
    }

    private func store(
        _ state: BrowseFeature.State,
        configure: (inout DependencyValues) -> Void
    ) -> TestStoreOf<BrowseFeature> {
        TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.date = .constant(now)
            configure(&$0)
        }
    }

    /// The transfer and rename responses write the shared undo stack, so the fakes hold their answer
    /// until the test has asserted the send that started them.
    @Test
    func aDuplicateShowsInTheListingAtOnceAndUndoDeletesIt() async {
        let misc = folder("Misc", in: "Docs")
        var initial = state("Docs", items: [misc])
        initial.selectedItemIDs = [misc.id]
        let copy = FileItem(name: "Misc (2)", path: "Docs", dateModified: now, size: 0, kind: "directory")
        let deleted = LockIsolated<[FileItem]>([])
        let gate = AsyncGate()

        let store = store(initial) {
            $0.filesClient.transferItems = { _, _, destination, _ in
                try await gate.wait()
                return TransferResult(destination: destination, items: [.init(from: "Docs/Misc", to: "Docs/Misc (2)")])
            }
            $0.filesClient.deleteItems = { _, items in deleted.setValue(items) }
        }

        await store.send(.duplicateSelectionTapped) {
            $0.isPerformingFileAction = true
            $0.fileActionProgressMessage = L10n.Browse.progressCopying
            $0.pendingTransferRetry = BrowseFeature.TransferRetry(
                items: [misc], destination: "Docs", operation: .copy, clearClipboard: false,
                resolution: .keepBoth, itemsToReplace: []
            )
        }
        gate.open()
        await store.receive(\.transferResponse.success) {
            $0.isPerformingFileAction = false
            $0.fileActionProgressMessage = nil
            $0.pendingTransferRetry = nil
            $0.transferSuccessMessage = L10n.Browse.transferCopied(1)
            $0.items = IdentifiedArray(uniqueElements: [misc, copy])
            $0.$undoStack.withLock { $0 = [FileUndoEntry(.created([copy]))] }
            $0.awaitedArrivalIDs = ["Docs/Misc (2)"]
            $0.arrivalChecksLeft = 3
        }
        await store.receive(.delegate(.directoryContentsChanged))

        await store.send(.undoTapped) {
            $0.$undoStack.withLock { $0 = [] }
            $0.isPerformingFileAction = true
        }
        await store.receive(\.undoResponse.success) { $0.isPerformingFileAction = false }
        await store.receive(.delegate(.directoryContentsChanged))
        await store.finish()

        #expect(deleted.value.map(\.id) == ["Docs/Misc (2)"])
    }

    @Test
    func undoingAMoveMovesTheItemsBackToWhereTheyCameFrom() async {
        let report = FileItem(name: "report.pdf", path: "Docs", dateModified: now, size: 10, kind: "pdf")
        let archive = folder("Archive", in: "Docs")
        let movedReport = FileItem(name: "report.pdf", path: "Docs/Archive", dateModified: now, size: 10, kind: "pdf")
        let moves = LockIsolated<[[String]]>([])
        let destinations = LockIsolated<[String]>([])
        let gate = AsyncGate()
        let access = access

        let store = store(state("Docs", items: [report, archive])) {
            $0.filesClient.browse = { _, path in BrowseResult(items: [], access: access, path: path) }
            $0.filesClient.transferItems = { _, items, destination, _ in
                try await gate.wait()
                moves.withValue { $0.append(items.map(\.id)) }
                destinations.withValue { $0.append(destination) }
                return TransferResult(destination: destination, items: items.map {
                    .init(from: $0.id, to: "\(destination)/\($0.name)")
                })
            }
        }
        let retry = BrowseFeature.TransferRetry(
            items: [report], destination: "Docs/Archive", operation: .move, clearClipboard: false
        )

        await store.send(.itemsDroppedOnFolder(ids: [report.id], folder: archive)) {
            $0.isPerformingFileAction = true
            $0.fileActionProgressMessage = L10n.Browse.progressMoving
            $0.pendingTransferRetry = retry
        }
        await store.receive(\.transferConflictCheckResponse.success) {
            $0.pendingTransferRetry = retry.resolved(.keepBoth)
        }
        gate.open()
        await store.receive(\.transferResponse.success) {
            $0.isPerformingFileAction = false
            $0.fileActionProgressMessage = nil
            $0.pendingTransferRetry = nil
            $0.transferSuccessMessage = L10n.Browse.transferMoved(1)
            $0.items = IdentifiedArray(uniqueElements: [archive])
            $0.$undoStack.withLock {
                $0 = [FileUndoEntry(.moved([FileUndoEntry.MovedItem(item: movedReport, originalParent: "Docs")]))]
            }
        }
        await store.receive(.delegate(.directoryContentsChanged))

        await store.send(.undoTapped) {
            $0.$undoStack.withLock { $0 = [] }
            $0.isPerformingFileAction = true
        }
        await store.receive(\.undoResponse.success) { $0.isPerformingFileAction = false }
        await store.receive(.delegate(.directoryContentsChanged))
        await store.finish()

        #expect(moves.value == [["Docs/report.pdf"], ["Docs/Archive/report.pdf"]])
        #expect(destinations.value == ["Docs/Archive", "Docs"])
    }

    @Test
    func undoingARenameRestoresTheOldName() async {
        let original = FileItem(name: "vacation.jpg", path: "Photos", dateModified: now, size: 0, kind: "jpg")
        let renamedItem = FileItem(name: "beach.jpg", path: "Photos", dateModified: now, size: 0, kind: "jpg")
        var initial = state("Photos", items: [original])
        initial.renameSheetItem = original
        let renames = LockIsolated<[String]>([])
        let gate = AsyncGate()

        let store = store(initial) {
            $0.filesClient.renameItem = { _, item, newName in
                try await gate.wait()
                renames.withValue { $0.append("\(item.id)>\(newName)") }
                return item.id == renamedItem.id ? original : renamedItem
            }
        }

        await store.send(.renameConfirmed("beach.jpg")) { $0.isPerformingFileAction = true }
        gate.open()
        await store.receive(\.renameResponse.success) {
            $0.isPerformingFileAction = false
            $0.renameSheetItem = nil
            $0.items = IdentifiedArray(uniqueElements: [renamedItem])
            $0.$undoStack.withLock { $0 = [FileUndoEntry(.renamed(renamedItem, previousName: "vacation.jpg"))] }
        }

        await store.send(.undoTapped) {
            $0.$undoStack.withLock { $0 = [] }
            $0.isPerformingFileAction = true
        }
        await store.receive(\.undoResponse.success) { $0.isPerformingFileAction = false }
        await store.receive(.delegate(.directoryContentsChanged))
        await store.finish()

        #expect(renames.value == ["Photos/vacation.jpg>beach.jpg", "Photos/beach.jpg>vacation.jpg"])
    }

    @Test
    func nothingToUndoDoesNothing() async {
        let store = store(state("Docs", items: [])) { _ in }
        await store.send(.undoTapped)
    }
}
