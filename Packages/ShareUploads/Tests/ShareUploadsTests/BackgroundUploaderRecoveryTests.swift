import CoreModels
import Foundation
@testable import ShareUploads
import Testing
import TestUtils

@Suite("Background uploader recovery")
struct BackgroundUploaderRecoveryTests {
    private func tombstone(in harness: Harness, modifiedSecondsAgo: TimeInterval) throws -> URL {
        let url = harness.root.appendingPathComponent(".removing-\(TestID.uuid().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("leftover".utf8).write(to: url.appendingPathComponent(ShareUploadsTestValue.firstEnvelope))
        try FileManager.default.setAttributes(
            [.modificationDate: TestClock.reference.addingTimeInterval(-modifiedSecondsAgo)], ofItemAtPath: url.path
        )
        return url
    }

    /// A batch nobody has heard from for longer than the stale age.
    private func oldBatch(
        in harness: Harness,
        names: [String] = [TestFile.aPhoto, TestFile.bPhoto]
    ) throws
        -> (id: String, directory: URL, manifest: Manifest)
    {
        let batch = try harness.makeBatch(
            names: names, startedAt: TestClock.reference.addingTimeInterval(-BackgroundUploader.staleAge - 60)
        )
        Manifest.touch(batch.directory, at: TestClock.reference.addingTimeInterval(-BackgroundUploader.staleAge - 60))
        return batch
    }

    // MARK: Notifications of removed batches

    @Test("Cancelling removes the delivered and pending notifications of exactly the batches it deleted")
    func cancelRemovesNotifications() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let leaving = try harness.makeBatch(names: [TestFile.aPhoto], accountID: ShareUploadsTestValue.leavingAccount)
        _ = try harness.makeBatch(names: [TestFile.aPhoto], accountID: ShareUploadsTestValue.stayingAccount)

        harness.uploader.cancel(keepingAccounts: [ShareUploadsTestValue.stayingAccount])

        #expect(harness.center.removedIdentifiers == [[leaving.id]])
    }

    @Test("Cancelling with nothing to delete touches no notification")
    func cancelWithNothingToDelete() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        _ = try harness.makeBatch(names: [TestFile.aPhoto], accountID: ShareUploadsTestValue.stayingAccount)

        harness.uploader.cancel(keepingAccounts: [ShareUploadsTestValue.stayingAccount])

