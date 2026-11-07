import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing

@MainActor
struct UploadsFeatureTests {
    private let serverURL = URL(string: "https://example.com")!
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private nonisolated func pending(_ name: String, id: UUID, destination: String = "Inbox") -> PendingUpload {
        PendingUpload(id: id, fileURL: URL(fileURLWithPath: "/tmp/\(name)"), fileName: name, destination: destination)
    }

    private nonisolated func uploaded(_ name: String, destination: String = "Inbox") -> FileItem {
        FileItem(name: name, path: destination, dateModified: Date(timeIntervalSince1970: 1), size: 10, kind: "txt")
    }

    private nonisolated func job(
        _ name: String, id: UUID, status: UploadsFeature.UploadJob.Status,
        isTransportFailure: Bool = false, autoRetryCount: Int = 0
    ) -> UploadsFeature.UploadJob {
        UploadsFeature.UploadJob(
            id: id, fileURL: URL(fileURLWithPath: "/tmp/\(name)"), fileName: name,
            destination: "Inbox", progress: status == .completed ? 1 : 0, status: status,
            isTransportFailure: isTransportFailure, autoRetryCount: autoRetryCount
        )
    }

    private nonisolated func summary(
        uploaded: Int, failed: Int, lastDestination: String?, changedPaths: Set<String>
    ) -> UploadsFeature.FinishSummary {
        UploadsFeature.FinishSummary(
            uploadedCount: uploaded, failedCount: failed,
            lastDestination: lastDestination, changedPaths: changedPaths
        )
    }

    @Test
    func filesUploadOneAtATimeAndTheQueueFinishes() async {
        let a = UUID(0)
        let b = UUID(1)
        let store = TestStore(initialState: UploadsFeature.State(serverURL: serverURL)) {
            UploadsFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.filesClient.uploadFile = { _, _, name, _, _ in uploaded(name) }
        }
        store.exhaustivity = .off

        await store.send(.enqueue([pending("a.txt", id: a), pending("b.txt", id: b)]))
        await store.receive(\.startNextIfIdle) {
            $0.jobs[id: a]?.status = .uploading
        }
        #expect(store.state.jobs[id: b]?.status == .queued)

        await store.receive(\.uploadResponse) {
            $0.jobs[id: a]?.status = .completed
            $0.jobs[id: a]?.progress = 1
        }
        await store.receive(\.startNextIfIdle) {
            $0.jobs[id: b]?.status = .uploading
        }
        await store.receive(\.uploadResponse) {
            $0.jobs[id: b]?.status = .completed
            $0.jobs[id: b]?.progress = 1
        }
        await store.receive(.delegate(.queueFinished(
            summary(uploaded: 2, failed: 0, lastDestination: "Inbox", changedPaths: ["Inbox"])
        )))
        #expect(store.state.isActive == false)
    }

    @Test
    func aFailedUploadReportsNoChangedPathsAndCanBeRetried() async {
        let a = UUID(0)
        let attempts = LockIsolated(0)
        let store = TestStore(initialState: UploadsFeature.State(serverURL: serverURL)) {
            UploadsFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.filesClient.uploadFile = { _, _, name, _, _ in
                let n = attempts.withValue { value -> Int in value += 1; return value }
                if n == 1 {
                    throw FilesClientError.server(statusCode: 500)
                }
                return uploaded(name)
            }
        }
        store.exhaustivity = .off

        await store.send(.enqueue([pending("a.txt", id: a)]))
        await store.receive(\.uploadResponse) {
            $0.jobs[id: a]?.status = .failed(L10n.Uploads.failedGeneric)
        }
        await store.receive(.delegate(.queueFinished(
            summary(uploaded: 0, failed: 1, lastDestination: nil, changedPaths: [])
        )))

        await store.send(.retryTapped(id: a)) {
            $0.jobs[id: a]?.status = .queued
            $0.jobs[id: a]?.progress = 0
        }
        await store.receive(\.uploadResponse) {
            $0.jobs[id: a]?.status = .completed
            $0.jobs[id: a]?.progress = 1
        }
    }

