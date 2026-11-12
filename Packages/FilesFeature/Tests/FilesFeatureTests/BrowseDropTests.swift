import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

private let serverURL = URL(string: "https://example.com") ?? URL(fileURLWithPath: "/")
private let fixedDate = Date(timeIntervalSince1970: 100)
private let receiver = DragOrigin(serverURL: serverURL.absoluteString, scope: "scope-a")

private func entry(_ name: String, in path: String = "Docs", isFolder: Bool = false) -> FileItem {
    FileItem(name: name, path: path, dateModified: fixedDate, size: 10, kind: isFolder ? "directory" : "pdf")
}

struct BrowseDragPayloadTests {
    @Test
    func referenceSurvivesAnEncodeDecodeRoundTrip() throws {
        let report = entry("report.pdf")
        let reference = ServerItemReference(dragging: report, selection: [report, entry("b.pdf")])

        let decoded = try JSONDecoder().decode(ServerItemReference.self, from: JSONEncoder().encode(reference))

        #expect(decoded.id == report.id)
        #expect(decoded.items.map(\.id) == ["Docs/report.pdf", "Docs/b.pdf"])
    }

    @Test
    func referenceWrittenByTheMacPathWithoutABatchStillDecodes() throws {
        let json = Data(#"{"id":"Docs/a.pdf"}"#.utf8)

        let decoded = try JSONDecoder().decode(ServerItemReference.self, from: json)

        #expect(decoded.id == "Docs/a.pdf")
        #expect(decoded.items.isEmpty)
    }

    @Test
    func draggingARowOutsideTheSelectionCarriesOnlyThatRow() {
        let outside = entry("outside.pdf")
        let reference = ServerItemReference(dragging: outside, selection: [entry("a.pdf"), entry("b.pdf")])

        #expect(reference.items == [outside])
    }

    @Test
    func draggingTheOnlySelectedRowCarriesOnlyThatRow() {
        let only = entry("a.pdf")

        #expect(ServerItemReference(dragging: only, selection: [only]).items == [only])
        #expect(ServerItemReference(dragging: only).items == [only])
    }

    @Test
    func aBatchListsEachRowOnce() {
        let a = entry("a.pdf")
        let reference = ServerItemReference(id: a.id, item: a, batch: [a, a, entry("b.pdf")])

        #expect(reference.items.map(\.name) == ["a.pdf", "b.pdf"])
    }

    @Test
    func stagingCopiesADroppedFileUnderItsOwnName() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("drop-\(TestID.name()).txt")
        try Data("hello".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let copy = try DroppedFileStaging.copy(source)
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }

        #expect(copy.lastPathComponent == source.lastPathComponent)
        #expect(copy != source)
        #expect(try String(contentsOf: copy, encoding: .utf8) == "hello")
    }

    @Test
    func stagingAMissingFileThrows() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(TestID.name())")

        #expect(throws: (any Error).self) {
            _ = try DroppedFileStaging.copy(missing)
        }
    }
}

struct BrowseDropPlanTests {
    @Test
    func listedRowsMoveByIDAndOthersByValue() {
        let listed = entry("a.pdf")
        let foreign = entry("z.pdf", in: "Other")
        let plan = BrowseDropPlan(drops: [.items([listed, foreign], origin: receiver)], listed: [listed.id], destination: "Docs/Archive", receiver: receiver)

        #expect(plan.listedIDs == [listed.id])
        #expect(plan.foreignItems == [foreign])
        #expect(plan.fileURLs.isEmpty)
    }

    @Test
    func aFolderDroppedOnItselfIsRefused() {
        let folder = entry("Archive", isFolder: true)
        let plan = BrowseDropPlan(drops: [.items([folder], origin: receiver)], listed: [folder.id], destination: folder.id, receiver: receiver)

        #expect(plan.isEmpty)
    }

    @Test
    func aFolderDroppedOnADescendantIsRefused() {
        let folder = entry("Archive", isFolder: true)
        let plan = BrowseDropPlan(drops: [.items([folder], origin: receiver)], listed: [folder.id], destination: "Docs/Archive/2024/Q1", receiver: receiver)

        #expect(plan.isEmpty)
    }

