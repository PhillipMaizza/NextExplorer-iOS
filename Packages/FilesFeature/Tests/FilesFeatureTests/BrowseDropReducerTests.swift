import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import ShareUploads
import Testing
import TestUtils

/// The reducer side of a drop on a folder row or the folder background. A move's answer writes the
/// shared undo stack, so the fake holds it until the test has asserted the send that started the move.
@Suite(.isolatedDependencies)
@MainActor
struct BrowseDropReducerTests {
    private let archive = BrowseDropFixtures.entry(TestFolder.archive, isFolder: true)

    private func state(items: [FileItem], access: FileAccess = BrowseFixtures.writableAccess) -> BrowseFeature.State {
        BrowseFixtures.loadedState(TestFolder.docs, items: items, access: access)
    }

    private func access(canWrite: Bool = true, canUpload: Bool = true, canDelete: Bool = true) -> FileAccess {
        FileAccess(canRead: true, canWrite: canWrite, canUpload: canUpload, canDelete: canDelete, canShare: false, canDownload: true)
    }

    private func stagedFile(_ name: String) -> PickedFile {
        PickedFile(id: UUID(0), fileURL: URL(fileURLWithPath: "/tmp/\(name)"), fileName: name, size: 10)
    }

    private nonisolated func staging(_ files: [PickedFile]) -> UploadStagingClient {
        UploadStagingClient(
            stageDocuments: { _ in
                AsyncStream { continuation in
                    for file in files {
                        continuation.yield(file)
                    }
                    continuation.finish()
                }
            },
            stagePhotos: { _ in AsyncStream { $0.finish() } },
            stageCameraCapture: { _ in nil },
            discard: { _ in },
            sweepStale: {}
        )
    }

    private func movingRetry(_ items: [FileItem], to destination: String) -> BrowseFeature.TransferRetry {
        BrowseFeature.TransferRetry(items: items, destination: destination, operation: .move, clearClipboard: false)
    }

    /// A move into another folder checks that folder for name clashes, then transfers, and records
    /// where each row came from so undo can move it back.
    private func receiveMoveIntoArchive(
        _ store: TestStoreOf<BrowseFeature>, moved: [FileItem], remaining: [FileItem], gate: AsyncGate
    ) async {
        await store.receive(\.transferConflictCheckResponse) {
            $0.pendingTransferRetry?.resolution = .keepBoth
        }
        gate.open()
        await store.receive(\.transferResponse.success) {
            $0.isPerformingFileAction = false
            $0.fileActionProgressMessage = nil
            $0.pendingTransferRetry = nil
            $0.transferSuccessMessage = L10n.Browse.transferMoved(moved.count)
            $0.items = IdentifiedArray(uniqueElements: remaining)
            $0.$undoStack.withLock {
                $0.record(FileUndoEntry(.moved(moved.map {
                    FileUndoEntry.MovedItem(item: BrowseDropFixtures.entry($0.name, in: "Docs/Archive"), originalParent: TestFolder.docs)
                })))
            }
        }
        await store.receive(.delegate(.directoryContentsChanged))
    }

    @Test(
        "Dropping rows on a folder moves them all there in one request",
        arguments: [[TestFile.report], [TestFile.aPDF, "b.pdf"]]
    )
    func droppingRowsOnAFolderMovesThemThere(names: [String]) async {
        let rows = names.map { BrowseDropFixtures.entry($0) }
        let gate = AsyncGate()
        let requests = LockIsolated<[String]>([])
        let store = BrowseFixtures.store(state(items: rows + [archive])) {
            $0.filesClient.browse = { _, path in BrowseResult(items: [], access: BrowseFixtures.writableAccess, path: path) }
            $0.filesClient.transferItems = { _, items, destination, operation in
                requests.withValue { $0.append("\(operation) \(items.map(\.id)) to \(destination)") }
                try await gate.wait()
                return BrowseFixtures.transferResult(items, to: destination)
            }
        }

        await store.send(.itemsDroppedOnFolder(ids: rows.map(\.id), folder: archive)) {
            $0.isPerformingFileAction = true
            $0.fileActionProgressMessage = L10n.Browse.progressMoving
            $0.pendingTransferRetry = movingRetry(rows, to: "Docs/Archive")
        }
        await receiveMoveIntoArchive(store, moved: rows, remaining: [archive], gate: gate)
        #expect(requests.value == ["move \(rows.map(\.id)) to Docs/Archive"])
    }

    @Test("Dropping a folder on itself moves nothing")
    func droppingAFolderOnItselfMovesNothing() async {
        // No filesClient override: a transfer fails the test as unimplemented.
        let store = BrowseFixtures.store(state(items: [archive]))

        await store.send(.itemsDroppedOnFolder(ids: [archive.id], folder: archive))
    }

    @Test("Dropping a folder on its own descendant moves nothing")
    func droppingAFolderOnItsOwnDescendantMovesNothing() async {
        let nested = BrowseDropFixtures.entry("2024", in: "Docs/Archive", isFolder: true)
        let store = BrowseFixtures.store(state(items: [archive]))

        await store.send(.itemsDroppedOnFolder(ids: [archive.id], folder: nested))
    }

