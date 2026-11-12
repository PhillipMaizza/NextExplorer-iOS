import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// Rename, new folder and new file. Their success answers write the shared undo stack, so the fakes
/// hold their answer until the test has asserted the send that started them.
@Suite(.isolatedDependencies)
@MainActor
struct BrowseFileOperationsTests {
    private let original = BrowseFixtures.file("vacation.jpg")
    private let renamed = BrowseFixtures.file("beach.jpg")

    private func renamingState(previewing: Bool = false) -> BrowseFeature.State {
        var state = BrowseFixtures.state(items: [original])
        state.renameSheetItem = original
        if previewing {
            state.previewItem = original
        }
        return state
    }

    // MARK: Rename

    @Test(
        "Confirming a blank or unchanged name closes the rename sheet without calling the server",
        arguments: ["   ", "vacation.jpg"]
    )
    func renameConfirmedWithNothingNewClearsTheSheetWithoutCallingTheServer(_ name: String) async {
        // No filesClient override: a rename request fails the test as unimplemented.
        let store = BrowseFixtures.store(renamingState())

        await store.send(.renameConfirmed(name)) {
            $0.renameSheetItem = nil
        }
    }

    @Test("Renaming replaces the item in place, sends the new name, and records an undo entry")
    func renameConfirmedReplacesTheRenamedItemInPlace() async {
        let gate = AsyncGate()
        let requested = LockIsolated<[String]>([])
        let store = BrowseFixtures.store(renamingState()) {
            $0.filesClient.renameItem = { _, item, name in
                requested.withValue { $0.append("\(item.id) to \(name)") }
                try await gate.wait()
                return renamed
            }
        }

        await store.send(.renameConfirmed("beach.jpg")) {
            $0.isPerformingFileAction = true
        }
        gate.open()
        await store.receive(\.renameResponse.success) {
            $0.isPerformingFileAction = false
            $0.renameSheetItem = nil
            $0.items = [renamed]
            $0.$undoStack.withLock { $0.record(FileUndoEntry(.renamed(renamed, previousName: "vacation.jpg"))) }
        }
        #expect(requested.value == ["vacation.jpg to beach.jpg"])
    }

    @Test("A failed rename shows a readable message and leaves the item as it was")
    func renameConfirmedFailureSurfacesAReadableErrorMessageAndLeavesTheItemUnchanged() async {
        let store = BrowseFixtures.store(renamingState()) {
            $0.filesClient.renameItem = { _, _, _ in throw FilesClientError.server(statusCode: 409) }
        }

        await store.send(.renameConfirmed("taken.jpg")) {
            $0.isPerformingFileAction = true
        }
        await store.receive(\.renameResponse.failure) {
            $0.isPerformingFileAction = false
            $0.fileActionErrorMessage = FilesClientError.server(statusCode: 409).userMessage
        }
    }

    @Test("Renaming the item being previewed points the cover at the renamed item without dismissing it")
    func renameConfirmedWhilePreviewingRepointsTheCoverAtTheRenamedItemWithoutDismissing() async {
        let gate = AsyncGate()
        let store = BrowseFixtures.store(renamingState(previewing: true)) {
            $0.filesClient.renameItem = { _, _, _ in
                try await gate.wait()
                return renamed
            }
        }

        await store.send(.renameConfirmed("beach.jpg")) {
            $0.isPerformingFileAction = true
        }
        gate.open()
        await store.receive(\.renameResponse.success) {
            $0.isPerformingFileAction = false
            $0.renameSheetItem = nil
            $0.items = [renamed]
            $0.previewItem = renamed
            $0.$undoStack.withLock { $0.record(FileUndoEntry(.renamed(renamed, previousName: "vacation.jpg"))) }
        }
    }

    // MARK: New folder