    @Test
    func aFolderWhoseNameOnlySharesAPrefixIsNotAnAncestor() {
        let folder = entry("Arch", isFolder: true)
        let plan = BrowseDropPlan(drops: [.items([folder], origin: receiver)], listed: [folder.id], destination: "Docs/Archive", receiver: receiver)

        #expect(plan.listedIDs == [folder.id])
    }

    @Test
    func rowsAlreadyInTheDestinationAreANoOp() {
        let inside = entry("a.pdf", in: "Docs/Archive")
        let plan = BrowseDropPlan(drops: [.items([inside], origin: receiver)], listed: [], destination: "Docs/Archive", receiver: receiver)

        #expect(plan.isEmpty)
    }

    @Test
    func theSameRowDroppedTwiceMovesOnce() {
        let a = entry("a.pdf")
        let plan = BrowseDropPlan(drops: [.items([a], origin: receiver), .items([a], origin: receiver)], listed: [a.id], destination: "Docs/Archive", receiver: receiver)

        #expect(plan.listedIDs == [a.id])
    }

    @Test
    func onlyFileURLsAreUploaded() throws {
        let local = URL(fileURLWithPath: "/tmp/a.jpg")
        let remote = try #require(URL(string: "https://example.com/a.jpg"))
        let plan = BrowseDropPlan(drops: [.file(local), .file(remote)], listed: [], destination: "Docs", receiver: receiver)

        #expect(plan.fileURLs == [local])
    }
}

struct BrowseDropRouterTests {
    private let folder = entry("Archive", isFolder: true)
    private let local = URL(fileURLWithPath: "/tmp/a.jpg")

    @Test
    func aFolderDropSendsMovesAndUploadsToTheFolder() {
        let foreign = entry("z.pdf", in: "Other")
        let plan = BrowseDropPlan(
            drops: [.items([entry("a.pdf"), foreign], origin: receiver), .file(local)],
            listed: ["Docs/a.pdf"],
            destination: folder.id,
            receiver: receiver
        )

        let actions = BrowseDropRouter.actions(for: plan, folder: folder, directoryPath: "Docs", canMove: true, canUpload: true)

        #expect(actions == [
            .itemsDroppedOnFolder(ids: ["Docs/a.pdf"], folder: folder),
            .itemsDroppedFromOtherWindow([foreign], destination: folder.id),
            .filesDroppedOnFolder([local], folder: folder),
        ])
    }

    @Test
    func withoutRightsNothingIsSent() {
        let plan = BrowseDropPlan(drops: [.items([entry("a.pdf")], origin: receiver), .file(local)], listed: ["Docs/a.pdf"], destination: folder.id, receiver: receiver)

        #expect(BrowseDropRouter.actions(for: plan, folder: folder, directoryPath: "Docs", canMove: false, canUpload: false).isEmpty)
    }

    @Test
    func aFileIsNotAFolderDropTarget() {
        let file = entry("a.pdf")
        let plan = BrowseDropPlan(drops: [.file(local)], listed: [], destination: file.id, receiver: receiver)

        #expect(BrowseDropRouter.actions(for: plan, folder: file, directoryPath: "Docs", canMove: true, canUpload: true).isEmpty)
    }

    @Test
    func theBackgroundUploadsThroughTheRegularFlow() {
        let plan = BrowseDropPlan(drops: [.file(local)], listed: [], destination: "Docs", receiver: receiver)

        let actions = BrowseDropRouter.actions(for: plan, folder: nil, directoryPath: "Docs", canMove: true, canUpload: true)

        #expect(actions == [.beginUpload(.documents([local]))])
    }

    @Test
    func theBackgroundMovesRowsFromAnotherWindowIntoTheFolderOnScreen() {
        let foreign = entry("z.pdf", in: "Other")
        let plan = BrowseDropPlan(drops: [.items([foreign], origin: receiver)], listed: [], destination: "Docs", receiver: receiver)

        let actions = BrowseDropRouter.actions(for: plan, folder: nil, directoryPath: "Docs", canMove: true, canUpload: true)

        #expect(actions == [.itemsDroppedFromOtherWindow([foreign], destination: "Docs")])
    }

    @Test
    func theBackgroundIgnoresRowsFromTheSameFolder() {
        let plan = BrowseDropPlan(drops: [.items([entry("a.pdf")], origin: receiver)], listed: ["Docs/a.pdf"], destination: "Docs", receiver: receiver)

        #expect(BrowseDropRouter.actions(for: plan, folder: nil, directoryPath: "Docs", canMove: true, canUpload: true).isEmpty)
    }

    @Test
    func theRootListingTakesNoMovedRows() {
        let foreign = entry("z.pdf", in: "Other")
        let plan = BrowseDropPlan(drops: [.items([foreign], origin: receiver)], listed: [], destination: "", receiver: receiver)

        #expect(BrowseDropRouter.actions(for: plan, folder: nil, directoryPath: "", canMove: true, canUpload: true).isEmpty)
    }
}

