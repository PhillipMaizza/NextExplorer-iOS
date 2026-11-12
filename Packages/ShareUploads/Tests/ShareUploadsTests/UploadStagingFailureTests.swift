import CoreModels
import Foundation
@testable import ShareUploads
import Testing
import TestUtils
import UniformTypeIdentifiers

@Suite("Staging failures leave nothing behind")
struct UploadStagingFailureTests {
    private enum Constants {
        static let aBinary = "a.bin"
        static let firstBinary = "first.bin"
        static let secondBinary = "second.bin"
        static let sourceBytes = 100
        static let spareBytes: Int64 = 150
        static let concurrentReservations = 64
        static let reservedSlots = 5
        static let slotBytes: Int64 = 1000
        static let waitSeconds: TimeInterval = 10
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("StagingFailure-\(TestID.uuid().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeBatch(in root: URL, capacity: Int64? = nil) throws -> UploadBatch {
        let uploader = BackgroundUploader(
            root: root, notifier: UploadNotifier { _ in }, defaults: .standard, availableCapacity: { _ in capacity }
        )
        return try uploader.makeBatch(credentials: Harness.credentials, destination: TestFolder.photos)
    }

    private func source(in root: URL, name: String = "source.bin", bytes: Int = Constants.sourceBytes) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(count: bytes).write(to: url)
        return url
    }

