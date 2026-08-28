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
        await store.receive(.delegate(.folderContentsChanged(path: "Inbox")))
        await store.receive(\.startNextIfIdle) {
            $0.jobs[id: b]?.status = .uploading
        }
        await store.receive(\.uploadResponse) {
            $0.jobs[id: b]?.status = .completed
            $0.jobs[id: b]?.progress = 1
        }
        await store.receive(.delegate(.folderContentsChanged(path: "Inbox")))
        await store.receive(.delegate(.queueFinished(
            UploadsFeature.FinishSummary(uploadedCount: 2, failedCount: 0, lastDestination: "Inbox")
        )))
        #expect(store.state.isActive == false)
    }

    @Test
    func aFailedUploadDoesNotRefreshTheFolderAndCanBeRetried() async {
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
            UploadsFeature.FinishSummary(uploadedCount: 0, failedCount: 1, lastDestination: nil)
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
            $0.filesClient.uploadFile = { _, _, name, _, _ in
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
    func appResumedRestartsStalledUploads() async {
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
            $0.filesClient.uploadFile = { _, _, name, _, _ in self.uploaded(name) }
        }
        store.exhaustivity = .off

        await store.send(.appResumed) {
            $0.jobs[id: UUID(0)]?.status = .queued
            $0.jobs[id: UUID(1)]?.status = .queued
        }
        // Completed stays, and the first now-queued job starts uploading.
        #expect(store.state.jobs[id: UUID(2)]?.status == .completed)
        await store.receive(\.startNextIfIdle) {
            $0.jobs[id: UUID(0)]?.status = .uploading
        }
    }

    @Test
    func clearRemovesFinishedJobs() async {
        var state = UploadsFeature.State(serverURL: serverURL)
        state.jobs = [
            job("a.txt", id: UUID(0), status: .completed),
            job("b.txt", id: UUID(1), status: .failed("nope")),
        ]
        let store = TestStore(initialState: state) { UploadsFeature() }

        await store.send(.clearCompletedTapped) {
            $0.jobs.removeAll()
            $0.isSheetPresented = false
        }
    }
}