@Suite(.isolatedDependencies)
@MainActor
struct BrowseDropReducerTests {
    private let access = FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true)

    private func state(items: [FileItem], access: FileAccess? = nil) -> BrowseFeature.State {
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "Docs", title: "Docs")
        state.items = IdentifiedArray(uniqueElements: items)
        state.access = access ?? self.access
        state.phase = .loaded
        return state
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

    @Test
    func droppingARowOnAFolderMovesItThere() async {
        let report = entry("report.pdf")
        let archive = entry("Archive", isFolder: true)
        let moved = LockIsolated<(ids: [String], destination: String)?>(nil)
        let store = TestStore(initialState: state(items: [report, archive])) {
            BrowseFeature()
        } withDependencies: {
            $0.date = .constant(fixedDate)
            $0.filesClient.browse = { _, _ in BrowseResult(items: [], access: FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true), path: "Docs/Archive") }
            $0.filesClient.transferItems = { _, items, destination, _ in
                moved.setValue((items.map(\.id), destination))
                return TransferResult(destination: destination, items: items.map { .init(from: $0.id, to: "\(destination)/\($0.name)") })
            }
        }
        store.exhaustivity = .off

        await store.send(.itemsDroppedOnFolder(ids: [report.id], folder: archive))
        await store.skipReceivedActions()

        #expect(moved.value?.ids == [report.id])
        #expect(moved.value?.destination == archive.id)
        #expect(store.state.items.map(\.name) == ["Archive"])
    }

    @Test
    func droppingSeveralSelectedRowsMovesThemAll() async {
        let a = entry("a.pdf")
        let b = entry("b.pdf")
        let archive = entry("Archive", isFolder: true)
        let moved = LockIsolated<[String]>([])
        let store = TestStore(initialState: state(items: [a, b, archive])) {
            BrowseFeature()
        } withDependencies: {
            $0.date = .constant(fixedDate)
            $0.filesClient.browse = { _, _ in BrowseResult(items: [], access: FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true), path: "Docs/Archive") }
            $0.filesClient.transferItems = { _, items, destination, _ in
                moved.setValue(items.map(\.id))
                return TransferResult(destination: destination, items: items.map { .init(from: $0.id, to: "\(destination)/\($0.name)") })
            }
        }
        store.exhaustivity = .off

        await store.send(.itemsDroppedOnFolder(ids: [a.id, b.id], folder: archive))
        await store.skipReceivedActions()

        #expect(Set(moved.value) == [a.id, b.id])
    }

    @Test
    func droppingAFolderOnItselfMovesNothing() async {
        let archive = entry("Archive", isFolder: true)
        let store = TestStore(initialState: state(items: [archive])) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.transferItems = { _, _, _, _ in
                Issue.record("a folder must not be moved into itself")
                return TransferResult(destination: "", items: [])
            }
        }

        await store.send(.itemsDroppedOnFolder(ids: [archive.id], folder: archive))
    }

    @Test
    func droppingAFolderOnItsOwnDescendantMovesNothing() async {
        let archive = entry("Archive", isFolder: true)
        let nested = entry("2024", in: "Docs/Archive", isFolder: true)
        let store = TestStore(initialState: state(items: [archive])) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.transferItems = { _, _, _, _ in
                Issue.record("a folder must not be moved into its own subfolder")
                return TransferResult(destination: "", items: [])
            }
        }

        await store.send(.itemsDroppedOnFolder(ids: [archive.id], folder: nested))
    }

    @Test
    func droppingRowsFromTheSameFolderOnTheBackgroundMovesNothing() async {
        let report = entry("report.pdf")
        let store = TestStore(initialState: state(items: [report])) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.transferItems = { _, _, _, _ in
                Issue.record("moving into the folder a row is already in is a no op")
                return TransferResult(destination: "", items: [])
            }
        }

        await store.send(.itemsDroppedFromOtherWindow([report], destination: "Docs"))
    }

    @Test
    func droppingRowsWithoutWriteAccessMovesNothing() async {
        let report = entry("report.pdf")
        let archive = entry("Archive", isFolder: true)
        let readOnly = FileAccess(canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true)
        let store = TestStore(initialState: state(items: [report, archive], access: readOnly)) {
            BrowseFeature()
        }

        await store.send(.itemsDroppedOnFolder(ids: [report.id], folder: archive))
        await store.send(.itemsDroppedFromOtherWindow([entry("z.pdf", in: "Other")], destination: "Docs"))
    }

    @Test
    func aNameClashOnTheDropRaisesTheTransferConflictPrompt() async {
        let report = entry("report.pdf")
        let archive = entry("Archive", isFolder: true)
        let clash = entry("report.pdf", in: "Docs/Archive")
        let store = TestStore(initialState: state(items: [report, archive])) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in BrowseResult(items: [clash], access: FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true), path: "Docs/Archive") }
        }
        store.exhaustivity = .off

        await store.send(.itemsDroppedOnFolder(ids: [report.id], folder: archive))
        await store.skipReceivedActions()

        #expect(store.state.transferConflict?.collidingItems == [clash])
    }

    @Test
    func aRejectedMoveSurfacesTheServerMessage() async {
        let report = entry("report.pdf")
        let archive = entry("Archive", isFolder: true)
        let store = TestStore(initialState: state(items: [report, archive])) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in BrowseResult(items: [], access: FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true), path: "Docs/Archive") }
            $0.filesClient.transferItems = { _, _, _, _ in throw FilesClientError.forbidden(message: "Read only folder") }
        }
        store.exhaustivity = .off

        await store.send(.itemsDroppedOnFolder(ids: [report.id], folder: archive))
        await store.skipReceivedActions()

        #expect(store.state.transferErrorMessage != nil)
        #expect(store.state.isPerformingFileAction == false)
    }

    @Test
    func droppedFilesUploadIntoTheTargetFolder() async {
        let archive = entry("Archive", isFolder: true)
        let url = URL(fileURLWithPath: "/tmp/a.jpg")
        let store = TestStore(initialState: state(items: [archive])) {
            BrowseFeature()
        } withDependencies: {
            $0.uploadStaging = staging([stagedFile("a.jpg")])
        }

        await store.send(.filesDroppedOnFolder([url], folder: archive))
        await store.receive(\.directUploadStaged)
        await store.receive(.delegate(.uploadRequested([
            PendingUpload(id: UUID(0), fileURL: URL(fileURLWithPath: "/tmp/a.jpg"), fileName: "a.jpg", destination: "Docs/Archive"),
        ])))
    }

    @Test
    func droppedFilesWithoutUploadRightsAreIgnoredAndTheirStagedCopiesDeleted() async throws {
        let archive = entry("Archive", isFolder: true)
        let readOnly = FileAccess(canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true)
        let staged = try StagedDropFixture.make()
        defer { StagedDropFixture.remove(staged) }
        let store = TestStore(initialState: state(items: [archive], access: readOnly)) {
            BrowseFeature()
        }

        await store.send(.filesDroppedOnFolder([staged], folder: archive))
        await store.finish()

        #expect(!FileManager.default.fileExists(atPath: staged.path))
    }

    @Test
    func droppedFilesOnAFileRowAreIgnored() async {
        let report = entry("report.pdf")
        let store = TestStore(initialState: state(items: [report])) {
            BrowseFeature()
        }

        await store.send(.filesDroppedOnFolder([URL(fileURLWithPath: "/tmp/a.jpg")], folder: report))
    }
}

