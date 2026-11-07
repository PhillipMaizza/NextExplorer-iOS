import CoreModels
import Foundation
@testable import ShareUploads
import Testing

@Suite("Background uploader wake ups, late events and races")
struct BackgroundUploaderEventsTests {
    private enum Constants {
        static let freshAge: TimeInterval = 60
        static let staleMargin: TimeInterval = 60
        static let concurrentIterations = 32
        static let racedBatches = 25
    }

    private func identifier() -> String {
        BackgroundUploader.identifierPrefix + UUID().uuidString
    }

    // MARK: Wake up completion handlers

    @Test("The safety timer is armed for the system's deadline and completes its own registration")
    func timerCompletesItsOwnRegistration() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let handler = Counter()

        harness.uploader.registerEvents(forSession: identifier(), completion: handler.call)
        #expect(harness.events.scheduledDelays == [BackgroundUploader.eventsTimeout])
        harness.events.fireTimers()

        #expect(handler.count == 1)
    }

    @Test("Normal completion cancels the timer, so it can never complete anything later")
    func normalCompletionCancelsTheTimer() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let handler = Counter()
        let session = identifier()

        harness.uploader.registerEvents(forSession: session, completion: handler.call)
        harness.uploader.completeEvents(identifier: session)

        #expect(handler.count == 1)
        #expect(harness.events.pendingTimers == 0)
        harness.events.fireTimers()
        #expect(handler.count == 1)
    }

    @Test("A second wake up for the same session calls the first handler right away and keeps the second")
    func displacedHandlerIsCalled() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let first = Counter()
        let second = Counter()
        let session = identifier()

        harness.uploader.registerEvents(forSession: session, completion: first.call)
        harness.uploader.registerEvents(forSession: session, completion: second.call)

        #expect(first.count == 1, "the system is never left waiting on the first handler")
        #expect(second.count == 0)
        #expect(harness.events.pendingTimers == 1, "the displaced registration's timer is gone")
        harness.uploader.completeEvents(identifier: session)
        #expect(first.count == 1)
        #expect(second.count == 1)
    }

    @Test("A stale registration's token never completes a newer wake up")
    func staleTokenIsIgnored() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let first = Counter()
        let second = Counter()
        let session = identifier()

        let oldToken = harness.uploader.registerEvents(forSession: session, completion: first.call)
        harness.uploader.registerEvents(forSession: session, completion: second.call)
        harness.uploader.completeEvents(identifier: session, token: oldToken)

        #expect(second.count == 0, "an old timer or task query must not end the newer wake up early")
        harness.events.fireTimers()
        #expect(second.count == 1)
        #expect(first.count == 1)
    }

    @Test("Finished events and an invalidated session together call the handler exactly once, in either order")
    func handlerRunsExactlyOnce() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        for order in [["finished", "invalid"], ["invalid", "finished"]] {
            let handler = Counter()
            let session = identifier()
            harness.uploader.registerEvents(forSession: session, completion: handler.call)
            for _ in order {
                harness.uploader.completeEvents(identifier: session)
            }
            #expect(handler.count == 1, "\(order)")
        }
        harness.events.fireTimers()
    }

    @Test("A session with nothing to wait for completes at once and leaves no timer behind")
    func unknownSessionLeavesNoTimer() async throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let session = identifier()

        await withCheckedContinuation { continuation in
            harness.uploader.handleEvents(forSession: session) { continuation.resume() }
        }

        #expect(harness.events.pendingTimers == 0)
    }

    // MARK: Cancelling with the extension at work

    @Test("A batch without a manifest that was touched a moment ago is still being filled in: an account change keeps it")
    func freshManifestlessBatchSurvivesCancel() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let staging = harness.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("half".utf8).write(to: staging.appendingPathComponent("x.multipart"))
        try FileManager.default.setAttributes(
            [.modificationDate: TestClock.reference.addingTimeInterval(-Constants.freshAge)], ofItemAtPath: staging.path
        )

        harness.uploader.cancel(keepingAccounts: [])

        #expect(harness.exists(staging.appendingPathComponent("x.multipart")))
    }

    @Test("A stale batch without a manifest is a leftover that cancelling removes")
    func staleManifestlessBatchIsCancelled() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let staging = harness.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.modificationDate: TestClock.reference.addingTimeInterval(-BackgroundUploader.staleAge - Constants.staleMargin)],
            ofItemAtPath: staging.path
        )

        harness.uploader.cancel(keepingAccounts: [])

        #expect(!harness.exists(staging))
    }

    // MARK: The extension's heartbeat

    @Test("A manifest touched in the last two minutes is young whatever its start date says")
    func heartbeatMakesABatchYoung() {
        let start = TestClock.reference
        let now = start.addingTimeInterval(BackgroundUploader.staleAge)
        let recent = now.addingTimeInterval(-BackgroundUploader.heartbeatAge + 1)
        let old = now.addingTimeInterval(-BackgroundUploader.heartbeatAge - 1)

        #expect(BackgroundUploader.isYoung(startedAt: start, touchedAt: recent, now: now))
        #expect(!BackgroundUploader.isYoung(startedAt: start, touchedAt: old, now: now))
        #expect(!BackgroundUploader.isYoung(startedAt: start, touchedAt: nil, now: now))
        #expect(!BackgroundUploader.isYoung(startedAt: start, touchedAt: now.addingTimeInterval(1), now: now), "a touch from the future is no heartbeat")
        #expect(BackgroundUploader.isYoung(startedAt: now.addingTimeInterval(-1), touchedAt: nil, now: now))
    }

    @Test("An old batch with a recent heartbeat waits, the same batch without one is reconnected")
    func heartbeatDecidesTheAction() {
        let start = TestClock.reference
        let now = start.addingTimeInterval(BackgroundUploader.youngAge * 4)
        func action(touchedAt: Date?) -> BackgroundUploader.PendingAction {
            BackgroundUploader.pendingAction(
                startedAt: start, touchedAt: touchedAt, resultCount: 0, fileCount: 2, claimedAt: nil, now: now
            )
        }
        #expect(action(touchedAt: now.addingTimeInterval(-BackgroundUploader.heartbeatAge + 1)) == .wait)
        #expect(action(touchedAt: now.addingTimeInterval(-BackgroundUploader.heartbeatAge - 1)) == .reconnect)
        #expect(action(touchedAt: nil) == .reconnect)
    }

    @Test("Starting tasks touches the manifest, so the app sees a live owner")
    func startingTouchesTheManifest() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let source = harness.root.appendingPathComponent("source.jpg")
        try Data("photo".utf8).write(to: source)
        var batch = try harness.uploader.makeBatch(credentials: Harness.credentials, destination: "Photos")
        try batch.add(batch.envelope(for: source, fileName: "one.jpg"))
        harness.clock.advance(by: BackgroundUploader.staleAge)

        try harness.uploader.start(batch)

        let touched = try #require(Manifest.touchedAt(harness.root.appendingPathComponent(batch.id)))
        #expect(touched == harness.clock.now)
    }

    // MARK: Late events after abandonment

    @Test("An abandoned file is recorded as abandoned, not as a plain failure")
    func abandonedIsRecordedDistinctly() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try harness.makeBatch(names: ["a.jpg", "b.jpg"])
        Manifest.record(index: 0, result: .success, in: batch.directory)

        harness.uploader.abandonOutstanding(batchID: batch.id)

        #expect(Manifest.results(in: batch.directory)[1] == .abandoned)
    }

    @Test("A late success overwrites the abandonment, reports the batch again and removes it when nothing failed")
    func lateSuccessCorrectsTheReport() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try harness.makeBatch(names: ["a.jpg", "b.jpg"])
        Manifest.record(index: 0, result: .success, in: batch.directory)
        harness.uploader.abandonOutstanding(batchID: batch.id)
        #expect(harness.recorder.outcomes.last?.failures.map(\.name) == ["b.jpg"])

        harness.uploader.complete(batchID: batch.id, index: 1, result: .success)

        #expect(harness.recorder.outcomes.count == 2)
        let corrected = try #require(harness.recorder.outcomes.last)
        #expect(corrected.uploaded == 2)
        #expect(corrected.failures.isEmpty)
        #expect(!harness.exists(batch.directory), "the server has both files: nothing is left to retry")
    }

    @Test("A late success among other abandoned files corrects only its own file")
    func lateSuccessKeepsTheOthersFailed() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try harness.makeBatch(names: ["a.jpg", "b.jpg", "c.jpg"])
        harness.uploader.abandonOutstanding(batchID: batch.id)

        harness.uploader.complete(batchID: batch.id, index: 1, result: .success)

        let corrected = try #require(harness.recorder.outcomes.last)
        #expect(harness.recorder.outcomes.count == 2)
        #expect(corrected.uploaded == 1)
        #expect(corrected.failures.map(\.name) == ["a.jpg", "c.jpg"])
        #expect(Manifest.results(in: batch.directory)[1] == .success)
    }

    @Test("A late failure after abandonment does not report the batch a second time")
    func lateFailureStaysQuiet() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try harness.makeBatch(names: ["a.jpg"])
        harness.uploader.abandonOutstanding(batchID: batch.id)

        harness.uploader.complete(batchID: batch.id, index: 0, result: .failure(.network))

        #expect(harness.recorder.outcomes.count == 1)
        #expect(Manifest.results(in: batch.directory)[0] == .failure(.network))
    }

    @Test("Retry skips a file whose latest result is a success, even when its envelope is still there")
    func retrySkipsSucceededFiles() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try harness.makeBatch(names: ["a.jpg", "b.jpg", "c.jpg"])
        Manifest.record(index: 0, result: .success, in: batch.directory)
        harness.uploader.abandonOutstanding(batchID: batch.id)
        Manifest.record(index: 1, result: .success, in: batch.directory)

        let count = harness.uploader.retryFailed(batchID: batch.id, credentials: Harness.credentials)

        #expect(count == 1)
        #expect(harness.starter.started.first?.specs.map(\.index) == [2])
    }

    // MARK: Two processes

    @Test("Two uploaders on one folder, finishing the same batch at once, report it exactly once")
    func claimHoldsAcrossUploaders() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let secondRecorder = RecordingNotifier()
        let clock = harness.clock
        let second = BackgroundUploader(
            root: harness.root, notifier: secondRecorder.notifier, defaults: harness.defaults,
            now: { clock.now }, startTasks: harness.starter.start
        )
        let uploaders = [harness.uploader, second]

        for _ in 0 ..< Constants.racedBatches {
            let batch = try harness.makeBatch(names: ["a.jpg", "b.jpg"])
            DispatchQueue.concurrentPerform(iterations: Constants.concurrentIterations) { iteration in
                uploaders[iteration % uploaders.count].finishBatch(id: batch.id, manifest: batch.manifest)
            }
        }

        let reported = harness.recorder.outcomes.count + secondRecorder.outcomes.count
        #expect(reported == Constants.racedBatches, "one report per batch across both processes")
    }

    @Test("The last two results arriving in two uploaders at once still report the batch once")
    func lastResultsRaceAcrossUploaders() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let secondRecorder = RecordingNotifier()
        let clock = harness.clock
        let second = BackgroundUploader(
            root: harness.root, notifier: secondRecorder.notifier, defaults: harness.defaults,
            now: { clock.now }, startTasks: harness.starter.start
        )

        for _ in 0 ..< Constants.racedBatches {
            let batch = try harness.makeBatch(names: ["a.jpg", "b.jpg"])
            DispatchQueue.concurrentPerform(iterations: 2) { index in
                (index == 0 ? harness.uploader : second).complete(batchID: batch.id, index: index, result: .failure(.network))
            }
        }

        let reported = harness.recorder.outcomes.count + secondRecorder.outcomes.count
        #expect(reported == Constants.racedBatches)
    }
}
