import CoreModels
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

private let receiver = BrowseDropFixtures.receiver

/// Staging copies of dropped files so an upload can read them after the drop session ends, and
/// deleting those copies when no upload takes them over.
@Suite(.isolatedDependencies)
struct BrowseDropStagingTests {
    private func temporaryFile(_ prefix: String, contents: String = "x") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(TestID.name()).txt")
        try Data(contents.utf8).write(to: url)
        return url
    }

    @Test("Copying a dropped file keeps its own name and its contents")
    func stagingCopiesADroppedFileUnderItsOwnName() throws {
        let source = try temporaryFile("drop", contents: "hello")
        defer { try? FileManager.default.removeItem(at: source) }

        let copy = try DroppedFileStaging.copy(source)
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }

        #expect(copy.lastPathComponent == source.lastPathComponent)
        #expect(copy != source)
        #expect(try String(contentsOf: copy, encoding: .utf8) == "hello")
    }

    @Test("Copying a missing file throws")
    func stagingAMissingFileThrows() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(TestID.name())")

        #expect(throws: (any Error).self) {
            _ = try DroppedFileStaging.copy(missing)
        }
    }

    @Test("A temporary system copy is moved, not copied")
    func aTemporarySystemCopyIsMovedNotCopied() throws {
        let source = try temporaryFile("system")

        let staged = try DroppedFileStaging.stage(source, isOriginal: false)
        defer { DroppedFileStaging.discardCopy(at: staged) }

        #expect(FileManager.default.fileExists(atPath: staged.path))
        #expect(!FileManager.default.fileExists(atPath: source.path))
    }

    @Test("An original file is copied and left where it was")
    func anOriginalFileIsCopiedAndLeftWhereItWas() throws {
        let source = try temporaryFile("original")
        defer { try? FileManager.default.removeItem(at: source) }

        let staged = try DroppedFileStaging.stage(source, isOriginal: true)
        defer { DroppedFileStaging.discardCopy(at: staged) }

        #expect(FileManager.default.fileExists(atPath: staged.path))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test("A failed stage leaves no empty folder behind")
    func aFailedStageLeavesNoEmptyFolderBehind() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "stage-root-\(TestID.name())",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let isolated = IsolatedTemporaryFileManager(root: root)
        let missing = root.appendingPathComponent("missing.txt")

        #expect(throws: (any Error).self) { try DroppedFileStaging.stage(
            missing,
            isOriginal: false,
            fileManager: isolated
        ) }

        let staging = DroppedFileStaging.directory(in: root)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? []
        #expect(leftovers.isEmpty)
    }

    @Test("A staged copy is deleted once upload staging took its own, and the source stays")
    func aStagedDropCopyIsDeletedOnceUploadStagingTookItsOwn() throws {
        let source = try temporaryFile("drop")
        defer { try? FileManager.default.removeItem(at: source) }
        let copy = try DroppedFileStaging.copy(source)

        DroppedFileStaging.discardCopy(at: copy)

        #expect(!FileManager.default.fileExists(atPath: copy.deletingLastPathComponent().path))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test("Discarding a file outside the drop directory leaves it alone")
    func discardingAFileOutsideTheDropDirectoryLeavesItAlone() throws {
        let outside = try temporaryFile("outside")
        defer { try? FileManager.default.removeItem(at: outside) }

        DroppedFileStaging.discardCopy(at: outside)

        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test("The stale sweep removes old drop copies and keeps fresh ones")
    func theStaleSweepRemovesOldDropCopiesAndKeepsFreshOnes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "sweep-\(TestID.name())",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent(TestValue.outdated, isDirectory: true)
        let fresh = root.appendingPathComponent("fresh", isDirectory: true)
        for url in [old, fresh] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let staleness: TimeInterval = 3_600
        try FileManager.default.setAttributes(
            [.modificationDate: MockDate.date.addingTimeInterval(-staleness)],
            ofItemAtPath: old.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: MockDate.date.addingTimeInterval(staleness)],
            ofItemAtPath: fresh.path
        )

        UploadStagingLocation.sweepStale(in: [root], olderThan: MockDate.date)

        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
    }
}