    @Test("Dropping rows from the same folder on the background moves nothing")
    func droppingRowsFromTheSameFolderOnTheBackgroundMovesNothing() async {
        let report = BrowseDropFixtures.entry(TestFile.report)
        let store = BrowseFixtures.store(state(items: [report]))

        await store.send(.itemsDroppedFromOtherWindow([report], destination: TestFolder.docs))
    }

    @Test("Moving rows onto a folder needs the right to delete from this one")
    func droppingOnAFolderNeedsDeleteAccess() async {
        let report = BrowseDropFixtures.entry(TestFile.report)
        let store = BrowseFixtures.store(state(items: [report, archive], access: access(canDelete: false)))

        await store.send(.itemsDroppedOnFolder(ids: [report.id], folder: archive))
    }

    @Test("Moving in rows from another window needs the right to write here")
    func droppingFromAnotherWindowNeedsWriteAccess() async {
        let store = BrowseFixtures.store(state(items: [], access: access(canWrite: false)))

        await store.send(.itemsDroppedFromOtherWindow([BrowseDropFixtures.entry("z.pdf", in: TestFolder.other)], destination: TestFolder.docs))
    }

    @Test("A name clash on the drop raises the transfer conflict prompt")
    func aNameClashOnTheDropRaisesTheTransferConflictPrompt() async {
        let report = BrowseDropFixtures.entry(TestFile.report)
        let clash = BrowseDropFixtures.entry(TestFile.report, in: "Docs/Archive")
        let store = BrowseFixtures.store(state(items: [report, archive])) {
            $0.filesClient.browse = { _, path in BrowseResult(items: [clash], access: BrowseFixtures.writableAccess, path: path) }
        }

        await store.send(.itemsDroppedOnFolder(ids: [report.id], folder: archive)) {
            $0.isPerformingFileAction = true
            $0.fileActionProgressMessage = L10n.Browse.progressMoving
            $0.pendingTransferRetry = movingRetry([report], to: "Docs/Archive")
        }
        await store.receive(\.transferConflictCheckResponse) {
            $0.isPerformingFileAction = false
            $0.fileActionProgressMessage = nil
            $0.transferConflict = BrowseFeature.TransferConflict(retry: movingRetry([report], to: "Docs/Archive"), collidingItems: [clash])
        }
    }

    @Test("A rejected move shows the server's message and keeps the row")
    func aRejectedMoveSurfacesTheServerMessage() async {
        let report = BrowseDropFixtures.entry(TestFile.report)
        let rejection = FilesClientError.forbidden(message: "Read only folder")
        let store = BrowseFixtures.store(state(items: [report, archive])) {
            $0.filesClient.browse = { _, path in BrowseResult(items: [], access: BrowseFixtures.writableAccess, path: path) }
            $0.filesClient.transferItems = { _, _, _, _ in throw rejection }
        }

        await store.send(.itemsDroppedOnFolder(ids: [report.id], folder: archive)) {
            $0.isPerformingFileAction = true
            $0.fileActionProgressMessage = L10n.Browse.progressMoving
            $0.pendingTransferRetry = movingRetry([report], to: "Docs/Archive")
        }
        await store.receive(\.transferConflictCheckResponse) {
            $0.pendingTransferRetry?.resolution = .keepBoth
        }
        await store.receive(\.transferResponse.failure) {
            $0.isPerformingFileAction = false
            $0.fileActionProgressMessage = nil
            $0.transferErrorMessage = rejection.userMessage
        }
    }

    @Test("Dropped files upload into the target folder")
    func droppedFilesUploadIntoTheTargetFolder() async {
        let url = URL(fileURLWithPath: "/tmp/a.jpg")
        let store = BrowseFixtures.store(state(items: [archive])) {
            $0.uploadStaging = staging([stagedFile(TestFile.aPhoto)])
        }

        await store.send(.filesDroppedOnFolder([url], folder: archive))
        await store.receive(\.directUploadStaged)
        await store.receive(.delegate(.uploadRequested([
            PendingUpload(id: UUID(0), fileURL: URL(fileURLWithPath: "/tmp/a.jpg"), fileName: TestFile.aPhoto, destination: "Docs/Archive"),
        ])))
    }

    @Test("Dropped files without upload rights are ignored and their staged copies deleted")
    func droppedFilesWithoutUploadRightsAreIgnoredAndTheirStagedCopiesDeleted() async throws {
        let staged = try BrowseDropFixtures.stagedCopy()
        defer { BrowseDropFixtures.removeStagedCopy(staged) }
        let store = BrowseFixtures.store(state(items: [archive], access: access(canUpload: false)))

        await store.send(.filesDroppedOnFolder([staged], folder: archive))
        await store.finish()

        #expect(!FileManager.default.fileExists(atPath: staged.path))
    }

    @Test("Dropped files on a file row are ignored")
    func droppedFilesOnAFileRowAreIgnored() async {
        let report = BrowseDropFixtures.entry(TestFile.report)
        let store = BrowseFixtures.store(state(items: [report]))

        await store.send(.filesDroppedOnFolder([URL(fileURLWithPath: "/tmp/a.jpg")], folder: report))
    }
}
