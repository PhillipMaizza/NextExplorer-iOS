import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct UploadsFailureAndResumeTests: UploadsTestSupport {
    typealias Job = UploadsFeature.UploadJob

    let uploadCalls = LockIsolated<[UploadCall]>([])
    let discarded = LockIsolated<[URL]>([])
    let sweeps = LockIsolated(0)

    @Test
    func aFailedUploadReportsNoChangedPathsAndCanBeRetried() async {
        let attempts = LockIsolated(0)
        let store = makeStore(state(), upload: { call, _ in
            if attempts.withValue({ $0 += 1; return $0 }) == 1 {
                throw FilesClientError.server(statusCode: 500)
            }
            return FileItem(
                name: call.fileName,
                path: call.destination,
                dateModified: MockDate.date,
                size: 10,
                kind: TestKind.text
            )
        })

        await store.send(.enqueue([pending(TestFile.aText, 0)])) { $0.jobs = [job(TestFile.aText, 0, .queued)] }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 0) }
        await store.receive(\.uploadResponse) { markFailed(&$0, 0, L10n.Uploads.failedGeneric) }
        await store.receive(.delegate(.queueFinished(summary(
            uploaded: 0,
            failed: 1,
            lastDestination: nil,
            changedPaths: []
        ))))
        #expect(discarded.value.isEmpty)

        await store.send(.retryTapped(id: UUID(0))) { $0.jobs[id: UUID(0)]?.status = .queued }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 0) }
        await store.receive(\.uploadResponse) { markCompleted(&$0, 0) }
        await store.receive(.delegate(.queueFinished(summary(
            uploaded: 1,
            failed: 0,
            lastDestination: TestFolder.inbox,
            changedPaths: [TestFolder.inbox]
        ))))
        await store.finish()
        #expect(attempts.value == 2)
    }

    @Test
    func failuresKeepTheBarUpAndRetryAllRequeuesThem() async {
        let failedOnce = LockIsolated<Set<String>>([])
        let store = makeStore(state(), upload: { call, _ in
            if failedOnce.withValue({ $0.insert(call.fileName).inserted }) {
                throw FilesClientError.server(statusCode: 500)
            }
            return FileItem(
                name: call.fileName,
                path: call.destination,
                dateModified: MockDate.date,
                size: 10,
                kind: TestKind.text
            )
        })

        await store.send(.enqueue([pending(TestFile.aText, 0), pending(TestFile.bText, 1)])) {
            $0.jobs = [job(TestFile.aText, 0, .queued), job(TestFile.bText, 1, .queued)]
        }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 0) }
        await store.receive(\.uploadResponse) { markFailed(&$0, 0, L10n.Uploads.failedGeneric) }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 1) }
        await store.receive(\.uploadResponse) { markFailed(&$0, 1, L10n.Uploads.failedGeneric) }
        await store.receive(.delegate(.queueFinished(summary(
            uploaded: 0,
            failed: 2,
            lastDestination: nil,
            changedPaths: []
        ))))
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
        await store.receive(.delegate(.queueFinished(summary(
            uploaded: 2,
            failed: 0,
            lastDestination: TestFolder.inbox,
            changedPaths: [TestFolder.inbox]
        ))))
        await store.finish()
        #expect(store.state.failedCount == 0)
        #expect(!store.state.isBarVisible)
    }

    @Test
    func retryingAJobThatDidNotFailDoesNothing() async {
        let store = makeStore(state([job(TestFile.aText, 0, .completed), job(TestFile.bText, 1, .queued)]))

        await store.send(.retryTapped(id: UUID(0)))
        await store.send(.retryTapped(id: UUID(1)))
        await store.send(.retryTapped(id: UUID(9)))
        await store.send(.retryAllFailedTapped)
        #expect(uploadCalls.value.isEmpty)
    }

    @Test
    func manualRetryResetsTheAutomaticRetryCounter() async {
        let store = makeStore(
            state([job(TestFile.aText, 0, .failed(TestFailure.offline), isTransportFailure: true, autoRetryCount: 3)]),
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

        await store.send(.enqueue([pending(TestFile.aText, 0)])) { $0.jobs = [job(TestFile.aText, 0, .queued)] }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 0) }
        await store.receive(\.uploadResponse) { markFailed(&$0, 0, testCase.message) }
        await store.receive(.delegate(.queueFinished(summary(
            uploaded: 0,
            failed: 1,
            lastDestination: nil,
            changedPaths: []
        ))))

        await store.send(.appResumed)
        await store.finish()
        #expect(uploadCalls.value.count == 1)
        #expect(sweeps.value == 1)
    }

    @Test
    func aSessionExpiredUploadTripsTheAppWideExpiryFlag() async {
        @Shared(.inMemory(SessionExpiry.sharedKey)) var sessionDidExpire = false
        $sessionDidExpire.withLock { $0 = false }
        let store = makeStore(
            state([job(TestFile.aText, 0, .queued)]),
            upload: { _, _ in throw FilesClientError.sessionExpired }
        )

        await store.send(.startNextIfIdle) { markUploading(&$0, 0) }
        await store.receive(\.uploadResponse) { markFailed(&$0, 0, L10n.Error.sessionExpired) }
        await store.receive(\.delegate)
        await store.finish()
        #expect(sessionDidExpire)
    }

    @Test(arguments: [FilesClientError.offline, .network("lost")])
    func appResumedRequeuesTransportFailuresAndTheRetryCanSucceed(_ error: FilesClientError) async {
        let attempts = LockIsolated(0)
        let store = makeStore(state(), upload: { call, _ in
            if attempts.withValue({ $0 += 1; return $0 }) == 1 {
                throw error
            }
            return FileItem(
                name: call.fileName,
                path: call.destination,
                dateModified: MockDate.date,
                size: 10,
                kind: TestKind.text
            )
        })

        await store.send(.enqueue([pending(TestFile.aText, 0)])) { $0.jobs = [job(TestFile.aText, 0, .queued)] }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 0) }
        await store
            .receive(\.uploadResponse) { markFailed(&$0, 0, L10n.Uploads.failedGeneric, isTransportFailure: true) }
        await store.receive(.delegate(.queueFinished(summary(
            uploaded: 0,
            failed: 1,
            lastDestination: nil,
            changedPaths: []
        ))))

        await store.send(.appResumed) {
            $0.jobs[id: UUID(0)]?.status = .queued
            $0.jobs[id: UUID(0)]?.autoRetryCount = 1
        }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 0) }
        await store.receive(\.uploadResponse) { markCompleted(&$0, 0) }
        await store.receive(.delegate(.queueFinished(summary(
            uploaded: 1,
            failed: 0,
            lastDestination: TestFolder.inbox,
            changedPaths: [TestFolder.inbox]
        ))))
        await store.finish()
        #expect(attempts.value == 2)
        #expect(sweeps.value == 1)
    }

    @Test
    func appResumedRequeuesFailedJobsAndLeavesActiveUploadsAlone() async {
        let store = makeStore(state([
            job(TestFile.aText, 0, .uploading),
            job(TestFile.bText, 1, .failed("connection lost"), isTransportFailure: true),
            job("c.txt", 2, .completed),
            job("d.txt", 3, .queued),
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
            state([job(TestFile.aText, 0, .uploading, startedAt: wedgedAt), job(TestFile.bText, 1, .queued)]),
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
        let store = makeStore(state([job(TestFile.aText, 0, .uploading, startedAt: now.addingTimeInterval(-299))]))

        await store.send(.appResumed)
        await store.finish()
        #expect(sweeps.value == 1)
    }

    @Test
    func appResumedDoesNotRequeueAJobWhoseSourceWasDeleted() async {
        let store = makeStore(
            state([job("gone.txt", 0, .failed(TestFailure.offline), isTransportFailure: true)]),
            isSourcePresent: false
        )

        await store.send(.appResumed) { $0.jobs[id: UUID(0)]?.isTransportFailure = false }
        await store.finish()
        #expect(store.state.jobs[id: UUID(0)]?.status == .failed(TestFailure.offline))
        #expect(uploadCalls.value.isEmpty)
    }

    @Test
    func aTimedOutUploadWaitsForAManualRetryBecauseTheServerMayHaveStoredIt() async {
        let attempts = LockIsolated(0)
        let store = makeStore(state(), upload: { call, _ in
            if attempts.withValue({ $0 += 1; return $0 }) == 1 {
                throw FilesClientError.timedOut
            }
            return FileItem(
                name: call.fileName,
                path: call.destination,
                dateModified: MockDate.date,
                size: 10,
                kind: TestKind.text
            )
        })

        await store.send(.enqueue([pending(TestFile.aText, 0)])) { $0.jobs = [job(TestFile.aText, 0, .queued)] }
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
        let store = makeStore(state([job(
            TestFile.aText,
            0,
            .uploading,
            autoRetryCount: 3,
            startedAt: now.addingTimeInterval(-600)
        )]))

        await store.send(.appResumed) { markFailed(&$0, 0, L10n.Uploads.failedGeneric) }
        await store.receive(.delegate(.queueFinished(summary(
            uploaded: 0,
            failed: 1,
            lastDestination: nil,
            changedPaths: []
        ))))
        await store.finish()
        #expect(store.state.jobs[id: UUID(0)]?.autoRetryCount == 3)
    }

    @Test
    func aFailedJobAtTheRetryCapKeepsItsRealError() async {
        let store = makeStore(state([
            job(TestFile.aText, 0, .failed("Quota exceeded"), isTransportFailure: true, autoRetryCount: 3),
        ]))

        await store.send(.appResumed) { $0.jobs[id: UUID(0)]?.isTransportFailure = false }
        await store.finish()
        #expect(store.state.jobs[id: UUID(0)]?.status == .failed("Quota exceeded"))
    }
}