/// A file manager whose temporary directory is a folder of the test's own, so staging tests running
/// in parallel never see each other's folders.
private final class IsolatedTemporaryFileManager: FileManager, @unchecked Sendable {
    private let root: URL

    init(root: URL) {
        self.root = root
        super.init()
    }

    override var temporaryDirectory: URL {
        root
    }
}

/// Which staged copies a drop deletes at once: those no action takes over.
@Suite(.isolatedDependencies)
struct BrowseDropHandlerTests {
    private let folder = BrowseDropFixtures.entry(TestFolder.archive, isFolder: true)

    private func resolve(
        folder: FileItem?, files: [URL], canMove: Bool = true, canUpload: Bool
    ) -> BrowseDropHandler.Resolution {
        BrowseDropHandler.resolve(
            drops: files.map(BrowseDrop.file),
            folder: folder,
            listed: [],
            directoryPath: TestFolder.docs,
            receiver: receiver,
            canMove: canMove,
            canUpload: canUpload
        )
    }

    @Test("A refused drop leaves no staged copy")
    func aRefusedDropLeavesNoStagedCopy() throws {
        let staged = try BrowseDropFixtures.stagedCopy()
        defer { BrowseDropFixtures.removeStagedCopy(staged) }

        let resolution = resolve(folder: folder, files: [staged], canUpload: false)
        #expect(resolution.actions.isEmpty)
        BrowseDropHandler.discard(resolution.discardedFiles)

        #expect(!FileManager.default.fileExists(atPath: staged.path))
    }

    @Test("A drop on a file row leaves no staged copy")
    func aDropOnAFileRowLeavesNoStagedCopy() throws {
        let staged = try BrowseDropFixtures.stagedCopy()
        defer { BrowseDropFixtures.removeStagedCopy(staged) }

        let resolution = resolve(folder: BrowseDropFixtures.entry(TestFile.report), files: [staged], canUpload: true)
        BrowseDropHandler.discard(resolution.discardedFiles)

        #expect(resolution.actions.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: staged.path))
    }

    @Test("An accepted drop keeps the staged copy for the upload")
    func anAcceptedDropKeepsTheStagedCopyForTheUpload() throws {
        let staged = try BrowseDropFixtures.stagedCopy()
        defer { BrowseDropFixtures.removeStagedCopy(staged) }

        let resolution = resolve(folder: folder, files: [staged], canUpload: true)
        BrowseDropHandler.discard(resolution.discardedFiles)

        #expect(resolution.actions == [.filesDroppedOnFolder([staged], folder: folder)])
        #expect(resolution.discardedFiles.isEmpty)
        #expect(FileManager.default.fileExists(atPath: staged.path))
    }

    @Test("A background drop without upload rights discards the copy")
    func aBackgroundDropWithoutUploadRightsDiscardsTheCopy() throws {
        let staged = try BrowseDropFixtures.stagedCopy()
        defer { BrowseDropFixtures.removeStagedCopy(staged) }

        let resolution = resolve(folder: nil, files: [staged], canUpload: false)

        #expect(resolution.actions.isEmpty)
        #expect(resolution.discardedFiles == [staged])
    }

    @Test("Only the files no action took over are discarded")
    func onlyTheFilesNoActionTookOverAreDiscarded() throws {
        let staged = try BrowseDropFixtures.stagedCopy()
        defer { BrowseDropFixtures.removeStagedCopy(staged) }
        let foreign = BrowseDropFixtures.entry("z.pdf", in: TestFolder.other)

        let resolution = BrowseDropHandler.resolve(
            drops: [.items([foreign], origin: receiver), .file(staged)],
            folder: folder, listed: [], directoryPath: TestFolder.docs, receiver: receiver, canMove: true,
            canUpload: false
        )

        #expect(resolution.actions == [.itemsDroppedFromOtherWindow([foreign], destination: folder.id)])
        #expect(resolution.discardedFiles == [staged])
    }
}