    @Test
    func cancellingTheActiveJobAdvancesToTheNext() async {
        let a = UUID(0)
        let b = UUID(1)
        let store = TestStore(initialState: UploadsFeature.State(serverURL: serverURL)) {
            UploadsFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.filesClient.uploadFile = { _, _, _, _, _ in
                try await Task.never()
            }
        }
        store.exhaustivity = .off

        await store.send(.enqueue([pending("a.txt", id: a), pending("b.txt", id: b)]))
        await store.receive(\.startNextIfIdle)
        await store.send(.cancelJobTapped(id: a)) {
            $0.jobs[id: a] = nil
        }
        await store.receive(\.startNextIfIdle) {
            $0.jobs[id: b]?.status = .uploading
        }
        await store.send(.cancelAllTapped) {
            $0.jobs.removeAll()
        }
    }

    @Test
    func failuresKeepTheBarUpAndRetryAllRequeuesThem() async {
        let attempts = LockIsolated(0)
        let store = TestStore(initialState: UploadsFeature.State(serverURL: serverURL)) {
            UploadsFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.filesClient.uploadFile = { _, _, name, _, _ in
                let n = attempts.withValue { value -> Int in value += 1; return value }
                if n <= 2 {
                    throw FilesClientError.server(statusCode: 500)
                }
                return uploaded(name)
            }
        }
        store.exhaustivity = .off

        await store.send(.enqueue([pending("a.txt", id: UUID(0)), pending("b.txt", id: UUID(1))]))
        // Both fail on the first pass.
        await store.receive(.delegate(.queueFinished(
            summary(uploaded: 0, failed: 2, lastDestination: nil, changedPaths: [])
        )))
        #expect(store.state.isActive == false)
        #expect(store.state.failedCount == 2)
        #expect(store.state.isBarVisible == true)

        await store.send(.retryAllFailedTapped) {
            $0.jobs[id: UUID(0)]?.status = .queued
            $0.jobs[id: UUID(1)]?.status = .queued
        }
        await store.receive(\.startNextIfIdle) {
            $0.jobs[id: UUID(0)]?.status = .uploading
        }
        // Second pass succeeds.
        await store.receive(.delegate(.queueFinished(
            summary(uploaded: 2, failed: 0, lastDestination: "Inbox", changedPaths: ["Inbox"])
        )))
        #expect(store.state.failedCount == 0)
        #expect(store.state.isBarVisible == false)
    }

    @Test
    func batchFinishedReportsEveryDistinctDestinationThatSucceeded() async {
        let store = TestStore(initialState: UploadsFeature.State(serverURL: serverURL)) {
            UploadsFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.filesClient.uploadFile = { _, _, name, dest, _ in uploaded(name, destination: dest) }
        }
        store.exhaustivity = .off

        await store.send(.enqueue([
            pending("a.txt", id: UUID(0), destination: "Inbox"),
            pending("b.txt", id: UUID(1), destination: "Inbox"),
            pending("c.txt", id: UUID(2), destination: "Archive"),
        ]))
        await store.receive(.delegate(.queueFinished(
            summary(uploaded: 3, failed: 0, lastDestination: "Archive", changedPaths: ["Inbox", "Archive"])
        )))
    }

    @Test
    func appResumedRequeuesFailedJobsAndLeavesActiveUploadsAlone() async {
        var state = UploadsFeature.State(serverURL: serverURL)
        state.jobs = [
            job("a.txt", id: UUID(0), status: .uploading),
            job("b.txt", id: UUID(1), status: .failed("connection lost"), isTransportFailure: true),
            job("c.txt", id: UUID(2), status: .completed),
            job("d.txt", id: UUID(3), status: .queued),
        ]
        let store = TestStore(initialState: state) {
            UploadsFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.filesClient.uploadFile = { _, _, _, _, _ in try await Task.never() }
        }
        store.exhaustivity = .off

        await store.send(.appResumed) {
            $0.jobs[id: UUID(1)]?.status = .queued
            $0.jobs[id: UUID(1)]?.autoRetryCount = 1
        }
        // The genuinely uploading job is untouched; the completed one stays; the failed one
        // is requeued but the active upload still holds the slot.
        #expect(store.state.jobs[id: UUID(0)]?.status == .uploading)
        #expect(store.state.jobs[id: UUID(2)]?.status == .completed)
        #expect(store.state.jobs[id: UUID(3)]?.status == .queued)
        await store.receive(\.startNextIfIdle)
    }