    @Test("Confirming a blank folder name closes the sheet without calling the server")
    func newFolderConfirmedWithABlankNameClosesTheSheetWithoutCallingTheServer() async {
        var state = BrowseFixtures.state("Docs", title: "Docs")
        state.isNewFolderSheetPresented = true
        let store = BrowseFixtures.store(state)

        await store.send(.newFolderConfirmed("   ")) {
            $0.isNewFolderSheetPresented = false
        }
    }

    @Test("A created folder is appended to the listing, written through to the cache, and recorded for undo")
    func newFolderConfirmedAppendsTheCreatedFolderOnSuccess() async {
        let existing = BrowseFixtures.file("old.txt", in: "Docs")
        let created = BrowseFixtures.folder("Reports", in: "Docs")
        var state = BrowseFixtures.state("Docs", title: "Docs", items: [existing])
        state.isNewFolderSheetPresented = true
        let gate = AsyncGate()
        let requested = LockIsolated<[String]>([])
        let store = BrowseFixtures.store(state) {
            $0.filesClient.createFolder = { _, path, name in
                requested.withValue { $0.append("\(path)/\(name)") }
                try await gate.wait()
                return created
            }
        }

        await store.send(.newFolderConfirmed("  Reports  ")) {
            $0.isPerformingFileAction = true
        }
        gate.open()
        await store.receive(\.newFolderResponse.success) {
            $0.isPerformingFileAction = false
            $0.isNewFolderSheetPresented = false
            $0.items = [existing, created]
            $0.$undoStack.withLock { $0.record(FileUndoEntry(.created([created]))) }
        }
        #expect(requested.value == ["Docs/Reports"])
    }

    @Test("A failed folder creation shows a readable message and keeps the sheet open for another try")
    func newFolderConfirmedFailureSurfacesAReadableErrorMessage() async {
        var state = BrowseFixtures.state("Docs", title: "Docs")
        state.isNewFolderSheetPresented = true
        let store = BrowseFixtures.store(state) {
            $0.filesClient.createFolder = { _, _, _ in throw FilesClientError.server(statusCode: 403) }
        }

        await store.send(.newFolderConfirmed("Reports")) {
            $0.isPerformingFileAction = true
        }
        await store.receive(\.newFolderResponse.failure) {
            $0.isPerformingFileAction = false
            $0.fileActionErrorMessage = FilesClientError.server(statusCode: 403).userMessage
        }
    }

    @Test("An in place change writes the corrected listing through to the cache, with no etag")
    func anInPlaceMutationWritesTheCorrectedListingThroughToTheCache() async {
        let cache = DirectoryCacheStore.inMemory()
        let existing = BrowseFixtures.file("Old.txt", in: "Docs")
        let newFolder = BrowseFixtures.folder("Reports", in: "Docs")
        let state = BrowseFixtures.state("Docs", title: "Docs", items: [existing], access: BrowseTestSupport.fullAccess)
        let store = BrowseFixtures.store(state) { $0.directoryCacheStore = cache }

        // A create edits this folder in place; the cache must now hold the new listing so an offline
        // revisit shows the folder, not the state before the create.
        await store.send(.newFolderResponse(.success(newFolder))) {
            $0.items = [existing, newFolder]
            $0.$undoStack.withLock { $0.record(FileUndoEntry(.created([newFolder]))) }
        }

        let cached = cache.read(serverURL: BrowseTestSupport.serverURL, path: "Docs")
        #expect(cached?.items == [existing, newFolder])
        #expect(cached?.access == BrowseTestSupport.fullAccess)
        #expect(cached?.fetchedAt == MockDate.date)
        #expect(cached?.etag == nil, "etag must be nil so the next online browse revalidates cleanly")
    }

    // MARK: New file

    @Test("Opening the new file sheet loads the server's extra editable types, and cancelling closes it")
    func newFileTappedPresentsTheSheetAndLoadsTheServersExtraFileTypes() async {
        let store = BrowseFixtures.store(BrowseFixtures.state("Docs", title: "Docs")) {
            $0.filesClient.serverFeatures = { _ in ServerFeatures(editorExtensions: ["sql"]) }
        }

        await store.send(.newFileTapped) {
            $0.isNewFileSheetPresented = true
        }
        await store.receive(\.newFileExtensionsLoaded) {
            $0.newFileServerExtensions = ["sql"]
        }
        await store.send(.newFileCancelled) {
            $0.isNewFileSheetPresented = false
        }
    }