struct BrowseDropIdentityTests {
    private let otherAccount = DragOrigin(serverURL: serverURL.absoluteString, scope: "scope-b")
    private let otherServer = DragOrigin(serverURL: "https://other.example.com", scope: "scope-a")

    @Test
    func aDragCarriesTheServerAndAccountItStartedIn() throws {
        let reference = ServerItemReference(dragging: entry("a.pdf"), origin: receiver)

        let decoded = try JSONDecoder().decode(ServerItemReference.self, from: JSONEncoder().encode(reference))

        #expect(decoded.origin == receiver)
    }

    @Test
    func aPayloadWrittenBeforeDragsCarriedAnIdentityStillDecodesWithoutOne() throws {
        let decoded = try JSONDecoder().decode(ServerItemReference.self, from: Data(#"{"id":"Docs/a.pdf"}"#.utf8))

        #expect(decoded.origin == nil)
    }

    @Test
    func rowsDraggedFromAnotherAccountOrServerAreRefused() {
        let same = entry("a.pdf")
        for origin in [otherAccount, otherServer] {
            let plan = BrowseDropPlan(
                drops: [.items([same], origin: origin)], listed: [same.id], destination: "Docs/Archive", receiver: receiver
            )

            #expect(plan.isEmpty)
        }
    }

    @Test
    func rowsWithoutAnIdentityAreRefused() {
        let foreign = entry("z.pdf", in: "Other")
        let plan = BrowseDropPlan(
            drops: [.items([foreign], origin: nil)], listed: [], destination: "Docs", receiver: receiver
        )

        #expect(plan.isEmpty)
    }

    @Test
    func aMixedDropKeepsOnlyTheRowsOfTheReceivingAccount() {
        let mine = entry("mine.pdf")
        let theirs = entry("theirs.pdf", in: "Other")
        let plan = BrowseDropPlan(
            drops: [.items([theirs], origin: otherAccount), .items([mine], origin: receiver)],
            listed: [],
            destination: "Elsewhere",
            receiver: receiver
        )

        #expect(plan.foreignItems == [mine])
    }

    @Test
    func theDragPayloadIsNotBuiltUntilTheDragStarts() {
        let calls = LockIsolated(0)
        let builder = DraggedServerItemBuilder(
            item: entry("a.pdf"), serverURL: serverURL, scope: receiver.scope, filesClient: .previewValue,
            selection: {
                calls.withValue { $0 += 1 }
                return []
            }
        )
        #expect(calls.value == 0)

        let payload = builder.build()

        #expect(calls.value == 1)
        #expect(payload.reference.origin == receiver)
    }

    @Test
    func aStagedDropCopyIsDeletedOnceUploadStagingTookItsOwn() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("drop-\(TestID.name()).txt")
        try Data("x".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let copy = try DroppedFileStaging.copy(source)

        DroppedFileStaging.discardCopy(at: copy)

        #expect(!FileManager.default.fileExists(atPath: copy.deletingLastPathComponent().path))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test
    func discardingAFileOutsideTheDropDirectoryLeavesItAlone() throws {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(TestID.name()).txt")
        try Data("x".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }

        DroppedFileStaging.discardCopy(at: outside)

        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test
    func theStaleSweepRemovesOldDropCopiesAndKeepsFreshOnes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sweep-\(TestID.name())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("old", isDirectory: true)
        let fresh = root.appendingPathComponent("fresh", isDirectory: true)
        for url in [old, fresh] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let staleness: TimeInterval = 3_600
        try FileManager.default.setAttributes([.modificationDate: fixedDate.addingTimeInterval(-staleness)], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: fixedDate.addingTimeInterval(staleness)], ofItemAtPath: fresh.path)

        UploadStagingLocation.sweepStale(in: [root], olderThan: fixedDate)

        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
    }
}

private enum StagedDropFixture {
    /// A real staged drop copy, created the way a drop stages one.
    static func make(name: String = "dropped.txt") throws -> URL {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("drop-src-\(TestID.name())-\(name)")
        try Data("x".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let staged = try DroppedFileStaging.stage(source, isOriginal: true)
        let renamed = staged.deletingLastPathComponent().appendingPathComponent(name)
        try FileManager.default.moveItem(at: staged, to: renamed)
        return renamed
    }

    static func remove(_ url: URL) {
        DroppedFileStaging.discardCopy(at: url)
    }
}

struct BrowseDropStagingTests {
    @Test
    func aTemporarySystemCopyIsMovedNotCopied() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("system-\(TestID.name()).txt")
        try Data("x".utf8).write(to: source)

        let staged = try DroppedFileStaging.stage(source, isOriginal: false)
        defer { DroppedFileStaging.discardCopy(at: staged) }

        #expect(FileManager.default.fileExists(atPath: staged.path))
        #expect(!FileManager.default.fileExists(atPath: source.path))
    }

    @Test
    func anOriginalFileIsCopiedAndLeftWhereItWas() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("original-\(TestID.name()).txt")
        try Data("x".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let staged = try DroppedFileStaging.stage(source, isOriginal: true)
        defer { DroppedFileStaging.discardCopy(at: staged) }

        #expect(FileManager.default.fileExists(atPath: staged.path))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test
    func aFailedStageLeavesNoEmptyFolderBehind() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("stage-root-\(TestID.name())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let isolated = IsolatedTemporaryFileManager(root: root)
        let missing = root.appendingPathComponent("missing.txt")

        #expect(throws: (any Error).self) { try DroppedFileStaging.stage(missing, isOriginal: false, fileManager: isolated) }

        let staging = DroppedFileStaging.directory(in: root)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? []
        #expect(leftovers.isEmpty)
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

struct BrowseDropHandlerTests {
    private let folder = entry("Archive", isFolder: true)

    private func resolve(
        folder: FileItem?, files: [URL], canMove: Bool = true, canUpload: Bool
    ) -> BrowseDropHandler.Resolution {
        BrowseDropHandler.resolve(
            drops: files.map(BrowseDrop.file),
            folder: folder,
            listed: [],
            directoryPath: "Docs",
            receiver: receiver,
            canMove: canMove,
            canUpload: canUpload
        )
    }

    @Test
    func aRefusedDropLeavesNoStagedCopy() throws {
        let staged = try StagedDropFixture.make()
        defer { StagedDropFixture.remove(staged) }

        let resolution = resolve(folder: folder, files: [staged], canUpload: false)
        #expect(resolution.actions.isEmpty)
        BrowseDropHandler.discard(resolution.discardedFiles)

        #expect(!FileManager.default.fileExists(atPath: staged.path))
    }

    @Test
    func aDropOnAFileRowLeavesNoStagedCopy() throws {
        let staged = try StagedDropFixture.make()
        defer { StagedDropFixture.remove(staged) }

        let resolution = resolve(folder: entry("report.pdf"), files: [staged], canUpload: true)
        BrowseDropHandler.discard(resolution.discardedFiles)

        #expect(resolution.actions.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: staged.path))
    }

    @Test
    func anAcceptedDropKeepsTheStagedCopyForTheUpload() throws {
        let staged = try StagedDropFixture.make()
        defer { StagedDropFixture.remove(staged) }

        let resolution = resolve(folder: folder, files: [staged], canUpload: true)
        BrowseDropHandler.discard(resolution.discardedFiles)

        #expect(resolution.actions == [.filesDroppedOnFolder([staged], folder: folder)])
        #expect(resolution.discardedFiles.isEmpty)
        #expect(FileManager.default.fileExists(atPath: staged.path))
    }

    @Test
    func aBackgroundDropWithoutUploadRightsDiscardsTheCopy() throws {
        let staged = try StagedDropFixture.make()
        defer { StagedDropFixture.remove(staged) }

        let resolution = resolve(folder: nil, files: [staged], canUpload: false)

        #expect(resolution.actions.isEmpty)
        #expect(resolution.discardedFiles == [staged])
    }

    @Test
    func onlyTheFilesNoActionTookOverAreDiscarded() throws {
        let staged = try StagedDropFixture.make()
        defer { StagedDropFixture.remove(staged) }
        let foreign = entry("z.pdf", in: "Other")

        let resolution = BrowseDropHandler.resolve(
            drops: [.items([foreign], origin: receiver), .file(staged)],
            folder: folder, listed: [], directoryPath: "Docs", receiver: receiver, canMove: true, canUpload: false
        )

        #expect(resolution.actions == [.itemsDroppedFromOtherWindow([foreign], destination: folder.id)])
        #expect(resolution.discardedFiles == [staged])
    }
}

struct BrowseDropAcceptanceTests {
    private let folder = entry("Archive", isFolder: true)

    private func canAccept(
        destination: String? = nil, isFolder: Bool = true, dragged: [FileItem] = [], canMove: Bool = true, canUpload: Bool = true
    ) -> Bool {
        BrowseDropAcceptance.canAccept(
            destination: destination ?? folder.id, isFolder: isFolder, draggedRows: dragged, canMove: canMove, canUpload: canUpload
        )
    }

    @Test
    func anExternalDragIsAcceptedWithUploadRights() {
        #expect(canAccept(canMove: false, canUpload: true))
    }

    @Test
    func anExternalDragIsAcceptedWithMoveRightsAloneOnANonRootDestination() {
        #expect(canAccept(canMove: true, canUpload: false))
        #expect(!canAccept(destination: "", canMove: true, canUpload: false))
    }

    @Test
    func noRightsMeansNoOutline() {
        #expect(!canAccept(canMove: false, canUpload: false))
    }

    @Test
    func aFileRowIsNotATarget() {
        #expect(!canAccept(isFolder: false))
    }

    @Test
    func aFolderDraggedOverItselfIsRefused() {
        #expect(!canAccept(dragged: [folder]))
    }

    @Test
    func aFolderDraggedOverItsOwnDescendantIsRefused() {
        let inside = entry("2024", in: folder.id, isFolder: true)
        #expect(!canAccept(destination: inside.id, dragged: [folder]))
    }

    @Test
    func rowsAlreadyInsideTheDestinationAreRefused() {
        #expect(!canAccept(dragged: [entry("a.pdf", in: folder.id)]))
    }

    @Test
    func ownRowsNeedMoveRightsEvenWhenUploadsAreAllowed() {
        #expect(!canAccept(dragged: [entry("a.pdf")], canMove: false, canUpload: true))
        #expect(canAccept(dragged: [entry("a.pdf")], canMove: true, canUpload: false))
    }

    @Test
    func aSelectionWithOneMovableRowIsAccepted() {
        #expect(canAccept(dragged: [folder, entry("a.pdf")]))
    }
}

struct BrowseDropUntrustedPayloadTests {
    private func plan(_ item: FileItem) -> BrowseDropPlan {
        BrowseDropPlan(drops: [.items([item], origin: receiver)], listed: [], destination: "Docs/Archive", receiver: receiver)
    }

    @Test
    func aWellFormedForeignRowIsMoved() {
        #expect(plan(entry("a.pdf", in: "Other/Deep")).foreignItems.count == 1)
        #expect(plan(entry("a.pdf", in: "")).foreignItems.count == 1)
    }

    @Test(arguments: ["../secret", "Docs/../../etc", "/absolute", "a//b", "Docs/./x", "a\u{0}b", ".."])
    func aForeignRowWithAnUnsafePathIsRejected(path: String) {
        #expect(plan(entry("a.pdf", in: path)).isEmpty)
    }

    @Test(arguments: ["", ".", "..", "a/b", "a\u{0}b"])
    func aForeignRowWithAnUnsafeNameIsRejected(name: String) {
        #expect(plan(entry(name, in: "Other")).isEmpty)
    }

    @Test
    func anUnsafeRowIsRejectedButItsSafeNeighbourStillMoves() {
        let drop = BrowseDropPlan(
            drops: [.items([entry("a.pdf", in: "../x"), entry("b.pdf", in: "Other")], origin: receiver)],
            listed: [], destination: "Docs/Archive", receiver: receiver
        )
        #expect(drop.foreignItems.map(\.name) == ["b.pdf"])
    }
}
