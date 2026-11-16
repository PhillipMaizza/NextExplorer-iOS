import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

/// ⇧⌘Z: an undone move, rename or new item is done again and goes back on the undo stack; a new
/// operation ends the redo history; copies are never redone.
@Suite(.isolatedDependencies)
@MainActor
struct FileRedoTests {
    private enum Constants {
        static let archivePath = "Docs/Archive"
        static let newFolderName = "Untitled Folder"
        static let newFolderTakenName = "Untitled Folder 2"
        static let renamedName = "beach.jpg"
    }

    private let serverURL = URL(fileURLWithPath: "/")
    private let movedReport = FileItem(
        name: TestFile.report,
        path: Constants.archivePath,
        dateModified: MockDate.date,
        size: 10,
        kind: TestKind.pdf
    )
    private let renamedPhoto = FileItem(
        name: Constants.renamedName,
        path: TestFolder.photos,
        dateModified: MockDate.date,
        size: 0,
        kind: TestKind.photo
    )

    private func folder(_ name: String) -> FileItem {
        FileItem(name: name, path: TestFolder.docs, dateModified: MockDate.date, size: 0, kind: FileItem.directoryKind)
    }

    private func store(
        undo: [FileUndoEntry] = [],
        redo: [FileUndoEntry] = [],
        configure: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<BrowseFeature> {
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: TestFolder.docs, title: TestFolder.docs)
        state.phase = .loaded
        state.$undoStack.withLock { $0 = undo }
        state.$redoStack.withLock { $0 = redo }
        return TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.date = .constant(MockDate.date)
            configure(&$0)
        }
    }

    @Test
    func redoingAnUndoneMoveMovesTheItemsBackToWhereTheyWent() async {
        let entry = FileUndoEntry(.moved([FileUndoEntry.MovedItem(item: movedReport, originalParent: TestFolder.docs)]))
        let moves = LockIsolated<[String]>([])
        let store = store(redo: [entry]) {
            $0.filesClient.transferItems = { _, items, destination, operation in
                moves.withValue { $0 += items.map { "\($0.id)>\(destination) \(operation)" } }
                return TransferResult(destination: destination, items: [])
            }
        }

        await store.send(.redoTapped) {
            $0.$redoStack.withLock { $0 = [] }
            $0.isPerformingFileAction = true
        }
        await store.receive(\.redoResponse.success) {
            $0.isPerformingFileAction = false
            $0.$undoStack.withLock { $0 = [entry] }
        }
        await store.receive(.delegate(.directoryContentsChanged))

        #expect(moves.value == ["Docs/report.pdf>Docs/Archive move"])
    }

    @Test
    func redoingAnUndoneRenameRenamesItAgain() async {
        let entry = FileUndoEntry(.renamed(renamedPhoto, previousName: TestFile.vacationPhoto))
        let renames = LockIsolated<[String]>([])
        let store = store(redo: [entry]) {
            $0.filesClient.renameItem = { _, item, newName in
                renames.withValue { $0.append("\(item.id)>\(newName)") }
                return item
            }
        }

        await store.send(.redoTapped) {
            $0.$redoStack.withLock { $0 = [] }
            $0.isPerformingFileAction = true
        }
        await store.receive(\.redoResponse.success) {
            $0.isPerformingFileAction = false
            $0.$undoStack.withLock { $0 = [entry] }
        }
        await store.receive(.delegate(.directoryContentsChanged))

        #expect(renames.value == ["Photos/vacation.jpg>beach.jpg"])
    }

    @Test
    func undoingANewFolderDeletesItAndRedoMakesItAgain() async {
        let made = folder(Constants.newFolderName)
        let remade = folder(Constants.newFolderTakenName)
        let deleted = LockIsolated<[String]>([])
        let created = LockIsolated<[String]>([])
        let store = store(undo: [FileUndoEntry(.madeNew(made))]) {
            $0.filesClient.deleteItems = { _, items in deleted.withValue { $0 += items.map(\.id) } }
            $0.filesClient.createFolder = { _, path, name in
                created.withValue { $0.append("\(path)/\(name)") }
                return remade
            }
        }

        await store.send(.undoTapped) {
            $0.$undoStack.withLock { $0 = [] }
            $0.isPerformingFileAction = true
        }
        await store.receive(\.undoResponse.success) {
            $0.isPerformingFileAction = false
            $0.$redoStack.withLock { $0 = [FileUndoEntry(.madeNew(made))] }
        }
        await store.receive(.delegate(.directoryContentsChanged))

        await store.send(.redoTapped) {
            $0.$redoStack.withLock { $0 = [] }
            $0.isPerformingFileAction = true
        }
        // The server may pick another name: the next undo deletes what it made this time.
        await store.receive(\.redoResponse.success) {
            $0.isPerformingFileAction = false
            $0.$undoStack.withLock { $0 = [FileUndoEntry(.madeNew(remade))] }
        }
        await store.receive(.delegate(.directoryContentsChanged))

        #expect(deleted.value == ["Docs/Untitled Folder"])
        #expect(created.value == ["Docs/Untitled Folder"])
    }

    @Test
    func anUndoneCopyIsNeverOfferedForRedo() async {
        let copy = folder(Constants.newFolderName)
        let store = store(undo: [FileUndoEntry(.created([copy]))]) {
            $0.filesClient.deleteItems = { _, _ in }
        }

        await store.send(.undoTapped) {
            $0.$undoStack.withLock { $0 = [] }
            $0.isPerformingFileAction = true
        }
        await store.receive(\.undoResponse.success) { $0.isPerformingFileAction = false }
        await store.receive(.delegate(.directoryContentsChanged))
    }

    @Test
    func aNewOperationEndsTheRedoHistory() async {
        let made = folder(Constants.newFolderName)
        let pending = FileUndoEntry(.renamed(renamedPhoto, previousName: TestFile.vacationPhoto))
        let store = store(redo: [pending])
        store.exhaustivity = .off

        await store.send(.newFolderResponse(.success(made))) {
            $0.$undoStack.withLock { $0 = [FileUndoEntry(.madeNew(made))] }
            $0.$redoStack.withLock { $0 = [] }
        }
    }

    @Test
    func aFailedRedoSaysWhyAndKeepsNothingToUndo() async {
        let entry = FileUndoEntry(.renamed(renamedPhoto, previousName: TestFile.vacationPhoto))
        let store = store(redo: [entry]) {
            $0.filesClient.renameItem = { _, _, _ in throw FilesClientError.offline }
        }

        await store.send(.redoTapped) {
            $0.$redoStack.withLock { $0 = [] }
            $0.isPerformingFileAction = true
        }
        await store.receive(\.redoResponse.failure) {
            $0.isPerformingFileAction = false
            $0.fileActionErrorMessage = FilesClientError.offline.userMessage
        }
        await store.receive(.delegate(.directoryContentsChanged))
    }

    @Test
    func nothingToRedoDoesNothing() async {
        let store = store()
        await store.send(.redoTapped)
    }
}
