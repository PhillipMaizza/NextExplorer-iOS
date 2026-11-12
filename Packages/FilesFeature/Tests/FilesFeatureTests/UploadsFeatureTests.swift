import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import TestUtils
import Testing

@Suite(.isolatedDependencies)
@MainActor
struct UploadsFeatureTests {
    private typealias Store = TestStoreOf<UploadsFeature>
    private typealias State = UploadsFeature.State
    typealias Job = UploadsFeature.UploadJob

    struct UploadCall: Equatable, Sendable {
        let fileURL: URL
        let fileName: String
        let destination: String
    }

    private let serverURL = SettingsTestSupport.serverURL
    private let now = MockDate.date
    private let uploadCalls = LockIsolated<[UploadCall]>([])
    private let discarded = LockIsolated<[URL]>([])
    private let sweeps = LockIsolated(0)

    private nonisolated func pending(_ name: String, _ id: Int, destination: String = "Inbox") -> PendingUpload {
        PendingUpload(id: UUID(id), fileURL: URL(fileURLWithPath: "/staging/\(name)"), fileName: name, destination: destination)
    }

    private nonisolated func fileURL(_ name: String) -> URL {
        URL(fileURLWithPath: "/staging/\(name)")
    }

    private nonisolated func uploaded(_ name: String, destination: String = "Inbox") -> FileItem {
        FileItem(name: name, path: destination, dateModified: MockDate.date, size: 10, kind: "txt")
    }