    @Test
    func appResumedRestartsAnUploadThatWedgedWellPastAPlausibleTransferTime() async {
        var state = UploadsFeature.State(serverURL: serverURL)
        var wedged = job("a.txt", id: UUID(0), status: .uploading)
        wedged.startedAt = now.addingTimeInterval(-600) // 10 minutes ago
        state.jobs = [wedged, job("b.txt", id: UUID(1), status: .queued)]
        let store = TestStore(initialState: state) {
            UploadsFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.filesClient.uploadFile = { _, _, _, _, _ in try await Task.never() }
        }
        store.exhaustivity = .off

        await store.send(.appResumed) {
            $0.jobs[id: UUID(0)]?.status = .queued
            $0.jobs[id: UUID(0)]?.progress = 0
            $0.jobs[id: UUID(0)]?.autoRetryCount = 1
        }
        await store.receive(\.startNextIfIdle) {
            $0.jobs[id: UUID(0)]?.status = .uploading
            $0.jobs[id: UUID(0)]?.startedAt = now
        }
    }

    @Test(arguments: [FilesClientError.offline, .network("lost")])
    func appResumedRequeuesTransportFailures(error: FilesClientError) async {
        let store = TestStore(initialState: UploadsFeature.State(serverURL: serverURL)) {
            UploadsFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.filesClient.uploadFile = { _, _, _, _, _ in throw error }
        }
        store.exhaustivity = .off

        await store.send(.enqueue([pending("a.txt", id: UUID(0))]))
        await store.receive(\.uploadResponse)
        #expect(store.state.jobs[id: UUID(0)]?.isTransportFailure == true)

        await store.send(.appResumed)
        #expect(store.state.jobs[id: UUID(0)]?.autoRetryCount == 1)
        await store.receive(\.startNextIfIdle)
        await store.skipReceivedActions()
    }

    @Test(arguments: [
        FilesClientError.server(statusCode: 413),
        .serverMessage(statusCode: 507, message: "Quota exceeded"),
        .forbidden(message: nil),
        .server(statusCode: 400),
        .decoding("source missing"),
        .sessionExpired,
    ])
    func appResumedNeverRequeuesPermanentFailures(error: FilesClientError) async {
        let attempts = LockIsolated(0)
        let store = TestStore(initialState: UploadsFeature.State(serverURL: serverURL)) {
            UploadsFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.filesClient.uploadFile = { _, _, _, _, _ in
                attempts.withValue { $0 += 1 }
                throw error
            }
        }
        store.exhaustivity = .off

        await store.send(.enqueue([pending("a.txt", id: UUID(0))]))
        await store.receive(\.uploadResponse)
        await store.send(.appResumed)

        guard case .failed = store.state.jobs[id: UUID(0)]?.status else {
            Issue.record("job should stay failed")
            return
        }
        #expect(store.state.jobs[id: UUID(0)]?.autoRetryCount == 0)
        #expect(attempts.value == 1)
    }

    @Test
    func appResumedDoesNotRequeueAJobWhoseSourceWasDeleted() async {
        var state = UploadsFeature.State(serverURL: serverURL)
        state.jobs = [job("gone.txt", id: UUID(0), status: .failed("offline"), isTransportFailure: true)]
        let store = TestStore(initialState: state) {
            UploadsFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.uploadStaging.sourceExists = { _ in false }
        }
        store.exhaustivity = .off

        await store.send(.appResumed)

        #expect(store.state.jobs[id: UUID(0)]?.status == .failed("offline"))
        #expect(store.state.jobs[id: UUID(0)]?.isTransportFailure == false)
    }

    @Test
    func aTimedOutUploadIsNeverRequeuedAutomaticallyBecauseTheServerMayHaveStoredIt() async {
        let attempts = LockIsolated(0)
        let store = TestStore(initialState: UploadsFeature.State(serverURL: serverURL)) {
            UploadsFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.filesClient.uploadFile = { _, _, _, _, _ in
                attempts.withValue { $0 += 1 }
                throw FilesClientError.timedOut
            }
        }
        store.exhaustivity = .off

        await store.send(.enqueue([pending("a.txt", id: UUID(0))]))
        await store.receive(\.uploadResponse)
        await store.send(.appResumed)

        #expect(store.state.jobs[id: UUID(0)]?.isTransportFailure == false)
        #expect(store.state.jobs[id: UUID(0)]?.autoRetryCount == 0)
        #expect(attempts.value == 1)
        await store.send(.retryTapped(id: UUID(0)))
        await store.receive(\.startNextIfIdle)
        await store.skipReceivedActions()
        #expect(attempts.value == 2)
    }