        #expect(harness.center.removedIdentifiers.isEmpty)
    }

    @Test("Starting a retry takes the batch's failure notification away, a retry that sends nothing leaves it")
    func retryRemovesTheNotification() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try harness.makeBatch(names: [TestFile.aPhoto])
        harness.uploader.complete(batchID: batch.id, index: 0, result: .failure(.network))
        var other = Harness.credentials
        other.username = TestUser.someoneElse

        #expect(harness.uploader.retryFailed(batchID: batch.id, credentials: other) == 0)
        #expect(harness.center.removedIdentifiers.isEmpty)
        #expect(harness.uploader.retryFailed(batchID: batch.id, credentials: Harness.credentials) == 1)
        #expect(harness.center.removedIdentifiers == [[batch.id]])
    }

    @Test("The retention deleting a failed batch takes its notification with it")
    func retentionRemovesTheNotification() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try harness.makeBatch(names: [TestFile.aPhoto])
        harness.uploader.complete(batchID: batch.id, index: 0, result: .failure(.network))
        try FileManager.default.setAttributes(
            [.modificationDate: TestClock.reference],
            ofItemAtPath: batch.directory.appendingPathComponent("finished").path
        )
        harness.clock.advance(by: BackgroundUploader.failedRetention - 1)
        harness.uploader.reconnectPending()
        #expect(harness.center.removedIdentifiers.isEmpty)

        harness.clock.advance(by: 2)
        harness.uploader.reconnectPending()

        #expect(harness.center.removedIdentifiers == [[batch.id]])
    }

    // MARK: Tombstones

    @Test("Reconnecting sweeps removal leftovers older than the stale age and keeps a fresh one")
    func reconnectSweepsTombstones() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let old = try tombstone(in: harness, modifiedSecondsAgo: BackgroundUploader.staleAge + 60)
        let fresh = try tombstone(in: harness, modifiedSecondsAgo: 60)

        harness.uploader.reconnectPending()

        #expect(!harness.exists(old))
        #expect(harness.exists(fresh), "another process may still be emptying it")
        #expect(harness.recorder.outcomes.isEmpty, "a leftover is never mistaken for a batch")
    }

    @Test("Cancelling sweeps old removal leftovers too")
    func cancelSweepsTombstones() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let old = try tombstone(in: harness, modifiedSecondsAgo: BackgroundUploader.staleAge + 60)

        harness.uploader.cancel(keepingAccounts: [])

        #expect(!harness.exists(old))
    }

    // MARK: Recording before deleting

    private final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [UploadResult?] = []

        var results: [UploadResult?] {
            lock.withLock { recorded }
        }

        func add(_ result: UploadResult?) {
            lock.withLock { recorded.append(result) }
        }
    }

    @Test("A sent file's result is on disk before its envelope is deleted")
    func resultComesBeforeDeletion() throws {
        let seen = Seen()
        let harness = try Harness(removeEnvelope: { url in
            seen.add(Manifest.results(in: url.deletingLastPathComponent())[0])
            try? FileManager.default.removeItem(at: url)
        })
        defer { harness.tearDown() }
        let batch = try harness.makeBatch(names: [TestFile.aPhoto])

        harness.uploader.complete(batchID: batch.id, index: 0, result: .success)

        #expect(seen.results == [.success], "a crash between the two steps must not lose the result")
    }

    @Test("A deletion that never happens still leaves the success recorded and the batch reported")
    func failedDeletionKeepsTheResult() throws {
        let harness = try Harness(removeEnvelope: { _ in })
        defer { harness.tearDown() }
        let batch = try harness.makeBatch(names: [TestFile.aPhoto, TestFile.bPhoto])

        harness.uploader.complete(batchID: batch.id, index: 0, result: .success)

        #expect(Manifest.results(in: batch.directory)[0] == .success)
        harness.uploader.complete(batchID: batch.id, index: 1, result: .success)
        #expect(harness.recorder.outcomes.first?.uploaded == 2)
    }

    // MARK: Files never submitted

    private func specs(_ harness: Harness) -> [[Int]] {
        harness.starter.started.map { $0.specs.map(\.index) }
    }

    @Test("A file with no result, no live task and an envelope is sent again; the others are left alone")
    func reconnectResubmitsUnsentFiles() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try oldBatch(in: harness, names: ["done.jpg", "running.jpg", "gone.jpg", "unsent.jpg"])
        Manifest.record(index: 0, result: .success, in: batch.directory)
        harness.tasks.set(LiveTasks(count: 1, indexes: [1]), forBatch: batch.id)
        try FileManager.default.removeItem(at: batch.directory.appendingPathComponent("2.multipart"))

        harness.uploader.reconnectPending(sessions: [Harness.credentials])

        #expect(specs(harness) == [[3]])
        let started = try #require(harness.starter.started.first)
        #expect(started.identifier == BackgroundUploader.identifierPrefix + batch.id)
        #expect(started.specs.first?.request
            .value(forHTTPHeaderField: ShareUploadsTestValue.cookieHeader) == "connect.sid=secret")
        #expect(harness.recorder.outcomes.isEmpty, "nothing is abandoned while files can still go out")
        #expect(harness.events.scheduledDelays.isEmpty)
    }

    @Test("A batch whose tasks all vanished is sent again instead of abandoned when its account is signed in")
    func reconnectResubmitsInsteadOfAbandoning() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        _ = try oldBatch(in: harness)

        harness.uploader.reconnectPending(sessions: [Harness.credentials])

        #expect(specs(harness) == [[0, 1]])
        #expect(harness.events.scheduledDelays.isEmpty)
    }

    @Test("Without a session for the batch's account nothing is sent and the batch is abandoned after the grace")
    func reconnectWithoutASessionAbandons() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try oldBatch(in: harness)
        var other = Harness.credentials
        other.username = TestUser.someoneElse

        harness.uploader.reconnectPending(sessions: [other])

        #expect(harness.starter.started.isEmpty)
        #expect(harness.events.scheduledDelays == [BackgroundUploader.abandonGrace])
        #expect(harness.recorder.outcomes.isEmpty, "not before the grace has passed")

        harness.events.fireTimers()

        let outcome = try #require(harness.recorder.outcomes.first)
        #expect(outcome.failures.map(\.name) == [TestFile.aPhoto, TestFile.bPhoto])
        #expect(
            harness.exists(batch.directory.appendingPathComponent(ShareUploadsTestValue.firstEnvelope)),
            "kept for a retry"
        )
    }

    @Test("A batch with a live task is neither resent nor abandoned")
    func liveBatchIsLeftAlone() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try oldBatch(in: harness)
        harness.tasks.set(LiveTasks(count: 2, indexes: [0, 1]), forBatch: batch.id)

        harness.uploader.reconnectPending(sessions: [Harness.credentials])

        #expect(harness.starter.started.isEmpty)
        #expect(harness.events.scheduledDelays.isEmpty)
        #expect(harness.recorder.outcomes.isEmpty)
    }

    @Test("Unsent files are the ones with no result, no running task and an envelope")
    func unsubmittedDecision() {
        let manifest = Manifest(
            accountID: "a", destination: "D", fileNames: ["0", "1", "2", "3"],
            envelopes: ["e0", "e1", "e2", "e3"], contentTypes: ["", "", "", ""],
            serverURL: Harness.credentials.serverBaseURL, startedAt: TestClock.reference
        )

        let unsent = BackgroundUploader.unsubmittedIndexes(
            manifest: manifest, results: [0: .success], liveIndexes: [1], envelopeExists: { $0 != "e2" }
        )

        #expect(unsent == [3])
        #expect(BackgroundUploader.unsubmittedIndexes(
            manifest: manifest,
            results: [:],
            liveIndexes: [],
            envelopeExists: { _ in false }
        ).isEmpty)
    }

    // MARK: Pending batches

    @Test("Pending batches are the folders named like a batch, nothing else")
    func pendingBatches() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        #expect(!harness.uploader.hasPendingBatches())
        _ = try tombstone(in: harness, modifiedSecondsAgo: 0)
        #expect(!harness.uploader.hasPendingBatches(), "a removal leftover is not a batch")

        try harness.makeBatch()

        #expect(harness.uploader.hasPendingBatches())
    }

    // MARK: Refused sessions

    @Test("Once signed in again, only the files the server refused as signed out are sent, from reported batches")
    func retryRefusedSendsOnlyUnauthorized() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try harness.makeBatch(names: [TestFile.aPhoto, TestFile.bPhoto, TestFile.cPhoto])
        harness.uploader.complete(batchID: batch.id, index: 0, result: .failure(.unauthorized))
        harness.uploader.complete(batchID: batch.id, index: 1, result: .failure(.network))
        harness.uploader.complete(batchID: batch.id, index: 2, result: .success)
        var fresh = Harness.credentials
        fresh.cookieValue = TestSession.refreshedCookieValue

        let count = harness.uploader.retryRefused(credentials: fresh)

        #expect(count == 1)
        #expect(specs(harness) == [[0]])
        #expect(harness.starter.started.first?.specs.first?.request
            .value(forHTTPHeaderField: ShareUploadsTestValue.cookieHeader) == "connect.sid=fresh")
        #expect(harness.uploader.retryRefused(credentials: fresh) == 0, "a second look finds nothing refused left")
    }

    @Test("Refused files of a batch still running, or of another account, are not touched")
    func retryRefusedGuards() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let running = try harness.makeBatch(names: [TestFile.aPhoto, TestFile.bPhoto])
        Manifest.record(index: 0, result: .failure(.unauthorized), in: running.directory)
        let other = try harness.makeBatch(names: [TestFile.aPhoto], accountID: "someone|else")
        harness.uploader.complete(batchID: other.id, index: 0, result: .failure(.unauthorized))

        #expect(harness.uploader.retryRefused(credentials: Harness.credentials) == 0)
        #expect(harness.starter.started.isEmpty)
    }
}
