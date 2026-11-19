import CoreModels
import Foundation
@testable import ShareUploads
import Testing
import TestUtils

@Suite("Deferred uploads")
struct DeferredUploadsTests {
    private enum Value {
        static let bigName = "Holiday.mov"
        static let bytes = "0123456789"
        static let otherAccount = "someone|else"
    }

    private func makeStore() throws -> (store: DeferredUploads, root: URL, source: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeferredUploadsTests-\(TestID.uuid().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.mov")
        try Data(Value.bytes.utf8).write(to: source)
        try FileManager.default.setAttributes([.modificationDate: MockDate.date], ofItemAtPath: source.path)
        return (DeferredUploads(root: root.appendingPathComponent("Deferred", isDirectory: true)), root, source)
    }

    @Test("Pending lists the file in place with its name and destination, and drops folders whose file is gone")
    func pendingListsFilesInPlace() throws {
        let (store, root, source) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try store.stage(
            copying: source, fileName: Value.bigName, accountID: Harness.credentials.accountID,
            destination: TestPath.photos2026
        )

        let first = store.pending(accountID: Harness.credentials.accountID)
        let again = store.pending(accountID: Harness.credentials.accountID)

        #expect(first == again, "listing never moves anything, so a force quit loses nothing")
        #expect(first.map(\.fileName) == [Value.bigName])
        #expect(first.map(\.destination) == [TestPath.photos2026])
        #expect(first.first.flatMap { try? String(contentsOf: $0.fileURL, encoding: .utf8) } == Value.bytes)

        try FileManager.default.removeItem(at: folder.appendingPathComponent("payload"))
        #expect(store.pending(accountID: Harness.credentials.accountID).isEmpty)
        #expect(store.isEmpty, "the upload deleted its file, so its folder goes")
    }

    @Test("A kept file that never uploaded is dropped after a week, so a failing one cannot fill the disk")
    func pendingDropsWeekOldFiles() throws {
        let (store, root, source) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try store.stage(
            copying: source, fileName: Value.bigName, accountID: Harness.credentials.accountID, destination: ""
        )
        try FileManager.default.setAttributes(
            [.modificationDate: TestClock.reference], ofItemAtPath: folder.appendingPathComponent("meta.json").path
        )
        let day: TimeInterval = 24 * 60 * 60

        #expect(store.pending(accountID: Harness.credentials.accountID, now: TestClock.reference + 6 * day).count == 1)
        #expect(store.pending(accountID: Harness.credentials.accountID, now: TestClock.reference + 8 * day).isEmpty)
        #expect(store.isEmpty)
    }

    @Test("Another account's files are not listed")
    func pendingIsPerAccount() throws {
        let (store, root, source) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try store.stage(copying: source, fileName: Value.bigName, accountID: Value.otherAccount, destination: "")

        #expect(store.pending(accountID: Harness.credentials.accountID).isEmpty)
        #expect(!store.isEmpty)
    }

    @Test("A name that tries to leave the destination folder is cut to its last component")
    func pendingCutsTraversalNames() throws {
        let (store, root, source) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try store.stage(
            copying: source, fileName: "../../evil.mov", accountID: Harness.credentials.accountID, destination: ""
        )

        #expect(store.pending(accountID: Harness.credentials.accountID).map(\.fileName) == ["evil.mov"])
    }

    @Test("Signing out deletes the files of accounts that left and keeps the others")
    func discardKeepsStayingAccounts() throws {
        let (store, root, source) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try store.stage(copying: source, fileName: Value.bigName, accountID: Value.otherAccount, destination: "")
        _ = try store.stage(
            copying: source, fileName: Value.bigName, accountID: Harness.credentials.accountID, destination: ""
        )

        store.discard(keepingAccounts: [Harness.credentials.accountID])

        let left = store.pending(accountID: Value.otherAccount)
        let kept = store.pending(accountID: Harness.credentials.accountID)
        #expect(left.isEmpty)
        #expect(kept.count == 1)
    }

    @Test("A half written folder is never claimed, and goes once it is old")
    func partialFoldersAreIgnored() throws {
        let (store, root, _) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let partial = store.root.appendingPathComponent(".half", isDirectory: true)
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: TestClock.reference], ofItemAtPath: partial.path)