    @Test
    func aWedgedUploadAtTheRetryCapFailsAndAnnouncesTheDrainedQueue() async {
        var state = UploadsFeature.State(serverURL: serverURL)
        var wedged = job("a.txt", id: UUID(0), status: .uploading, autoRetryCount: 3)
        wedged.startedAt = now.addingTimeInterval(-600)
        state.jobs = [wedged]
        let store = TestStore(initialState: state) {
            UploadsFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }
        store.exhaustivity = .off

        await store.send(.appResumed)
        await store.receive(.delegate(.queueFinished(summary(uploaded: 0, failed: 1, lastDestination: nil, changedPaths: []))))

        #expect(store.state.jobs[id: UUID(0)]?.status == .failed(L10n.Uploads.failedGeneric))
        #expect(store.state.jobs[id: UUID(0)]?.autoRetryCount == 3)
    }

    @Test
    func aFailedJobAtTheRetryCapKeepsItsRealError() async {
        var state = UploadsFeature.State(serverURL: serverURL)
        state.jobs = [job("a.txt", id: UUID(0), status: .failed("Quota exceeded"), isTransportFailure: true, autoRetryCount: 3)]
        let store = TestStore(initialState: state) {
            UploadsFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }
        store.exhaustivity = .off

        await store.send(.appResumed)

        #expect(store.state.jobs[id: UUID(0)]?.status == .failed("Quota exceeded"))
        #expect(store.state.jobs[id: UUID(0)]?.isTransportFailure == false)
    }

    @Test
    func appResumedStopsRequeueingOnceTheRetryCapIsReached() async {
        var state = UploadsFeature.State(serverURL: serverURL)
        state.jobs = [job("a.txt", id: UUID(0), status: .failed("offline"), isTransportFailure: true, autoRetryCount: 3)]
        let store = TestStore(initialState: state) {
            UploadsFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }
        store.exhaustivity = .off

        await store.send(.appResumed)

        guard case .failed = store.state.jobs[id: UUID(0)]?.status else {
            Issue.record("job should stay failed at the cap")
            return
        }
        #expect(store.state.jobs[id: UUID(0)]?.autoRetryCount == 3)
    }

    @Test
    func manualRetryResetsTheAutomaticRetryCounter() async {
        var state = UploadsFeature.State(serverURL: serverURL)
        state.jobs = [job("a.txt", id: UUID(0), status: .failed("offline"), isTransportFailure: true, autoRetryCount: 3)]
        let store = TestStore(initialState: state) {
            UploadsFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.filesClient.uploadFile = { _, _, _, _, _ in try await Task.never() }
        }
        store.exhaustivity = .off

        await store.send(.retryTapped(id: UUID(0)))
        #expect(store.state.jobs[id: UUID(0)]?.autoRetryCount == 0)
        await store.receive(\.startNextIfIdle)
        await store.send(.cancelAllTapped)
    }

    @Test
    func cancellingTheLastPendingJobAfterSomeFinishedStillReportsTheFinishedFiles() async {
        var state = UploadsFeature.State(serverURL: serverURL)
        state.jobs = [
            job("a.txt", id: UUID(0), status: .completed),
            job("b.txt", id: UUID(1), status: .uploading),
        ]
        let store = TestStore(initialState: state) { UploadsFeature() }
        store.exhaustivity = .off

        await store.send(.cancelJobTapped(id: UUID(1)))
        await store.receive(.delegate(.queueFinished(
            summary(uploaded: 1, failed: 0, lastDestination: "Inbox", changedPaths: ["Inbox"])
        )))
    }