    private func envelopes(of batch: UploadBatch) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: batch.directory.path)) ?? []
        return names.filter { $0.hasSuffix(".multipart") }
    }

    /// Writes half an envelope, then fails with `error`, like a disk that filled up mid write.
    private func failingWriter(_ error: any Error) -> EnvelopeWriter {
        { _, _, _, _, envelopeURL in
            try Data("partial".utf8).write(to: envelopeURL)
            throw error
        }
    }

    // MARK: Partial envelopes

    @Test("Any error while writing removes the partial envelope and is passed on unchanged")
    func anyErrorRemovesThePartialEnvelope() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var batch = try makeBatch(in: root)
        batch.writeEnvelope = failingWriter(CocoaError(.fileReadCorruptFile))

        #expect(throws: CocoaError.self) {
            try batch.envelope(for: source(in: root), fileName: Constants.aBinary)
        }
        #expect(envelopes(of: batch).isEmpty)
    }

    @Test("Every way a full disk is reported becomes insufficient space, and no partial envelope stays")
    func fullDiskInAllItsForms() throws {
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        let quota = NSError(domain: NSPOSIXErrorDomain, code: Int(EDQUOT))
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue, userInfo: [NSUnderlyingErrorKey: posix])
        let errors: [any Error] = [CocoaError(.fileWriteOutOfSpace), posix, quota, wrapped, ShareUploadError.insufficientSpace]
        for error in errors {
            let root = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            var batch = try makeBatch(in: root)
            batch.writeEnvelope = failingWriter(error)

            #expect(throws: ShareUploadError.insufficientSpace, "\(error)") {
                try batch.envelope(for: source(in: root), fileName: Constants.aBinary)
            }
            #expect(envelopes(of: batch).isEmpty, "\(error)")
        }
    }

    @Test("Other POSIX errors are not mistaken for a full disk")
    func otherPosixErrorsAreNot() {
        #expect(!ShareUploadError.isOutOfSpace(NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))))
        #expect(!ShareUploadError.isOutOfSpace(CocoaError(.fileReadNoSuchFile)))
        #expect(ShareUploadError.isOutOfSpace(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))))
    }

    @Test("A Live Photo whose movie cannot be staged takes the already staged still back out")
    func livePhotoMovieFailureDeletesTheStill() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let still = try source(in: root, name: ShareUploadsTestValue.heicName)
        let movie = try source(in: root, name: "0F3A.mov")
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.heic.identifier, fileOptions: [], visibility: .all) { completion in
            completion(still, false, nil)
            return nil
        }
        provider.registerDataRepresentation(forTypeIdentifier: UTType.livePhoto.identifier, visibility: .all) { completion in
            completion(Data(), nil)
            return nil
        }
        provider.registerFileRepresentation(forTypeIdentifier: UTType.quickTimeMovie.identifier, fileOptions: [], visibility: .all) { completion in
            completion(movie, false, nil)
            return nil
        }
        var batch = try makeBatch(in: root)
        let write = batch.writeEnvelope
        let failure = failingWriter(CocoaError(.fileWriteOutOfSpace))
        batch.writeEnvelope = { serverURL, fileURL, name, destination, envelopeURL in
            if name.hasSuffix(".mov") {
                return try failure(serverURL, fileURL, name, destination, envelopeURL)
            }
            return try write(serverURL, fileURL, name, destination, envelopeURL)
        }

        await #expect(throws: ShareUploadError.insufficientSpace) {
            try await SharedItemLoader.stageAll(provider, in: batch)
        }
        #expect(envelopes(of: batch).isEmpty, "a still without its movie is not the photo")
    }

    // MARK: Parallel staging and the free space figure

    @Test("A second file staged while the first is still being written sees the first one's bytes as taken")
    func parallelStagingDoesNotOvercommit() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var batch = try makeBatch(in: root, capacity: DiskSpace.reservedBytes + Constants.spareBytes)
        let writing = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let write = batch.writeEnvelope
        batch.writeEnvelope = { serverURL, fileURL, name, destination, envelopeURL in
            writing.signal()
            release.wait()
            return try write(serverURL, fileURL, name, destination, envelopeURL)
        }
        let first = try source(in: root, name: Constants.firstBinary)
        let second = try source(in: root, name: Constants.secondBinary)
        let finished = DispatchSemaphore(value: 0)
        let staged = LockedValue<UploadBatch.StagedFile?>(nil)
        let started = batch
        DispatchQueue.global().async {
            staged.set(try? started.envelope(for: first, fileName: Constants.firstBinary))
            finished.signal()
        }
        #expect(writing.wait(timeout: .now() + Constants.waitSeconds) == .success)

        #expect(throws: ShareUploadError.insufficientSpace) {
            try batch.envelope(for: second, fileName: Constants.secondBinary)
        }
        release.signal()
        #expect(finished.wait(timeout: .now() + Constants.waitSeconds) == .success)
        #expect(staged.value != nil, "the first file went through")
        #expect(batch.ledger.inFlight == 0, "everything is given back once written")
        #expect(envelopes(of: batch).count == 1)
    }

    @Test("Reservations made at the same moment never add up to more than the free space allows")
    func ledgerIsExactUnderContention() {
        let ledger = SpaceLedger()
        let available = DiskSpace.reservedBytes + Constants.slotBytes * Int64(Constants.reservedSlots)
        let granted = LockedValue(0)

        DispatchQueue.concurrentPerform(iterations: Constants.concurrentReservations) { _ in
            if ledger.reserve(Constants.slotBytes, available: available) {
                granted.update { $0 += 1 }
            }
        }

        #expect(granted.value == Constants.reservedSlots)
        #expect(ledger.inFlight == Constants.slotBytes * Int64(Constants.reservedSlots))
    }

    @Test("Releasing a reservation makes its room usable again, and never goes below zero")
    func ledgerReleases() {
        let ledger = SpaceLedger()
        let available = DiskSpace.reservedBytes + Constants.slotBytes
        #expect(ledger.reserve(Constants.slotBytes, available: available))
        #expect(!ledger.reserve(1, available: available))
        ledger.release(Constants.slotBytes)
        #expect(ledger.reserve(Constants.slotBytes, available: available))
        ledger.release(Constants.slotBytes * 2)
        #expect(ledger.inFlight == 0)
        #expect(ledger.reserve(Constants.slotBytes, available: nil), "an unknown capacity never blocks")
    }

    @Test("The free space figure is the conservative one, not counting what the system might purge")
    func capacityIsConservative() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let conservative = try #require(DiskSpace.availableCapacity(at: root))
        let values = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let important = try #require(values.volumeAvailableCapacityForImportantUsage)

        #expect(conservative <= important)
        #expect(conservative > 0)
    }

    // MARK: Cancelled and discarded batches

    private final class TaskBox: @unchecked Sendable {
        private let lock = NSLock()
        private var task: Task<UploadBatch.StagedFile, any Error>?
        let isSet = DispatchSemaphore(value: 0)

        func set(_ task: Task<UploadBatch.StagedFile, any Error>) {
            lock.withLock { self.task = task }
            isSet.signal()
        }

        func cancel() {
            isSet.wait()
            lock.withLock { task }?.cancel()
            isSet.signal()
        }
    }

    @Test("A batch discarded while its file is being read is never recreated and gets no envelope")
    func discardedBatchStaysGone() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try source(in: root)
        let batch = try makeBatch(in: root)
        let access = FileAccess(ubiquityStatus: { _ in .notDownloaded }, startDownload: { _ in
            try? FileManager.default.removeItem(at: batch.directory)
        })

        await #expect(throws: CancellationError.self) {
            try await SharedItemLoader.stageFile(at: file, in: batch, access: access)
        }
        #expect(!batch.exists, "the discarded batch folder is not made again")
    }

    @Test("A task cancelled during the coordinated read writes no envelope")
    func cancelledDuringTheRead() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try source(in: root)
        let batch = try makeBatch(in: root)
        let box = TaskBox()
        let access = FileAccess(ubiquityStatus: { _ in .notDownloaded }, startDownload: { _ in box.cancel() })
        let task = Task { try await SharedItemLoader.stageFile(at: file, in: batch, access: access) }
        box.set(task)

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(envelopes(of: batch).isEmpty)
    }

    @Test("A task cancelled while the envelope is being written has it taken back out")
    func cancelledDuringTheWrite() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try source(in: root)
        var batch = try makeBatch(in: root)
        let box = TaskBox()
        let write = batch.writeEnvelope
        batch.writeEnvelope = { serverURL, fileURL, name, destination, envelopeURL in
            let request = try write(serverURL, fileURL, name, destination, envelopeURL)
            box.cancel()
            return request
        }
        let access = FileAccess(ubiquityStatus: { _ in nil }, startDownload: { _ in })
        let started = batch
        let task = Task { try await SharedItemLoader.stageFile(at: file, in: started, access: access) }
        box.set(task)

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(envelopes(of: batch).isEmpty)
    }

    @Test("A file staged normally is still staged: the checks only stop what was cancelled or discarded")
    func normalStagingStillWorks() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try source(in: root)
        let batch = try makeBatch(in: root)

        let staged = try await SharedItemLoader.stageFile(
            at: file, in: batch, access: FileAccess(ubiquityStatus: { _ in nil }, startDownload: { _ in })
        )

        #expect(staged != nil)
        #expect(envelopes(of: batch).count == 1)
    }
}

final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    var value: Value {
        lock.withLock { stored }
    }

    func set(_ value: Value) {
        lock.withLock { stored = value }
    }

    func update(_ change: (inout Value) -> Void) {
        lock.withLock { change(&stored) }
    }
}
