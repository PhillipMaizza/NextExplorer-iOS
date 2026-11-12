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
struct UploadsCancelAndClearTests: UploadsTestSupport {
    typealias Job = UploadsFeature.UploadJob

    let uploadCalls = LockIsolated<[UploadCall]>([])
    let discarded = LockIsolated<[URL]>([])
    let sweeps = LockIsolated(0)

    @Test
    func cancellingTheActiveJobAdvancesToTheNext() async {
        let store = makeStore(state(), upload: { _, _ in
            try await suspendUntilCancelled()
            throw CancellationError()
        })

        await store.send(.enqueue([pending(TestFile.aText, 0), pending(TestFile.bText, 1)])) {
            $0.jobs = [self.job(TestFile.aText, 0, .queued), self.job(TestFile.bText, 1, .queued)]
        }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 0) }
        await store.send(.cancelJobTapped(id: UUID(0))) { $0.jobs[id: UUID(0)] = nil }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 1) }
        await store.send(.cancelAllTapped) { $0.jobs = [] }
        await store.finish()
        #expect(Set(discarded.value) == [fileURL(TestFile.aText), fileURL(TestFile.bText)])
    }

    @Test
    func cancellingTheOnlyJobClosesTheSheet() async {
        let store = makeStore(state([self.job(TestFile.aText, 0, .failed(TestAccount.rejectedPassword))], isSheetPresented: true))

        await store.send(.cancelJobTapped(id: UUID(0))) {
            $0.jobs = []
            $0.isSheetPresented = false
        }
        await store.receive(\.startNextIfIdle)
        await store.finish()
        #expect(discarded.value == [fileURL(TestFile.aText)])
    }

    @Test
    func cancellingTheLastPendingJobAfterSomeFinishedStillReportsTheFinishedFiles() async {
        let store = makeStore(state([self.job(TestFile.aText, 0, .completed), self.job(TestFile.bText, 1, .uploading)]))

        await store.send(.cancelJobTapped(id: UUID(1))) { $0.jobs[id: UUID(1)] = nil }
        await store.receive(\.startNextIfIdle)
        await store.receive(.delegate(.queueFinished(
            summary(uploaded: 1, failed: 0, lastDestination: TestFolder.inbox, changedPaths: [TestFolder.inbox])
        )))
        await store.finish()
        #expect(discarded.value == [fileURL(TestFile.bText)])
    }

    @Test
    func cancellingAJobWhileOthersStillRunDoesNotAnnounceTheQueueFinished() async {
        let store = makeStore(
            state([self.job(TestFile.aText, 0, .completed), self.job(TestFile.bText, 1, .uploading), self.job("c.txt", 2, .queued)]),
            upload: { _, _ in
                try await suspendUntilCancelled()
                throw CancellationError()
            }
        )

        await store.send(.cancelJobTapped(id: UUID(1))) { $0.jobs[id: UUID(1)] = nil }
        await store.receive(\.startNextIfIdle) { markUploading(&$0, 2) }
        await store.send(.cancelAllTapped) { $0.jobs = [] }
        await store.receive(.delegate(.queueFinished(
            summary(uploaded: 1, failed: 0, lastDestination: TestFolder.inbox, changedPaths: [TestFolder.inbox])
        )))
        await store.finish()
    }

    @Test
    func cancelAllWithFinishedFilesReportsThemToTheParent() async {
        let store = makeStore(state([
            self.job(TestFile.aText, 0, .completed), self.job(TestFile.bText, 1, .uploading), self.job("c.txt", 2, .queued),
        ], isSheetPresented: true))

        await store.send(.cancelAllTapped) {
            $0.jobs = []
            $0.isSheetPresented = false
        }
        await store.receive(.delegate(.queueFinished(
            summary(uploaded: 1, failed: 0, lastDestination: TestFolder.inbox, changedPaths: [TestFolder.inbox])
        )))
        await store.finish()
        #expect(Set(discarded.value) == [fileURL(TestFile.aText), fileURL(TestFile.bText), fileURL("c.txt")])
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
        let store = makeStore(state([self.job(TestFile.aText, 0, .completed)]))

        await store.send(.cancelAllTapped) { $0.jobs = [] }
        await store.finish()
    }

    @Test
    func clearRemovesFinishedJobsDiscardsTheirFilesAndClosesAnEmptySheet() async {
        let store = makeStore(state([self.job(TestFile.aText, 0, .completed), self.job(TestFile.bText, 1, .failed(TestAccount.rejectedPassword))], isSheetPresented: true))

        await store.send(.clearFinishedTapped) {
            $0.jobs = []
            $0.isSheetPresented = false
        }
        await store.finish()
        #expect(Set(discarded.value) == [fileURL(TestFile.aText), fileURL(TestFile.bText)])
    }

    @Test
    func clearKeepsJobsThatAreStillRunningAndTheSheetOpen() async {
        let running = job(TestFile.bText, 1, .uploading)
        let store = makeStore(state([self.job(TestFile.aText, 0, .completed), running], isSheetPresented: true))

        await store.send(.clearFinishedTapped) { $0.jobs = [running] }
        await store.finish()
        #expect(store.state.isSheetPresented)
        #expect(discarded.value == [fileURL(TestFile.aText)])
    }

    @Test
    func theBarOpensTheSheetAndTheSheetFollowsItsBinding() async {
        let store = makeStore(state())

        await store.send(.barTapped) { $0.isSheetPresented = true }
        await store.send(.sheetPresented(false)) { $0.isSheetPresented = false }
        await store.send(.sheetPresented(true)) { $0.isSheetPresented = true }
    }
}
