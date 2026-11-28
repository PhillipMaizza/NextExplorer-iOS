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
struct BrowseTrashUndoTests {
    private enum Constants {
        static let folderPath = "Docs"
        static let firstTrashID = "t1"
        static let secondTrashID = "t2"
        static let restoredName = "vacation 2.jpg"
    }

    private let photo = BrowseFixtures.file(TestFile.vacationPhoto, in: Constants.folderPath)
    private let notes = BrowseFixtures.file(TestFile.aText, in: Constants.folderPath)

    @Test("Undo after Move to Trash restores the item and selects it; Redo puts it back in the trash")
    func undoRestoresAndRedoTrashesAgain() async {
        var state = BrowseFixtures.loadedState(Constants.folderPath, items: [photo, notes])
        state.deleteConfirmationItem = photo
        let restored = LockIsolated<[TrashTarget]>([])
        let deletes = LockIsolated<[Bool]>([])
        let trashID = LockIsolated(Constants.firstTrashID)
        let store = BrowseFixtures.store(state) {
            $0.directoryCacheStore = .inMemory()
            $0.filesClient.deleteItems = { _, items, permanent, _ in
                deletes.withValue { $0.append(permanent) }
                return DeleteOutcome(items: items.map {
                    .init(path: $0.id, status: .trashed, trashItemID: trashID.value)
                })
            }
            $0.filesClient.restoreTrash = { _, target, _, _, _ in
                restored.withValue { $0.append(target) }
                return TrashActionResult(items: [.init(key: Constants.firstTrashID, status: .restored)])
            }
        }
        let trashed = FileUndoEntry(.trashed([.init(item: photo, trashID: Constants.firstTrashID)]))

        await store.send(.deleteConfirmed) {
            $0.deleteConfirmationItem = nil
            $0.isPerformingFileAction = true
        }
        await store.receive(\.deleteResponse.success) {
            $0.isPerformingFileAction = false
            $0.items = [notes]
            $0.trashNotice = .init(count: 1, sequence: 1)
            $0.$undoStack.withLock { $0 = [trashed] }
        }

        await store.send(.undoTapped) {
            $0.$undoStack.withLock { $0 = [] }
            $0.isPerformingFileAction = true
        }
        await store.receive(\.undoResponse.success) {
            $0.isPerformingFileAction = false
            $0.$redoStack.withLock { $0 = [trashed] }
            $0.reveal = .select(photo.id)
        }
        await store.receive(.delegate(.directoryContentsChanged))
        #expect(restored.value == [.items([Constants.firstTrashID])])

        trashID.setValue(Constants.secondTrashID)
        await store.send(.redoTapped) {
            $0.$redoStack.withLock { $0 = [] }
            $0.isPerformingFileAction = true
        }
        await store.receive(\.redoResponse.success) {
            $0.isPerformingFileAction = false
            $0.$undoStack.withLock {
                $0 = [FileUndoEntry(.trashed([.init(item: photo, trashID: Constants.secondTrashID)]))]
            }
        }
        await store.receive(.delegate(.directoryContentsChanged))
        #expect(deletes.value == [false, false])
    }

    @Test("A restore the server renamed is redone under its new name; one it did not restore is left out")
    func restoredPairsByTrashIDAndTakesTheNewName() throws {
        let entry = try BrowseFeature.restored(
            [.init(item: photo, trashID: Constants.firstTrashID), .init(item: notes, trashID: Constants.secondTrashID)],
            by: TrashActionResult(items: [
                .init(key: Constants.secondTrashID, status: .blocked),
                .init(key: Constants.firstTrashID, status: .restored, restoredName: Constants.restoredName),
            ])
        )

        #expect(entry == FileUndoEntry(.trashed([
            .init(item: photo.changing(name: Constants.restoredName), trashID: Constants.firstTrashID),
        ])))
    }

    @Test("Undo that restores nothing says why and leaves nothing to redo")
    func undoThatRestoresNothingSaysWhy() async {
        var state = BrowseFixtures.loadedState(Constants.folderPath, items: [notes])
        state.$undoStack
            .withLock { $0 = [FileUndoEntry(.trashed([.init(item: photo, trashID: Constants.firstTrashID)]))] }
        let store = BrowseFixtures.store(state) {
            $0.filesClient.restoreTrash = { _, _, _, _, _ in
                TrashActionResult(items: [.init(key: Constants.firstTrashID, status: .blocked)])
            }
        }

        await store.send(.undoTapped) {
            $0.$undoStack.withLock { $0 = [] }
            $0.isPerformingFileAction = true
        }
        await store.receive(\.undoResponse.failure) {
            $0.isPerformingFileAction = false
            $0.fileActionErrorMessage = L10n.Trash.failureBlocked
        }
        await store.receive(.delegate(.directoryContentsChanged))
        #expect(store.state.redoStack.isEmpty)
    }

    @Test("A permanent delete leaves nothing to undo")
    func permanentDeleteRecordsNoUndo() async {
        var state = BrowseFixtures.loadedState(Constants.folderPath, items: [photo])
        state.deleteConfirmationItem = photo
        let store = BrowseFixtures.store(state) {
            $0.directoryCacheStore = .inMemory()
            $0.filesClient.deleteItems = { _, items, _, _ in
                DeleteOutcome(items: items.map { .init(path: $0.id, status: .deleted) })
            }
        }

        await store.send(.deletePermanentlyConfirmed(fromPreview: false)) {
            $0.deleteConfirmationItem = nil
            $0.isPerformingFileAction = true
        }
        await store.receive(\.deleteResponse.success) {
            $0.isPerformingFileAction = false
            $0.items = []
        }
        #expect(store.state.undoStack.isEmpty)
    }
}