        #expect(store.pending(accountID: Harness.credentials.accountID).isEmpty)
        store.discard(keepingAccounts: [], now: TestClock.reference)
        #expect(FileManager.default.fileExists(atPath: partial.path), "a young one may still be filling")
        store.discard(keepingAccounts: [], now: TestClock.reference.addingTimeInterval(2 * 60 * 60))
        #expect(!FileManager.default.fileExists(atPath: partial.path))
    }

    @Test("A file over the limit is kept whole for the app and an under limit one still gets an envelope")
    func batchDefersOnlyBigFiles() throws {
        let (store, root, source) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let harness = try Harness(deferredUploads: store)
        defer { harness.tearDown() }
        var batch = try harness.uploader.makeBatch(credentials: Harness.credentials, destination: TestPath.photos2026)
        batch.deferralBytes = Int64(Value.bytes.utf8.count) - 1

        try batch.add(batch.envelope(for: source, fileName: Value.bigName))
        batch.deferralBytes = Int64(Value.bytes.utf8.count)
        try batch.add(batch.envelope(for: source, fileName: ShareUploadsTestValue.reportName))

        #expect(batch.count == 2)
        #expect(batch.staged.map(\.fileName) == [ShareUploadsTestValue.reportName])
        #expect(!store.isEmpty)
    }

    @Test("A batch of only big files sends nothing, tells the user and leaves no batch folder")
    func startWithOnlyDeferredFiles() throws {
        let (store, root, source) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let harness = try Harness(deferredUploads: store)
        defer { harness.tearDown() }
        var batch = try harness.uploader.makeBatch(credentials: Harness.credentials, destination: TestPath.photos2026)
        batch.deferralBytes = 1
        try batch.add(batch.envelope(for: source, fileName: Value.bigName))

        try harness.uploader.start(batch)

        #expect(harness.starter.started.isEmpty)
        #expect(!harness.exists(batch.directory))
        #expect(harness.center.requests.map(\.identifier) == [UploadNotificationIdentifier.deferredNotification])
    }

    @Test("Cancelling the share takes the files kept for the app out too")
    func discardingABatchDeletesItsKeptFiles() throws {
        let (store, root, source) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let harness = try Harness(deferredUploads: store)
        defer { harness.tearDown() }
        var batch = try harness.uploader.makeBatch(credentials: Harness.credentials, destination: TestPath.photos2026)
        batch.deferralBytes = 1
        try batch.add(batch.envelope(for: source, fileName: Value.bigName))
        #expect(!store.isEmpty)

        harness.uploader.discard(batch)

        #expect(store.isEmpty, "a cancelled share must not upload from the app later")
    }

    @Test("Signing out also deletes the files kept for the app")
    func cancelDiscardsDeferredFiles() throws {
        let (store, root, source) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let harness = try Harness(deferredUploads: store)
        defer { harness.tearDown() }
        _ = try store.stage(
            copying: source, fileName: Value.bigName, accountID: Harness.credentials.accountID, destination: ""
        )

        harness.uploader.cancel(keepingAccounts: [])

        #expect(store.isEmpty)
    }

    @Test("A refused size lowers the limit for that server only, never below the proxy floor")
    func learnedLimit() throws {
        let suite = "DeferredLimit-\(TestID.uuid().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let server = Harness.credentials.serverBaseURL
        let other = try #require(URL(string: TestHost.otherServerURLString))
        let mebibyte = Int64(UploadSettings.bytesPerMiB)

        #expect(DeferredUploads.directLimitBytes(for: server, defaults: defaults) == DeferredUploads.thresholdBytes)

        DeferredUploads.learnRefusal(ofBytes: 60 * mebibyte, serverURL: server, defaults: defaults)
        #expect(DeferredUploads.directLimitBytes(for: server, defaults: defaults) == 30 * mebibyte)
        #expect(DeferredUploads.directLimitBytes(for: other, defaults: defaults) == DeferredUploads.thresholdBytes)

        DeferredUploads.learnRefusal(ofBytes: 80 * mebibyte, serverURL: server, defaults: defaults)
        #expect(DeferredUploads.directLimitBytes(for: server, defaults: defaults) == 30 * mebibyte, "never raised")

        DeferredUploads.learnRefusal(ofBytes: 16 * mebibyte, serverURL: server, defaults: defaults)
        #expect(DeferredUploads.directLimitBytes(for: server, defaults: defaults) == Int64(UploadMode.largeFileBytes))

        let small = try #require(URL(string: "https://small.example.com"))
        DeferredUploads.learnRefusal(ofBytes: mebibyte, serverURL: small, defaults: defaults)
        #expect(
            DeferredUploads.directLimitBytes(for: small, defaults: defaults) == DeferredUploads.thresholdBytes,
            "a small file refused is not a size limit"
        )
    }

    @Test("A file a proxy refused as too large lowers the limit, so sharing it again keeps it for the app")
    func refusalIsLearnedFromTheBatch() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try harness.makeBatch(names: [TestFile.aPhoto])
        let envelope = batch.directory.appendingPathComponent(batch.manifest.envelopes[0])
        let size = 40 * UploadSettings.bytesPerMiB
        let handle = try FileHandle(forWritingTo: envelope)
        try handle.truncate(atOffset: UInt64(size))
        try handle.close()

        harness.uploader.complete(batchID: batch.id, index: 0, result: .failure(.tooLarge))

        let limit = DeferredUploads.directLimitBytes(for: batch.manifest.serverURL, defaults: harness.defaults)
        #expect(limit == Int64(size / 2))
    }
}