    @Test("New file and new folder do nothing where the folder refuses them")
    func newFileAndNewFolderDoNothingWhereTheFolderRefusesThem() async {
        // An upload only share: uploads allowed, new files and folders refused.
        let access = FileAccess(
            canRead: true, canWrite: false, canUpload: true, canDelete: false, canShare: false, canDownload: false,
            canCreateFolder: false, canCreateFile: false
        )
        let store = BrowseFixtures.store(BrowseFixtures.state("Shared/Drop", title: "Drop", access: access))

        await store.send(.newFileTapped)
        await store.send(.newFolderTapped)
    }

    @Test("A created file is listed, recorded for undo, and opened in the editor once the sheet has closed")
    func newFileConfirmedCreatesTheFileAndOpensIt() async {
        let created = BrowseFixtures.file("notes.txt", in: "Docs")
        var state = BrowseFixtures.state("Docs", title: "Docs")
        state.isNewFileSheetPresented = true
        let requested = LockIsolated<[String]>([])
        let gate = AsyncGate()
        let clock = TestClock()
        let store = BrowseFixtures.store(state) {
            $0.continuousClock = clock
            $0.filesClient.createFile = { _, path, name in
                requested.withValue { $0.append("\(path)/\(name)") }
                try await gate.wait()
                return created
            }
            $0.filesClient.fetchTextContent = { _, _ in "" }
        }

        await store.send(.newFileConfirmed("  notes.txt  ")) {
            $0.isPerformingFileAction = true
        }
        gate.open()
        await store.receive(\.newFileResponse.success) {
            $0.isPerformingFileAction = false
            $0.isNewFileSheetPresented = false
            $0.items = [created]
            $0.$undoStack.withLock { $0.record(FileUndoEntry(.created([created]))) }
            $0.newlyCreatedFileID = created.id
        }
        // Opens only once the New File sheet has finished closing.
        await clock.advance(by: .milliseconds(350))
        await store.receive(.rowTapped(created)) {
            $0.previewItem = created
            $0.textPhase = .loading
        }
        await store.receive(\.textContentResponse.success) {
            $0.textPhase = .loaded
            $0.textContent = ""
        }
        await store.send(.previewDismissed) {
            $0.newlyCreatedFileID = nil
            $0.previewItem = nil
            $0.textPhase = .idle
            $0.textContent = nil
        }
        #expect(requested.value == ["Docs/notes.txt"])
    }

    @Test("A file name the editor cannot open is refused without calling the server", arguments: ["photo.jpg", "Makefile"])
    func newFileConfirmedRefusesAFileTheEditorCannotOpen(_ name: String) async {
        var state = BrowseFixtures.state("Docs", title: "Docs")
        state.isNewFileSheetPresented = true
        let store = BrowseFixtures.store(state)

        await store.send(.newFileConfirmed(name))
    }

    @Test("A failed file creation shows a readable message and keeps the sheet open")
    func newFileFailureKeepsTheSheetOpenWithAReadableError() async {
        var state = BrowseFixtures.state("Docs", title: "Docs")
        state.isNewFileSheetPresented = true
        let store = BrowseFixtures.store(state) {
            $0.filesClient.createFile = { _, _, _ in throw FilesClientError.forbidden(message: nil) }
        }

        await store.send(.newFileConfirmed("notes.md")) {
            $0.isPerformingFileAction = true
        }
        await store.receive(\.newFileResponse.failure) {
            $0.isPerformingFileAction = false
            $0.fileActionErrorMessage = FilesClientError.forbidden(message: nil).userMessage
        }
    }
}
