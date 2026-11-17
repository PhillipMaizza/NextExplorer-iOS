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
        return (DeferredUploads(root: root.appendingPathComponent("Deferred", isDirectory: true)), root, source)
    }

    @Test("A claim moves the file out with its name and destination, and a second claim finds nothing")
    func claimMovesOnce() throws {
        let (store, root, source) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try store.stage(
            copying: source, fileName: Value.bigName, accountID: Harness.credentials.accountID,
            destination: TestPath.photos2026
        )
        let target = root.appendingPathComponent("scratch", isDirectory: true)

        let first = store.claim(accountID: Harness.credentials.accountID, into: target)
        let second = store.claim(accountID: Harness.credentials.accountID, into: target)

        #expect(first.map(\.fileName) == [Value.bigName])
        #expect(first.map(\.destination) == [TestPath.photos2026])
        #expect(first.first.flatMap { try? String(contentsOf: $0.fileURL, encoding: .utf8) } == Value.bytes)
        #expect(second.isEmpty)
        #expect(store.isEmpty)
    }

    @Test("A claim leaves another account's files where they are")
    func claimIsPerAccount() throws {
        let (store, root, source) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try store.stage(copying: source, fileName: Value.bigName, accountID: Value.otherAccount, destination: "")

        let claimed = store.claim(
            accountID: Harness.credentials.accountID,
            into: root.appendingPathComponent("scratch")
        )

        #expect(claimed.isEmpty)
        #expect(!store.isEmpty)
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

        let left = store.claim(accountID: Value.otherAccount, into: root.appendingPathComponent("a"))
        let kept = store.claim(accountID: Harness.credentials.accountID, into: root.appendingPathComponent("b"))
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

        #expect(store.claim(accountID: Harness.credentials.accountID, into: root).isEmpty)
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
}