    @Test
    func cancellingAJobWhileOthersStillRunDoesNotAnnounceTheQueueFinished() async {
        var state = UploadsFeature.State(serverURL: serverURL)
        state.jobs = [
            job("a.txt", id: UUID(0), status: .completed),
            job("b.txt", id: UUID(1), status: .uploading),
            job("c.txt", id: UUID(2), status: .queued),
        ]
        let store = TestStore(initialState: state) {
            UploadsFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.filesClient.uploadFile = { _, _, _, _, _ in try await Task.never() }
        }

        await store.send(.cancelJobTapped(id: UUID(1))) {
            $0.jobs[id: UUID(1)] = nil
        }
        await store.receive(\.startNextIfIdle) {
            $0.jobs[id: UUID(2)]?.status = .uploading
            $0.jobs[id: UUID(2)]?.startedAt = now
        }
        await store.send(.cancelAllTapped) {
            $0.jobs.removeAll()
        }
        await store.receive(.delegate(.queueFinished(
            summary(uploaded: 1, failed: 0, lastDestination: "Inbox", changedPaths: ["Inbox"])
        )))
    }

    @Test
    func cancelAllWithFinishedFilesReportsThemAndWithNothingFinishedStaysQuiet() async {
        var state = UploadsFeature.State(serverURL: serverURL)
        state.jobs = [
            job("a.txt", id: UUID(0), status: .completed),
            job("b.txt", id: UUID(1), status: .uploading),
            job("c.txt", id: UUID(2), status: .queued),
        ]
        let store = TestStore(initialState: state) { UploadsFeature() }
        store.exhaustivity = .off

        await store.send(.cancelAllTapped)
        await store.receive(.delegate(.queueFinished(
            summary(uploaded: 1, failed: 0, lastDestination: "Inbox", changedPaths: ["Inbox"])
        )))
        #expect(store.state.jobs.isEmpty)

        var quiet = UploadsFeature.State(serverURL: serverURL)
        quiet.jobs = [job("d.txt", id: UUID(3), status: .uploading)]
        let quietStore = TestStore(initialState: quiet) { UploadsFeature() }
        await quietStore.send(.cancelAllTapped) { $0.jobs.removeAll() }
    }

    @Test
    func clearingAnAlreadyAnnouncedQueueDoesNotAnnounceItAgain() async {
        var state = UploadsFeature.State(serverURL: serverURL)
        state.jobs = [job("a.txt", id: UUID(0), status: .completed)]
        let store = TestStore(initialState: state) { UploadsFeature() }

        await store.send(.cancelAllTapped) { $0.jobs.removeAll() }
    }

    @Test
    func aSessionExpiredUploadFailsTheJobAndTripsTheAppWideExpiryFlag() async {
        @Shared(.inMemory(SessionExpiry.sharedKey)) var sessionDidExpire = false
        $sessionDidExpire.withLock { $0 = false }

        let store = TestStore(initialState: UploadsFeature.State(serverURL: serverURL)) {
            UploadsFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.filesClient.uploadFile = { _, _, _, _, _ in throw FilesClientError.sessionExpired }
        }
        store.exhaustivity = .off

        await store.send(.enqueue([pending("a.txt", id: UUID(0))]))
        await store.receive(\.uploadResponse) {
            $0.jobs[id: UUID(0)]?.status = .failed(FilesClientError.sessionExpired.userMessage)
        }
        #expect(sessionDidExpire == true)
    }

    @Test
    func clearRemovesFinishedJobs() async {
        var state = UploadsFeature.State(serverURL: serverURL)
        state.jobs = [
            job("a.txt", id: UUID(0), status: .completed),
            job("b.txt", id: UUID(1), status: .failed("nope")),
        ]
        let store = TestStore(initialState: state) { UploadsFeature() }
        store.exhaustivity = .off

        await store.send(.clearFinishedTapped) {
            $0.jobs.removeAll()
            $0.isSheetPresented = false
        }
    }

    @Test
    func overallProgressCountsFinishedFilesAndTheOneInFlight() {
        var state = UploadsFeature.State(serverURL: URL(string: "https://example.com")!)
        #expect(state.overallProgress == nil)

        var inFlight = job("b.txt", id: UUID(), status: .uploading)
        inFlight.progress = 0.5
        state.jobs = [
            job("a.txt", id: UUID(), status: .completed),
            inFlight,
            job("c.txt", id: UUID(), status: .queued),
            job("d.txt", id: UUID(), status: .queued),
        ]

        #expect(state.overallProgress == 1.5 / 4)
        #expect(state.remainingCount == 3)
    }
}
