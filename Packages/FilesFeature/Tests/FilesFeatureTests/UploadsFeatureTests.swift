import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Localization
import Testing

@testable import FilesFeature

@MainActor
@Suite
struct UploadsFeatureTests {
    private let serverURL = URL(string: "https://example.com")!

    private nonisolated func pending(_ name: String, id: UUID, destination: String = "Inbox") -> PendingUpload {
        PendingUpload(id: id, fileURL: URL(fileURLWithPath: "/tmp/\(name)"), fileName: name, destination: destination)
    }

    private nonisolated func uploaded(_ name: String, destination: String = "Inbox") -> FileItem {
        FileItem(name: name, path: destination, dateModified: Date(timeIntervalSince1970: 1), size: 10, kind: "txt")
    }

    private nonisolated func job(
        _ name: String, id: UUID, status: UploadsFeature.UploadJob.Status
    ) -> UploadsFeature.UploadJob {
        UploadsFeature.UploadJob(
            id: id, fileURL: URL(fileURLWithPath: "/tmp/\(name)"), fileName: name,
            destination: "Inbox", progress: status == .completed ? 1 : 0, status: status
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
            $0.filesClient.uploadFile = { _, _, name, _, _ in self.uploaded(name) }
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
            $0.filesClient.uploadFile = { _, _, name, _, _ in
                let n = attempts.withValue { value -> Int in value += 1; return value }
                if n == 1 { throw FilesClientError.server(statusCode: 500) }
                return self.uploaded(name)
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
            $0.filesClient.uploadFile = { _, _, name, _, _ in
                let n = attempts.withValue { value -> Int in value += 1; return value }
                if n <= 2 { throw FilesClientError.server(statusCode: 500) }
                return self.uploaded(name)
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
            $0.filesClient.uploadFile = { _, _, name, dest, _ in self.uploaded(name, destination: dest) }
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
            job("b.txt", id: UUID(1), status: .failed("connection lost")),
            job("c.txt", id: UUID(2), status: .completed),
            job("d.txt", id: UUID(3), status: .queued),
        ]
        let store = TestStore(initialState: state) {
            UploadsFeature()
        } withDependencies: {
            $0.filesClient.uploadFile = { _, _, _, _, _ in try await Task.never() }
        }
        store.exhaustivity = .off

        await store.send(.appResumed) {
            $0.jobs[id: UUID(1)]?.status = .queued
        }
        // The genuinely uploading job is untouched; the completed one stays; the failed one
        // is requeued but the active upload still holds the slot.
        #expect(store.state.jobs[id: UUID(0)]?.status == .uploading)
        #expect(store.state.jobs[id: UUID(2)]?.status == .completed)
        #expect(store.state.jobs[id: UUID(3)]?.status == .queued)
        await store.receive(\.startNextIfIdle)
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
}