    private nonisolated func job(
        _ name: String, _ id: Int, _ status: Job.Status,
        destination: String = "Inbox", isTransportFailure: Bool = false, autoRetryCount: Int = 0, startedAt: Date? = nil
    ) -> Job {
        Job(
            id: UUID(id), fileURL: URL(fileURLWithPath: "/staging/\(name)"), fileName: name,
            destination: destination, progress: status == .completed ? 1 : 0, status: status,
            startedAt: startedAt, isTransportFailure: isTransportFailure, autoRetryCount: autoRetryCount
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

    private func state(_ jobs: [Job] = [], isSheetPresented: Bool = false) -> State {
        var state = State(serverURL: serverURL)
        state.jobs = IdentifiedArray(uniqueElements: jobs)
        state.isSheetPresented = isSheetPresented
        return state
    }

    private func makeStore(
        _ state: State,
        isSourcePresent: Bool = true,
        upload: @escaping @Sendable (UploadCall, @Sendable (Double) -> Void) async throws -> FileItem = { call, _ in
            FileItem(name: call.fileName, path: call.destination, dateModified: MockDate.date, size: 10, kind: "txt")
        }
    ) -> Store {
        let uploadCalls = uploadCalls
        let discarded = discarded
        let sweeps = sweeps
        let date = now
        return TestStore(initialState: state) {
            UploadsFeature()
        } withDependencies: {
            $0.date = .constant(date)
            $0.filesClient.uploadFile = { _, url, name, destination, progress in
                let call = UploadCall(fileURL: url, fileName: name, destination: destination)
                uploadCalls.withValue { $0.append(call) }
                return try await upload(call, progress)
            }
            $0.uploadStaging = UploadStagingClient(
                stageDocuments: { _ in AsyncStream<PickedFile> { $0.finish() } },
                stagePhotos: { _ in AsyncStream<PickedFile> { $0.finish() } },
                stageCameraCapture: { _ in nil },
                discard: { urls in discarded.withValue { $0.append(contentsOf: urls) } },
                sweepStale: { sweeps.withValue { $0 += 1 } },
                sourceExists: { _ in isSourcePresent }
            )
        }
    }

    private func markUploading(_ state: inout State, _ id: Int) {
        state.jobs[id: UUID(id)]?.status = .uploading
        state.jobs[id: UUID(id)]?.startedAt = now
    }

    private func markCompleted(_ state: inout State, _ id: Int) {
        state.jobs[id: UUID(id)]?.status = .completed
        state.jobs[id: UUID(id)]?.progress = 1
    }

    private func markFailed(_ state: inout State, _ id: Int, _ message: String, isTransportFailure: Bool = false) {
        state.jobs[id: UUID(id)]?.status = .failed(message)
        state.jobs[id: UUID(id)]?.isTransportFailure = isTransportFailure
    }

    // MARK: Enqueue and run

    @Test
    func filesUploadOneAtATimeAndTheQueueFinishes() async {
        let store = makeStore(state())

        await store.send(.enqueue([pending("a.txt", 0), pending("b.txt", 1)])) {
            $0.jobs = [self.job("a.txt", 0, .queued), self.job("b.txt", 1, .queued)]
        }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 0) }
        #expect(store.state.jobs[id: UUID(1)]?.status == .queued)

        await store.receive(\.uploadResponse) { markCompleted(&$0, 0) }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 1) }
        await store.receive(\.uploadResponse) { markCompleted(&$0, 1) }
        await store.receive(.delegate(.queueFinished(
            summary(uploaded: 2, failed: 0, lastDestination: "Inbox", changedPaths: ["Inbox"])
        )))
        await store.finish()

        #expect(!store.state.isActive)
        #expect(uploadCalls.value == [
            UploadCall(fileURL: fileURL("a.txt"), fileName: "a.txt", destination: "Inbox"),
            UploadCall(fileURL: fileURL("b.txt"), fileName: "b.txt", destination: "Inbox"),
        ])
        #expect(Set(discarded.value) == [fileURL("a.txt"), fileURL("b.txt")])
    }

    @Test
    func enqueueingNothingDoesNothing() async {
        let store = makeStore(state())

        await store.send(.enqueue([]))
        #expect(uploadCalls.value.isEmpty)
    }

    @Test
    func aFreshBatchDropsTheFinishedRowsOfThePreviousOne() async {
        let store = makeStore(state([self.job("old.txt", 0, .completed), self.job("bad.txt", 1, .failed("nope"))]))

        await store.send(.enqueue([pending("new.txt", 2)])) {
            $0.jobs = [self.job("new.txt", 2, .queued)]
        }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 2) }
        await store.receive(\.uploadResponse) { markCompleted(&$0, 2) }
        await store.receive(\.delegate)
        await store.finish()
    }

    @Test
    func enqueueingWhileBusyKeepsTheRunningJobAndAppendsTheNewOnes() async {
        let store = makeStore(state([self.job("a.txt", 0, .uploading, startedAt: MockDate.date)]), upload: { _, _ in
            try await suspendUntilCancelled()
            throw CancellationError()
        })

        await store.send(.enqueue([pending("b.txt", 1)])) {
            $0.jobs.append(self.job("b.txt", 1, .queued))
        }
        await store.receive(\.startNextIfIdle)
        #expect(uploadCalls.value.isEmpty)

        await store.send(.cancelAllTapped) { $0.jobs = [] }
        await store.finish()
    }

    @Test
    func progressIsThrottledToTwoPercentStepsAndAlwaysReportsCompletion() async {
        let store = makeStore(state([self.job("a.txt", 0, .queued)]), upload: { _, progress in
            progress(0.01)
            progress(0.5)
            progress(0.51)
            progress(1)
            return FileItem(name: "a.txt", path: "Inbox", dateModified: MockDate.date, size: 10, kind: "txt")
        })

        await store.send(.startNextIfIdle) { markUploading(&$0, 0) }
        await store.receive(.progress(id: UUID(0), 0.5)) { $0.jobs[id: UUID(0)]?.progress = 0.5 }
        await store.receive(.progress(id: UUID(0), 1)) { $0.jobs[id: UUID(0)]?.progress = 1 }
        await store.receive(\.uploadResponse) { markCompleted(&$0, 0) }
        await store.receive(\.delegate)
        await store.finish()
    }

    @Test
    func aResponseForAJobThatIsGoneIsIgnored() async {
        let store = makeStore(state([self.job("a.txt", 0, .completed)]))

        await store.send(.uploadResponse(id: UUID(7), .success(uploaded("ghost.txt"))))
        #expect(discarded.value.isEmpty)
    }

    // MARK: Failure and retry

    @Test
    func aFailedUploadReportsNoChangedPathsAndCanBeRetried() async {
        let attempts = LockIsolated(0)
        let store = makeStore(state(), upload: { call, _ in
            if attempts.withValue({ $0 += 1; return $0 }) == 1 { throw FilesClientError.server(statusCode: 500) }
            return FileItem(name: call.fileName, path: call.destination, dateModified: MockDate.date, size: 10, kind: "txt")
        })

        await store.send(.enqueue([pending("a.txt", 0)])) { $0.jobs = [self.job("a.txt", 0, .queued)] }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 0) }
        await store.receive(\.uploadResponse) { markFailed(&$0, 0, L10n.Uploads.failedGeneric) }
        await store.receive(.delegate(.queueFinished(summary(uploaded: 0, failed: 1, lastDestination: nil, changedPaths: []))))
        #expect(discarded.value.isEmpty)

        await store.send(.retryTapped(id: UUID(0))) { $0.jobs[id: UUID(0)]?.status = .queued }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 0) }
        await store.receive(\.uploadResponse) { markCompleted(&$0, 0) }
        await store.receive(.delegate(.queueFinished(summary(uploaded: 1, failed: 0, lastDestination: "Inbox", changedPaths: ["Inbox"]))))
        await store.finish()
        #expect(attempts.value == 2)
    }

    @Test
    func failuresKeepTheBarUpAndRetryAllRequeuesThem() async {
        let failedOnce = LockIsolated<Set<String>>([])
        let store = makeStore(state(), upload: { call, _ in
            if failedOnce.withValue({ $0.insert(call.fileName).inserted }) { throw FilesClientError.server(statusCode: 500) }
            return FileItem(name: call.fileName, path: call.destination, dateModified: MockDate.date, size: 10, kind: "txt")
        })

        await store.send(.enqueue([pending("a.txt", 0), pending("b.txt", 1)])) {
            $0.jobs = [self.job("a.txt", 0, .queued), self.job("b.txt", 1, .queued)]
        }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 0) }
        await store.receive(\.uploadResponse) { markFailed(&$0, 0, L10n.Uploads.failedGeneric) }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 1) }
        await store.receive(\.uploadResponse) { markFailed(&$0, 1, L10n.Uploads.failedGeneric) }
        await store.receive(.delegate(.queueFinished(summary(uploaded: 0, failed: 2, lastDestination: nil, changedPaths: []))))
        #expect(!store.state.isActive)
        #expect(store.state.failedCount == 2)
        #expect(store.state.isBarVisible)

        await store.send(.retryAllFailedTapped) {
            $0.jobs[id: UUID(0)]?.status = .queued
            $0.jobs[id: UUID(1)]?.status = .queued
        }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 0) }
        await store.receive(\.uploadResponse) { markCompleted(&$0, 0) }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 1) }
        await store.receive(\.uploadResponse) { markCompleted(&$0, 1) }
        await store.receive(.delegate(.queueFinished(summary(uploaded: 2, failed: 0, lastDestination: "Inbox", changedPaths: ["Inbox"]))))
        await store.finish()
        #expect(store.state.failedCount == 0)
        #expect(!store.state.isBarVisible)
    }

    @Test
    func retryingAJobThatDidNotFailDoesNothing() async {
        let store = makeStore(state([self.job("a.txt", 0, .completed), self.job("b.txt", 1, .queued)]))

        await store.send(.retryTapped(id: UUID(0)))
        await store.send(.retryTapped(id: UUID(1)))
        await store.send(.retryTapped(id: UUID(9)))
        await store.send(.retryAllFailedTapped)
        #expect(uploadCalls.value.isEmpty)
    }

    @Test
    func manualRetryResetsTheAutomaticRetryCounter() async {
        let store = makeStore(
            state([self.job("a.txt", 0, .failed("offline"), isTransportFailure: true, autoRetryCount: 3)]),
            upload: { _, _ in
                try await suspendUntilCancelled()
                throw CancellationError()
            }
        )

        await store.send(.retryTapped(id: UUID(0))) {
            $0.jobs[id: UUID(0)]?.status = .queued
            $0.jobs[id: UUID(0)]?.autoRetryCount = 0
        }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 0) }
        await store.send(.cancelAllTapped) { $0.jobs = [] }
        await store.finish()
    }

    // MARK: Batch summary

    @Test
    func batchFinishedReportsEveryDistinctDestinationThatSucceeded() async {
        let store = makeStore(state())

        await store.send(.enqueue([
            pending("a.txt", 0, destination: "Inbox"),
            pending("b.txt", 1, destination: "Inbox"),
            pending("c.txt", 2, destination: "Archive"),
        ])) {
            $0.jobs = [
                self.job("a.txt", 0, .queued, destination: "Inbox"),
                self.job("b.txt", 1, .queued, destination: "Inbox"),
                self.job("c.txt", 2, .queued, destination: "Archive"),
            ]
        }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 0) }
        await store.receive(\.uploadResponse) { markCompleted(&$0, 0) }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 1) }
        await store.receive(\.uploadResponse) { markCompleted(&$0, 1) }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 2) }
        await store.receive(\.uploadResponse) { markCompleted(&$0, 2) }
        await store.receive(.delegate(.queueFinished(
            summary(uploaded: 3, failed: 0, lastDestination: "Archive", changedPaths: ["Inbox", "Archive"])
        )))
        await store.finish()
    }

    // MARK: Failure messages

    struct FailureCase: Sendable {
        let error: FilesClientError
        let message: String
    }

    @Test(
        "A permanent failure keeps the server's words when it has them, never requeues on resume, and is not retried",
        arguments: [
            FailureCase(error: .server(statusCode: 413), message: L10n.Uploads.failedGeneric),
            FailureCase(error: .serverMessage(statusCode: 507, message: "Quota exceeded"), message: "Quota exceeded"),
            FailureCase(error: .forbidden(message: nil), message: L10n.Uploads.failedGeneric),
            FailureCase(error: .server(statusCode: 400), message: L10n.Uploads.failedGeneric),
            FailureCase(error: .decoding("source missing"), message: L10n.Uploads.failedGeneric),
            FailureCase(error: .sessionExpired, message: L10n.Error.sessionExpired),
            FailureCase(error: .rateLimited, message: L10n.Error.rateLimited),
            FailureCase(error: .timedOut, message: L10n.Uploads.failedGeneric),
        ]
    )
    func appResumedNeverRequeuesPermanentFailures(_ testCase: FailureCase) async {
        let error = testCase.error
        let store = makeStore(state(), upload: { _, _ in throw error })

        await store.send(.enqueue([pending("a.txt", 0)])) { $0.jobs = [self.job("a.txt", 0, .queued)] }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 0) }
        await store.receive(\.uploadResponse) { markFailed(&$0, 0, testCase.message) }
        await store.receive(.delegate(.queueFinished(summary(uploaded: 0, failed: 1, lastDestination: nil, changedPaths: []))))

        await store.send(.appResumed)
        await store.finish()
        #expect(uploadCalls.value.count == 1)
        #expect(sweeps.value == 1)
    }

    @Test
    func aSessionExpiredUploadTripsTheAppWideExpiryFlag() async {
        @Shared(.inMemory(SessionExpiry.sharedKey)) var sessionDidExpire = false
        $sessionDidExpire.withLock { $0 = false }
        let store = makeStore(state([self.job("a.txt", 0, .queued)]), upload: { _, _ in throw FilesClientError.sessionExpired })

        await store.send(.startNextIfIdle) { markUploading(&$0, 0) }
        await store.receive(\.uploadResponse) { markFailed(&$0, 0, L10n.Error.sessionExpired) }
        await store.receive(\.delegate)
        await store.finish()
        #expect(sessionDidExpire)
    }

    // MARK: Resuming

    @Test(arguments: [FilesClientError.offline, .network("lost")])
    func appResumedRequeuesTransportFailuresAndTheRetryCanSucceed(_ error: FilesClientError) async {
        let attempts = LockIsolated(0)
        let store = makeStore(state(), upload: { call, _ in
            if attempts.withValue({ $0 += 1; return $0 }) == 1 { throw error }
            return FileItem(name: call.fileName, path: call.destination, dateModified: MockDate.date, size: 10, kind: "txt")
        })

        await store.send(.enqueue([pending("a.txt", 0)])) { $0.jobs = [self.job("a.txt", 0, .queued)] }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 0) }
        await store.receive(\.uploadResponse) { markFailed(&$0, 0, L10n.Uploads.failedGeneric, isTransportFailure: true) }
        await store.receive(.delegate(.queueFinished(summary(uploaded: 0, failed: 1, lastDestination: nil, changedPaths: []))))

        await store.send(.appResumed) {
            $0.jobs[id: UUID(0)]?.status = .queued
            $0.jobs[id: UUID(0)]?.autoRetryCount = 1
        }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 0) }
        await store.receive(\.uploadResponse) { markCompleted(&$0, 0) }
        await store.receive(.delegate(.queueFinished(summary(uploaded: 1, failed: 0, lastDestination: "Inbox", changedPaths: ["Inbox"]))))
        await store.finish()
        #expect(attempts.value == 2)
        #expect(sweeps.value == 1)
    }

    @Test
    func appResumedRequeuesFailedJobsAndLeavesActiveUploadsAlone() async {
        let store = makeStore(state([
            self.job("a.txt", 0, .uploading),
            self.job("b.txt", 1, .failed("connection lost"), isTransportFailure: true),
            self.job("c.txt", 2, .completed),
            self.job("d.txt", 3, .queued),
        ]))

        await store.send(.appResumed) {
            $0.jobs[id: UUID(1)]?.status = .queued
            $0.jobs[id: UUID(1)]?.autoRetryCount = 1
        }
        await store.receive(\.startNextIfIdle)
        await store.finish()

        #expect(store.state.jobs[id: UUID(0)]?.status == .uploading)
        #expect(store.state.jobs[id: UUID(2)]?.status == .completed)
        #expect(store.state.jobs[id: UUID(3)]?.status == .queued)
        #expect(uploadCalls.value.isEmpty)
        #expect(sweeps.value == 1)
    }

    @Test
    func appResumedRestartsAnUploadThatWedgedWellPastAPlausibleTransferTime() async {
        let wedgedAt = now.addingTimeInterval(-600)
        let store = makeStore(
            state([self.job("a.txt", 0, .uploading, startedAt: wedgedAt), self.job("b.txt", 1, .queued)]),
            upload: { _, _ in
                try await suspendUntilCancelled()
                throw CancellationError()
            }
        )

        await store.send(.appResumed) {
            $0.jobs[id: UUID(0)]?.status = .queued
            $0.jobs[id: UUID(0)]?.autoRetryCount = 1
        }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 0) }
        await store.send(.cancelAllTapped) { $0.jobs = [] }
        await store.finish()
    }

    @Test
    func anUploadJustUnderTheWedgeAgeIsLeftAlone() async {
        let store = makeStore(state([self.job("a.txt", 0, .uploading, startedAt: now.addingTimeInterval(-299))]))

        await store.send(.appResumed)
        await store.finish()
        #expect(sweeps.value == 1)
    }

    @Test
    func appResumedDoesNotRequeueAJobWhoseSourceWasDeleted() async {
        let store = makeStore(
            state([self.job("gone.txt", 0, .failed("offline"), isTransportFailure: true)]),
            isSourcePresent: false
        )

        await store.send(.appResumed) { $0.jobs[id: UUID(0)]?.isTransportFailure = false }
        await store.finish()
        #expect(store.state.jobs[id: UUID(0)]?.status == .failed("offline"))
        #expect(uploadCalls.value.isEmpty)
    }

    @Test
    func aTimedOutUploadWaitsForAManualRetryBecauseTheServerMayHaveStoredIt() async {
        let attempts = LockIsolated(0)
        let store = makeStore(state(), upload: { call, _ in
            if attempts.withValue({ $0 += 1; return $0 }) == 1 { throw FilesClientError.timedOut }
            return FileItem(name: call.fileName, path: call.destination, dateModified: MockDate.date, size: 10, kind: "txt")
        })

        await store.send(.enqueue([pending("a.txt", 0)])) { $0.jobs = [self.job("a.txt", 0, .queued)] }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 0) }
        await store.receive(\.uploadResponse) { markFailed(&$0, 0, L10n.Uploads.failedGeneric) }
        await store.receive(\.delegate)

        await store.send(.appResumed)
        #expect(attempts.value == 1)

        await store.send(.retryTapped(id: UUID(0))) { $0.jobs[id: UUID(0)]?.status = .queued }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 0) }
        await store.receive(\.uploadResponse) { markCompleted(&$0, 0) }
        await store.receive(\.delegate)
        await store.finish()
        #expect(attempts.value == 2)
    }

    @Test
    func aWedgedUploadAtTheRetryCapFailsAndAnnouncesTheDrainedQueue() async {
        let store = makeStore(state([self.job("a.txt", 0, .uploading, autoRetryCount: 3, startedAt: now.addingTimeInterval(-600))]))

        await store.send(.appResumed) { markFailed(&$0, 0, L10n.Uploads.failedGeneric) }
        await store.receive(.delegate(.queueFinished(summary(uploaded: 0, failed: 1, lastDestination: nil, changedPaths: []))))
        await store.finish()
        #expect(store.state.jobs[id: UUID(0)]?.autoRetryCount == 3)
    }

    @Test
    func aFailedJobAtTheRetryCapKeepsItsRealError() async {
        let store = makeStore(state([
            self.job("a.txt", 0, .failed("Quota exceeded"), isTransportFailure: true, autoRetryCount: 3),
        ]))

        await store.send(.appResumed) { $0.jobs[id: UUID(0)]?.isTransportFailure = false }
        await store.finish()
        #expect(store.state.jobs[id: UUID(0)]?.status == .failed("Quota exceeded"))
    }

    // MARK: Cancelling

    @Test
    func cancellingTheActiveJobAdvancesToTheNext() async {
        let store = makeStore(state(), upload: { _, _ in
            try await suspendUntilCancelled()
            throw CancellationError()
        })

        await store.send(.enqueue([pending("a.txt", 0), pending("b.txt", 1)])) {
            $0.jobs = [self.job("a.txt", 0, .queued), self.job("b.txt", 1, .queued)]
        }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 0) }
        await store.send(.cancelJobTapped(id: UUID(0))) { $0.jobs[id: UUID(0)] = nil }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 1) }
        await store.send(.cancelAllTapped) { $0.jobs = [] }
        await store.finish()
        #expect(Set(discarded.value) == [fileURL("a.txt"), fileURL("b.txt")])
    }

    @Test
    func cancellingTheOnlyJobClosesTheSheet() async {
        let store = makeStore(state([self.job("a.txt", 0, .failed("nope"))], isSheetPresented: true))

        await store.send(.cancelJobTapped(id: UUID(0))) {
            $0.jobs = []
            $0.isSheetPresented = false
        }
        await store.receive(\.startNextIfIdle)
        await store.finish()
        #expect(discarded.value == [fileURL("a.txt")])
    }

    @Test
    func cancellingTheLastPendingJobAfterSomeFinishedStillReportsTheFinishedFiles() async {
        let store = makeStore(state([self.job("a.txt", 0, .completed), self.job("b.txt", 1, .uploading)]))

        await store.send(.cancelJobTapped(id: UUID(1))) { $0.jobs[id: UUID(1)] = nil }
        await store.receive(\.startNextIfIdle)
        await store.receive(.delegate(.queueFinished(
            summary(uploaded: 1, failed: 0, lastDestination: "Inbox", changedPaths: ["Inbox"])
        )))
        await store.finish()
        #expect(discarded.value == [fileURL("b.txt")])
    }

    @Test
    func cancellingAJobWhileOthersStillRunDoesNotAnnounceTheQueueFinished() async {
        let store = makeStore(
            state([self.job("a.txt", 0, .completed), self.job("b.txt", 1, .uploading), self.job("c.txt", 2, .queued)]),
            upload: { _, _ in
                try await suspendUntilCancelled()
                throw CancellationError()
            }
        )

        await store.send(.cancelJobTapped(id: UUID(1))) { $0.jobs[id: UUID(1)] = nil }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 2) }
        await store.send(.cancelAllTapped) { $0.jobs = [] }
        await store.receive(.delegate(.queueFinished(
            summary(uploaded: 1, failed: 0, lastDestination: "Inbox", changedPaths: ["Inbox"])
        )))
        await store.finish()
    }

    @Test
    func cancelAllWithFinishedFilesReportsThemToTheParent() async {
        let store = makeStore(state([
            self.job("a.txt", 0, .completed), self.job("b.txt", 1, .uploading), self.job("c.txt", 2, .queued),
        ], isSheetPresented: true))

        await store.send(.cancelAllTapped) {
            $0.jobs = []
            $0.isSheetPresented = false
        }
        await store.receive(.delegate(.queueFinished(
            summary(uploaded: 1, failed: 0, lastDestination: "Inbox", changedPaths: ["Inbox"])
        )))
        await store.finish()
        #expect(Set(discarded.value) == [fileURL("a.txt"), fileURL("b.txt"), fileURL("c.txt")])
    }

    @Test
    func cancelAllWithNothingFinishedStaysQuiet() async {
        let store = makeStore(state([self.job("d.txt", 0, .uploading)]))

        await store.send(.cancelAllTapped) { $0.jobs = [] }
        await store.finish()
        #expect(discarded.value == [fileURL("d.txt")])
    }

    @Test
    func cancelAllOnAQueueThatAlreadyAnnouncedItselfDoesNotAnnounceItAgain() async {
        let store = makeStore(state([self.job("a.txt", 0, .completed)]))

        await store.send(.cancelAllTapped) { $0.jobs = [] }
        await store.finish()
    }

    // MARK: Clearing and the sheet

    @Test
    func clearRemovesFinishedJobsDiscardsTheirFilesAndClosesAnEmptySheet() async {
        let store = makeStore(state([self.job("a.txt", 0, .completed), self.job("b.txt", 1, .failed("nope"))], isSheetPresented: true))

        await store.send(.clearFinishedTapped) {
            $0.jobs = []
            $0.isSheetPresented = false
        }
        await store.finish()
        #expect(Set(discarded.value) == [fileURL("a.txt"), fileURL("b.txt")])
    }

    @Test
    func clearKeepsJobsThatAreStillRunningAndTheSheetOpen() async {
        let running = job("b.txt", 1, .uploading)
        let store = makeStore(state([self.job("a.txt", 0, .completed), running], isSheetPresented: true))

        await store.send(.clearFinishedTapped) { $0.jobs = [running] }
        await store.finish()
        #expect(store.state.isSheetPresented)
        #expect(discarded.value == [fileURL("a.txt")])
    }

    @Test
    func theBarOpensTheSheetAndTheSheetFollowsItsBinding() async {
        let store = makeStore(state())

        await store.send(.barTapped) { $0.isSheetPresented = true }
        await store.send(.sheetPresented(false)) { $0.isSheetPresented = false }
        await store.send(.sheetPresented(true)) { $0.isSheetPresented = true }
    }

    // MARK: Derived values

    @Test
    func overallProgressCountsFinishedFilesAndTheOneInFlight() {
        var queue = state()
        #expect(queue.overallProgress == nil)

        var inFlight = job("b.txt", 1, .uploading)
        inFlight.progress = 0.5
        queue.jobs = [job("a.txt", 0, .completed), inFlight, job("c.txt", 2, .queued), job("d.txt", 3, .queued)]

        #expect(queue.overallProgress == 0.375)
        #expect(queue.remainingCount == 3)
        #expect(queue.completedCount == 1)
        #expect(queue.currentJob?.fileName == "b.txt")
        #expect(queue.hasClearableJobs)
    }

    struct BarCase: Sendable {
        let statuses: [Job.Status]
        let isActive: Bool
        let isBarVisible: Bool
    }

    @Test(
        "The bar stays up while uploads run and while failures wait",
        arguments: [
            BarCase(statuses: [], isActive: false, isBarVisible: false),
            BarCase(statuses: [.queued], isActive: true, isBarVisible: true),
            BarCase(statuses: [.uploading, .completed], isActive: true, isBarVisible: true),
            BarCase(statuses: [.completed], isActive: false, isBarVisible: false),
            BarCase(statuses: [.completed, .failed("x")], isActive: false, isBarVisible: true),
        ]
    )
    func barVisibility(_ testCase: BarCase) {
        let queue = state(testCase.statuses.enumerated().map { job("f\($0.offset)", $0.offset, $0.element) })

        #expect(queue.isActive == testCase.isActive)
        #expect(queue.isBarVisible == testCase.isBarVisible)
    }
}
