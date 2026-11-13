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
struct UploadsQueueTests: UploadsTestSupport {
    typealias Job = UploadsFeature.UploadJob

    let uploadCalls = LockIsolated<[UploadCall]>([])
    let discarded = LockIsolated<[URL]>([])
    let sweeps = LockIsolated(0)

    @Test
    func filesUploadOneAtATimeAndTheQueueFinishes() async {
        let store = makeStore(state())

        await store.send(.enqueue([pending(TestFile.aText, 0), pending(TestFile.bText, 1)])) {
            $0.jobs = [job(TestFile.aText, 0, .queued), job(TestFile.bText, 1, .queued)]
        }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 0) }
        #expect(store.state.jobs[id: UUID(1)]?.status == .queued)

        await store.receive(\.uploadResponse) { markCompleted(&$0, 0) }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 1) }
        await store.receive(\.uploadResponse) { markCompleted(&$0, 1) }
        await store.receive(.delegate(.queueFinished(
            summary(uploaded: 2, failed: 0, lastDestination: TestFolder.inbox, changedPaths: [TestFolder.inbox])
        )))
        await store.finish()

        #expect(!store.state.isActive)
        #expect(uploadCalls.value == [
            UploadCall(fileURL: fileURL(TestFile.aText), fileName: TestFile.aText, destination: TestFolder.inbox),
            UploadCall(fileURL: fileURL(TestFile.bText), fileName: TestFile.bText, destination: TestFolder.inbox),
        ])
        #expect(Set(discarded.value) == [fileURL(TestFile.aText), fileURL(TestFile.bText)])
    }

    @Test
    func enqueueingNothingDoesNothing() async {
        let store = makeStore(state())

        await store.send(.enqueue([]))
        #expect(uploadCalls.value.isEmpty)
    }

    @Test
    func aFreshBatchDropsTheFinishedRowsOfThePreviousOne() async {
        let store = makeStore(state([
            job("old.txt", 0, .completed),
            job("bad.txt", 1, .failed(TestAccount.rejectedPassword)),
        ]))

        await store.send(.enqueue([pending("new.txt", 2)])) {
            $0.jobs = [job("new.txt", 2, .queued)]
        }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 2) }
        await store.receive(\.uploadResponse) { markCompleted(&$0, 2) }
        await store.receive(\.delegate)
        await store.finish()
    }

    @Test
    func enqueueingWhileBusyKeepsTheRunningJobAndAppendsTheNewOnes() async {
        let store = makeStore(state([job(TestFile.aText, 0, .uploading, startedAt: MockDate.date)]), upload: { _, _ in
            try await suspendUntilCancelled()
            throw CancellationError()
        })

        await store.send(.enqueue([pending(TestFile.bText, 1)])) {
            $0.jobs.append(job(TestFile.bText, 1, .queued))
        }
        await store.receive(\.startNextIfIdle)
        #expect(uploadCalls.value.isEmpty)

        await store.send(.cancelAllTapped) { $0.jobs = [] }
        await store.finish()
    }

    @Test
    func progressIsThrottledToTwoPercentStepsAndAlwaysReportsCompletion() async {
        let store = makeStore(state([job(TestFile.aText, 0, .queued)]), upload: { _, progress in
            progress(0.01)
            progress(0.5)
            progress(0.51)
            progress(1)
            return FileItem(
                name: TestFile.aText,
                path: TestFolder.inbox,
                dateModified: MockDate.date,
                size: 10,
                kind: TestKind.text
            )
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
        let store = makeStore(state([job(TestFile.aText, 0, .completed)]))

        await store.send(.uploadResponse(id: UUID(7), .success(uploaded("ghost.txt"))))
        #expect(discarded.value.isEmpty)
    }

    @Test
    func batchFinishedReportsEveryDistinctDestinationThatSucceeded() async {
        let store = makeStore(state())

        await store.send(.enqueue([
            pending(TestFile.aText, 0, destination: TestFolder.inbox),
            pending(TestFile.bText, 1, destination: TestFolder.inbox),
            pending("c.txt", 2, destination: TestFolder.archive),
        ])) {
            $0.jobs = [
                job(TestFile.aText, 0, .queued, destination: TestFolder.inbox),
                job(TestFile.bText, 1, .queued, destination: TestFolder.inbox),
                job("c.txt", 2, .queued, destination: TestFolder.archive),
            ]
        }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 0) }
        await store.receive(\.uploadResponse) { markCompleted(&$0, 0) }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 1) }
        await store.receive(\.uploadResponse) { markCompleted(&$0, 1) }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 2) }
        await store.receive(\.uploadResponse) { markCompleted(&$0, 2) }
        await store.receive(.delegate(.queueFinished(
            summary(
                uploaded: 3,
                failed: 0,
                lastDestination: TestFolder.archive,
                changedPaths: [TestFolder.inbox, TestFolder.archive]
            )
        )))
        await store.finish()
    }

    @Test
    func overallProgressCountsFinishedFilesAndTheOneInFlight() {
        var queue = state()
        #expect(queue.overallProgress == nil)

        var inFlight = job(TestFile.bText, 1, .uploading)
        inFlight.progress = 0.5
        queue.jobs = [job(TestFile.aText, 0, .completed), inFlight, job("c.txt", 2, .queued), job("d.txt", 3, .queued)]

        #expect(queue.overallProgress == 0.375)
        #expect(queue.remainingCount == 3)
        #expect(queue.completedCount == 1)
        #expect(queue.currentJob?.fileName == TestFile.bText)
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
