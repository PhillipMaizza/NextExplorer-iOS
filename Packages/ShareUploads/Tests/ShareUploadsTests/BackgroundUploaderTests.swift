import CoreModels
import Foundation
@testable import ShareUploads
import Testing
import TestUtils

@Suite("Background uploader lifecycle")
struct BackgroundUploaderTests {
    // MARK: Cancelling

    @Test("A cancelled batch reports nothing when its cancelled tasks call back")
    func cancelledBatchStaysQuiet() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try harness.makeBatch()

        harness.uploader.cancel(keepingAccounts: [])
        harness.uploader.complete(batchID: batch.id, index: 0, result: .failure(.other))
        harness.uploader.complete(batchID: batch.id, index: 1, result: .failure(.other))

        #expect(harness.recorder.outcomes.isEmpty, "no 'some files didn't upload' for an account that signed out")
        #expect(!harness.exists(batch.directory))
        #expect(harness.uploader.accountsNeedingSignIn().isEmpty)
    }

    @Test("Cancelling clears the sign in flags of accounts that left and keeps the others")
    func cancelClearsFlags() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let leaving = try harness.makeBatch(names: ["a.jpg"], accountID: "left")
        let staying = try harness.makeBatch(names: ["a.jpg"], accountID: "stays")
        harness.uploader.complete(batchID: leaving.id, index: 0, result: .failure(.unauthorized))
        harness.uploader.complete(batchID: staying.id, index: 0, result: .failure(.unauthorized))
        #expect(harness.uploader.accountsNeedingSignIn() == ["left", "stays"])

        harness.uploader.cancel(keepingAccounts: ["stays"])

        #expect(harness.uploader.accountsNeedingSignIn() == ["stays"])
    }

    // MARK: Finishing

    @Test("A batch is reported once, with its uploaded count, when every file has a result")
    func finishesWhenComplete() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try harness.makeBatch()

        harness.uploader.complete(batchID: batch.id, index: 0, result: .success)
        #expect(harness.recorder.outcomes.isEmpty)
        harness.uploader.complete(batchID: batch.id, index: 1, result: .success)

        let outcome = try #require(harness.recorder.outcomes.first)
        #expect(harness.recorder.outcomes.count == 1)
        #expect(outcome.uploaded == 2)
        #expect(outcome.failures.isEmpty)
        #expect(outcome.host == "files.example.com")
        #expect(outcome.destination == "Photos/2026")
        #expect(!harness.exists(batch.directory), "a fully uploaded batch leaves nothing behind")
    }

    @Test("A sent file's envelope is deleted, a failed one is kept for a retry")
    func failedEnvelopesAreKept() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try harness.makeBatch()

        harness.uploader.complete(batchID: batch.id, index: 0, result: .success)
        harness.uploader.complete(batchID: batch.id, index: 1, result: .failure(.network))

        #expect(!harness.exists(batch.directory.appendingPathComponent("0.multipart")))
        #expect(harness.exists(batch.directory.appendingPathComponent("1.multipart")))
        let outcome = try #require(harness.recorder.outcomes.first)
        #expect(outcome.uploaded == 1)
        #expect(outcome.failures == [FailedUpload(name: "b.jpg", cause: .network)])
    }

    @Test("Finishing is claimed once even when many processes finish at the same time")
    func claimIsExclusive() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try harness.makeBatch(names: ["a.jpg"])
        Manifest.record(index: 0, result: .failure(.other), in: batch.directory)

        DispatchQueue.concurrentPerform(iterations: 32) { _ in
            harness.uploader.finishBatch(id: batch.id, manifest: batch.manifest)
        }

        #expect(harness.recorder.outcomes.count == 1)
        #expect(!Manifest.claim(batch.directory))
    }

    @Test("A duplicate result after the batch was reported does not report it again")
    func duplicateEventIsIgnored() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try harness.makeBatch(names: ["a.jpg"])

        harness.uploader.complete(batchID: batch.id, index: 0, result: .failure(.network))
        harness.uploader.complete(batchID: batch.id, index: 0, result: .failure(.network))

        #expect(harness.recorder.outcomes.count == 1)
    }

    @Test("An out of range or unknown result is ignored")
    func unknownIndex() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try harness.makeBatch(names: ["a.jpg"])

        harness.uploader.complete(batchID: batch.id, index: 5, result: .success)
        harness.uploader.complete(batchID: TestID.uuid().uuidString, index: 0, result: .success)

        #expect(harness.recorder.outcomes.isEmpty)
        #expect(Manifest.results(in: batch.directory).isEmpty)
    }

    // MARK: Reconnecting

    @Test("Reconnecting reports a batch that ended while nobody listened, once, however often it runs")
    func reconnectIsIdempotent() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try harness.makeBatch()
        Manifest.record(index: 0, result: .success, in: batch.directory)
        Manifest.record(index: 1, result: .failure(.serverFull), in: batch.directory)

        harness.uploader.reconnectPending()
        let marker = batch.directory.appendingPathComponent("finished")
        try FileManager.default.setAttributes([.modificationDate: TestClock.reference], ofItemAtPath: marker.path)
        harness.uploader.reconnectPending()
        harness.uploader.reconnectPending()

        let outcome = try #require(harness.recorder.outcomes.first)
        #expect(harness.recorder.outcomes.count == 1)
        #expect(outcome.failures == [FailedUpload(name: "b.jpg", cause: .serverFull)])
        #expect(harness.exists(batch.directory), "a reported batch with failures waits for a retry")
    }

    @Test("A fully uploaded batch found at reconnect is reported and removed")
    func reconnectCleansFinishedBatch() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try harness.makeBatch()
        Manifest.record(index: 0, result: .success, in: batch.directory)
        Manifest.record(index: 1, result: .success, in: batch.directory)

        harness.uploader.reconnectPending()

        #expect(harness.recorder.outcomes.first?.uploaded == 2)
        #expect(!harness.exists(batch.directory))
    }

    @Test("The pending action depends on age, results and the finished marker")
    func pendingActions() {
        let start = TestClock.reference
        func action(results: Int, claimedAt: Date? = nil, after: TimeInterval) -> BackgroundUploader.PendingAction {
            BackgroundUploader.pendingAction(
                startedAt: start, resultCount: results, fileCount: 2, claimedAt: claimedAt, now: start.addingTimeInterval(after)
            )
        }
        #expect(action(results: 0, after: BackgroundUploader.youngAge - 1) == .wait, "the extension may still own it")
        #expect(action(results: 0, after: BackgroundUploader.youngAge + 1) == .reconnect)
        #expect(action(results: 2, after: 1) == .finish, "everything reported already, whoever owns it")
        #expect(action(results: 1, after: BackgroundUploader.youngAge + 1) == .reconnect)
        #expect(action(results: 2, claimedAt: start, after: 10) == .wait)
        #expect(action(results: 2, claimedAt: start, after: BackgroundUploader.failedRetention + 1) == .expire)
    }

    @Test("A young started batch is left alone at reconnect, an old one without results is not finished early")
    func youngBatchIsSkipped() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try harness.makeBatch()
        harness.clock.advance(by: BackgroundUploader.youngAge - 1)

        harness.uploader.reconnectPending()

        #expect(harness.recorder.outcomes.isEmpty)
        #expect(harness.exists(batch.directory))
    }

    @Test("A reported batch past its retention is deleted at reconnect")
    func retentionExpires() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try harness.makeBatch(names: ["a.jpg"])
        harness.uploader.complete(batchID: batch.id, index: 0, result: .failure(.network))
        let marker = batch.directory.appendingPathComponent("finished")
        try FileManager.default.setAttributes([.modificationDate: TestClock.reference], ofItemAtPath: marker.path)

        harness.clock.advance(by: BackgroundUploader.failedRetention - 60)
        harness.uploader.reconnectPending()
        #expect(harness.exists(batch.directory))

        harness.clock.advance(by: 120)
        harness.uploader.reconnectPending()
        #expect(!harness.exists(batch.directory))
        #expect(harness.recorder.outcomes.count == 1, "expiring never reports again")
    }

    @Test("A batch no task runs for is abandoned only once it is older than the stale age")
    func abandonedDecision() {
        let start = TestClock.reference
        #expect(BackgroundUploader.isAbandoned(liveTaskCount: 0, startedAt: start, now: start.addingTimeInterval(BackgroundUploader.staleAge + 1)))
        #expect(!BackgroundUploader.isAbandoned(liveTaskCount: 0, startedAt: start, now: start.addingTimeInterval(BackgroundUploader.staleAge - 1)))
        #expect(!BackgroundUploader.isAbandoned(liveTaskCount: 2, startedAt: start, now: start.addingTimeInterval(BackgroundUploader.staleAge + 1)))
    }

    @Test("Abandoning reports the files still outstanding as failed and keeps their envelopes")
    func abandonOutstanding() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try harness.makeBatch(names: ["a.jpg", "b.jpg", "c.jpg"])
        Manifest.record(index: 0, result: .success, in: batch.directory)

        harness.uploader.abandonOutstanding(batchID: batch.id)
        harness.uploader.abandonOutstanding(batchID: batch.id)

        let outcome = try #require(harness.recorder.outcomes.first)
        #expect(harness.recorder.outcomes.count == 1)
        #expect(outcome.uploaded == 1)
        #expect(outcome.failures.map(\.name) == ["b.jpg", "c.jpg"])
        #expect(outcome.failures.allSatisfy { $0.cause == .other })
        #expect(harness.exists(batch.directory.appendingPathComponent("1.multipart")))
    }

    @Test("An old batch staged but never started is cleaned up, a recent one is kept")
    func unstartedBatches() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        func unstarted() throws -> URL {
            let directory = harness.root.appendingPathComponent(TestID.uuid().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("half written".utf8).write(to: directory.appendingPathComponent("x.multipart"))
            return directory
        }
        let old = try unstarted()
        let recent = try unstarted()
        try FileManager.default.setAttributes(
            [.modificationDate: TestClock.reference.addingTimeInterval(-BackgroundUploader.staleAge - 60)], ofItemAtPath: old.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: TestClock.reference.addingTimeInterval(-60)], ofItemAtPath: recent.path
        )

        harness.uploader.reconnectPending()

        #expect(!harness.exists(old))
        #expect(harness.exists(recent))
    }

    @Test("A folder that cannot be read counts as stale")
    func missingFolderIsStale() {
        #expect(BackgroundUploader.isStale(URL(fileURLWithPath: "/nonexistent/\(TestID.uuid().uuidString)"), now: TestClock.reference))
    }

    // MARK: Waking up

    @Test("The wake up completion is held only when there are events left to wait for")
    func eventsDecision() {
        #expect(BackgroundUploader.shouldCompleteEventsImmediately(liveTaskCount: 0, hasManifest: false, isClaimed: false))
        #expect(BackgroundUploader.shouldCompleteEventsImmediately(liveTaskCount: 0, hasManifest: true, isClaimed: true))
        #expect(!BackgroundUploader.shouldCompleteEventsImmediately(liveTaskCount: 0, hasManifest: true, isClaimed: false))
        #expect(!BackgroundUploader.shouldCompleteEventsImmediately(liveTaskCount: 3, hasManifest: false, isClaimed: false))
    }

    @Test("Waking up for a session with no batch calls the system completion once, at once, with no timer left")
    func unknownSessionCompletesAtOnce() async throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let identifier = BackgroundUploader.identifierPrefix + TestID.uuid().uuidString
        let fired = Counter()

        await withCheckedContinuation { continuation in
            harness.uploader.handleEvents(forSession: identifier) {
                fired.call()
                continuation.resume()
            }
        }

        #expect(fired.count == 1)
        #expect(harness.events.scheduledDelays == [BackgroundUploader.eventsTimeout], "the safety timer was armed")
        #expect(harness.events.pendingTimers == 0, "and cancelled once the completion had run")
    }

    @Test("Waking up for a batch with live tasks holds the completion until the safety timer or the events finish")
    func liveTasksHoldTheCompletion() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try harness.makeBatch()
        harness.tasks.set(LiveTasks(count: 2, indexes: [0, 1]), forBatch: batch.id)
        let fired = Counter()

        harness.uploader.handleEvents(forSession: BackgroundUploader.identifierPrefix + batch.id, completion: fired.call)
        #expect(fired.count == 0)
        #expect(harness.events.pendingTimers == 1)

        harness.events.fireTimers()
        #expect(fired.count == 1, "the timer completes it before the system's deadline")
    }

    // MARK: Starting and retrying

    @Test("Starting a batch records its manifest and hands every file to the session with the cookie")
    func startSubmitsEveryFile() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let source = harness.root.appendingPathComponent("source.jpg")
        try Data("photo".utf8).write(to: source)
        var batch = try harness.uploader.makeBatch(credentials: Harness.credentials, destination: "Photos")
        try batch.add(batch.envelope(for: source, fileName: "one.jpg"))
        try batch.add(batch.envelope(for: source, fileName: "two.jpg"))

        try harness.uploader.start(batch)

        let manifest = try #require(Manifest.load(from: harness.root.appendingPathComponent(batch.id)))
        #expect(manifest.fileNames == ["one.jpg", "two.jpg"])
        #expect(manifest.startedAt == TestClock.reference)
        #expect(manifest.contentTypes.allSatisfy { $0.hasPrefix("multipart/form-data; boundary=") })
        let started = try #require(harness.starter.started.first)
        #expect(started.identifier == BackgroundUploader.identifierPrefix + batch.id)
        #expect(started.specs.map(\.index) == [0, 1])
        #expect(started.specs.allSatisfy { $0.request.value(forHTTPHeaderField: "Cookie") == "connect.sid=secret" })
    }

    @Test("Retry resends only the failed files, with the current cookie, and the batch is reported again")
    func retryResendsFailed() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try harness.makeBatch(names: ["a.jpg", "b.jpg", "c.jpg"])
        harness.uploader.complete(batchID: batch.id, index: 0, result: .success)
        harness.uploader.complete(batchID: batch.id, index: 1, result: .failure(.unauthorized))
        harness.uploader.complete(batchID: batch.id, index: 2, result: .failure(.network))
        #expect(harness.recorder.outcomes.count == 1)
        #expect(harness.uploader.accountsNeedingSignIn() == [Harness.credentials.accountID])
        var fresh = Harness.credentials
        fresh.cookieValue = "fresh"
        harness.clock.advance(by: 600)

        let count = harness.uploader.retryFailed(batchID: batch.id, credentials: fresh)

        #expect(count == 2)
        let started = try #require(harness.starter.started.first)
        #expect(started.specs.map(\.index) == [1, 2])
        #expect(started.specs.allSatisfy { $0.request.value(forHTTPHeaderField: "Cookie") == "connect.sid=fresh" })
        #expect(harness.uploader.accountsNeedingSignIn().isEmpty, "signing in again settles the flag")
        let manifest = try #require(Manifest.load(from: batch.directory))
        #expect(manifest.startedAt == TestClock.reference.addingTimeInterval(600))

        harness.uploader.complete(batchID: batch.id, index: 1, result: .success)
        harness.uploader.complete(batchID: batch.id, index: 2, result: .success)

        #expect(harness.recorder.outcomes.count == 2)
        #expect(harness.recorder.outcomes.last?.uploaded == 3)
        #expect(!harness.exists(batch.directory), "everything went through, nothing is kept")
    }

    @Test("Retry refuses another account's batch, an unknown batch and a path that is no batch id")
    func retryGuards() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try harness.makeBatch(names: ["a.jpg"])
        harness.uploader.complete(batchID: batch.id, index: 0, result: .failure(.other))
        var other = Harness.credentials
        other.username = "someone else"

        #expect(harness.uploader.retryFailed(batchID: batch.id, credentials: other) == 0)
        #expect(harness.uploader.retryFailed(batchID: TestID.uuid().uuidString, credentials: Harness.credentials) == 0)
        #expect(harness.uploader.retryFailed(batchID: "../etc", credentials: Harness.credentials) == 0)
        #expect(harness.starter.started.isEmpty)
    }

    @Test("Retry has nothing to send when no failed envelope is left")
    func retryNeedsEnvelopes() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try harness.makeBatch(names: ["a.jpg"])
        harness.uploader.complete(batchID: batch.id, index: 0, result: .failure(.other))
        try FileManager.default.removeItem(at: batch.directory.appendingPathComponent("0.multipart"))

        #expect(harness.uploader.retryFailed(batchID: batch.id, credentials: Harness.credentials) == 0)
    }

    @Test("A reported batch with failures keeps its envelopes until the retention ends, whatever the user does with the notification")
    func failedEnvelopesSurviveUntilRetention() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try harness.makeBatch(names: ["a.jpg"])
        harness.uploader.complete(batchID: batch.id, index: 0, result: .failure(.network))
        let marker = batch.directory.appendingPathComponent("finished")
        try FileManager.default.setAttributes([.modificationDate: TestClock.reference], ofItemAtPath: marker.path)

        harness.uploader.reconnectPending()
        #expect(harness.exists(batch.directory.appendingPathComponent("0.multipart")))
        harness.clock.advance(by: BackgroundUploader.failedRetention - 1)
        harness.uploader.reconnectPending()
        #expect(harness.exists(batch.directory.appendingPathComponent("0.multipart")))
        harness.clock.advance(by: 2)
        harness.uploader.reconnectPending()
        #expect(!harness.exists(batch.directory))
    }

    // MARK: Sign in flags

    @Test("Only a 401 flags the account as needing to sign in")
    func unauthorizedFlagsTheAccount() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try harness.makeBatch(names: ["a.jpg", "b.jpg", "c.jpg"])

        harness.uploader.complete(batchID: batch.id, index: 0, result: .failure(.forbidden))
        harness.uploader.complete(batchID: batch.id, index: 1, result: .failure(.network))
        #expect(harness.uploader.accountsNeedingSignIn().isEmpty)
        harness.uploader.complete(batchID: batch.id, index: 2, result: .failure(.unauthorized))

        #expect(harness.uploader.accountsNeedingSignIn() == [Harness.credentials.accountID])
        harness.uploader.clearNeedsSignIn(accountID: Harness.credentials.accountID)
        #expect(harness.uploader.accountsNeedingSignIn().isEmpty)
    }

    // MARK: Disk space

    @Test("A file that does not fit is refused with the specific error and leaves no envelope")
    func insufficientSpace() throws {
        let harness = try Harness(availableCapacity: { _ in 1024 })
        defer { harness.tearDown() }
        let source = harness.root.appendingPathComponent("big.bin")
        try Data(count: 2048).write(to: source)
        let batch = try harness.uploader.makeBatch(credentials: Harness.credentials, destination: "Docs")

        #expect(throws: ShareUploadError.insufficientSpace) {
            try batch.envelope(for: source, fileName: "big.bin")
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: harness.root.appendingPathComponent(batch.id).path)
        #expect(leftovers.isEmpty)
    }

    @Test("Room is judged against the file size plus a reserve")
    func roomDecision() {
        #expect(DiskSpace.hasRoom(forBytes: 100, available: nil), "an unknown capacity never blocks")
        #expect(DiskSpace.hasRoom(forBytes: 100, available: 100 + DiskSpace.reservedBytes))
        #expect(!DiskSpace.hasRoom(forBytes: 100, available: 100 + DiskSpace.reservedBytes - 1))
        #expect(!DiskSpace.hasRoom(forBytes: 0, available: 0))
    }
}
