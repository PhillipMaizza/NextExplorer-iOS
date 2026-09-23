import ComposableArchitecture
import CoreModels
import DependenciesTestSupport
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import NetworkClient
import Testing

@MainActor
@Suite(.dependencies)
struct DownloadQueueFeatureTests {
    private let serverURL = URL(string: "https://example.com")!

    private nonisolated func file(_ name: String, size: Int64 = 10) -> FileItem {
        FileItem(name: name, path: "Files", dateModified: Date(timeIntervalSince1970: 1), size: size, kind: (name as NSString).pathExtension)
    }

    private nonisolated func folder(_ name: String) -> FileItem {
        FileItem(name: name, path: "Files", dateModified: Date(timeIntervalSince1970: 1), size: 0, kind: "directory")
    }

    private nonisolated func temporaryFile() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
        return url
    }

    @Test
    func itemsDownloadOneAtATimeIntoDownloadsAndTheQueueFinishes() async {
        let requested = LockIsolated<[String]>([])
        let saved = LockIsolated<[String]>([])
        let flushes = LockIsolated(0)
        let store = TestStore(initialState: DownloadQueueFeature.State(serverURL: serverURL)) {
            DownloadQueueFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.filesClient.flushDownloadConnections = { flushes.withValue { $0 += 1 } }
            $0.filesClient.downloadItem = { _, item, _ in
                requested.withValue { $0.append(item.id) }
                return temporaryFile()
            }
            $0.localDownloadStore.save = { source, name, location, _ in
                #expect(location == .documents)
                saved.withValue { $0.append(name) }
                return source
            }
        }
        store.exhaustivity = .off

        await store.send(.enqueue([file("movie.mkv"), folder("Photos")]))
        await store.receive(\.startNextIfIdle) {
            $0.jobs[id: UUID(0)]?.status = .downloading
        }
        #expect(store.state.jobs[id: UUID(1)]?.status == .queued)
        await store.receive(\.downloadResponse) {
            $0.jobs[id: UUID(0)]?.status = .completed
        }
        await store.receive(.delegate(.itemSaved))
        await store.receive(\.startNextIfIdle)
        await store.receive(\.downloadResponse)
        await store.receive(.delegate(.itemSaved))
        await store.receive(.delegate(.queueFinished(DownloadQueueFeature.FinishSummary(savedCount: 2, failedCount: 0))))

        #expect(requested.value == ["Files/movie.mkv", "Files/Photos"])
        #expect(saved.value == ["movie.mkv", "Photos.zip"])
        #expect(flushes.value == 2)
        #expect(store.state.isActive == false)
        #expect(store.state.isBarVisible == false)
    }

    @Test
    func aFailedItemStaysOnTheFailedBarWhileTheRestFinish() async {
        let store = TestStore(initialState: DownloadQueueFeature.State(serverURL: serverURL)) {
            DownloadQueueFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.filesClient.flushDownloadConnections = {}
            $0.filesClient.downloadItem = { _, item, _ in
                if item.name == "broken.bin" {
                    throw FilesClientError.network("timed out")
                }
                return temporaryFile()
            }
            $0.localDownloadStore.save = { source, _, _, _ in source }
        }
        store.exhaustivity = .off

        await store.send(.enqueue([file("broken.bin"), file("ok.txt")]))
        await store.receive(.delegate(.queueFinished(DownloadQueueFeature.FinishSummary(savedCount: 1, failedCount: 1))))
        #expect(store.state.failedCount == 1)
        #expect(store.state.isBarVisible)
        #expect(store.state.jobs[id: UUID(0)]?.status == .failed(FilesClientError.network("timed out").userMessage))
    }

    @Test
    func retryRequeuesAFailedItem() async {
        let attempts = LockIsolated(0)
        let store = TestStore(initialState: DownloadQueueFeature.State(serverURL: serverURL)) {
            DownloadQueueFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.filesClient.flushDownloadConnections = {}
            $0.filesClient.downloadItem = { _, _, _ in
                let attempt = attempts.withValue { $0 += 1; return $0 }
                if attempt == 1 {
                    throw FilesClientError.offline
                }
                return temporaryFile()
            }
            $0.localDownloadStore.save = { source, _, _, _ in source }
        }
        store.exhaustivity = .off

        await store.send(.enqueue([file("movie.mkv")]))
        await store.receive(.delegate(.queueFinished(DownloadQueueFeature.FinishSummary(savedCount: 0, failedCount: 1))))

        await store.send(.retryAllFailedTapped) {
            $0.jobs[id: UUID(0)]?.status = .queued
        }
        await store.receive(.delegate(.queueFinished(DownloadQueueFeature.FinishSummary(savedCount: 1, failedCount: 0))))
        #expect(attempts.value == 2)
    }

    @Test
    func progressTracksBytesAndDerivesARateAndTimeLeft() async {
        let start = Date(timeIntervalSince1970: 1_000)
        let now = LockIsolated(start)
        var running = DownloadQueueFeature.DownloadJob(id: UUID(0), item: file("a.mkv"), status: .downloading)
        running.startedAt = start
        var state = DownloadQueueFeature.State(serverURL: serverURL)
        state.jobs = [running, DownloadQueueFeature.DownloadJob(id: UUID(1), item: file("b.mkv"), status: .queued)]
        let store = TestStore(initialState: state) {
            DownloadQueueFeature()
        } withDependencies: {
            $0.date = DateGenerator { now.value }
        }

        // Too early for a meaningful rate: bytes only.
        now.setValue(start.addingTimeInterval(0.5))
        await store.send(.progress(id: UUID(0), TransferProgress(receivedBytes: 10_000_000, expectedBytes: 100_000_000))) {
            $0.jobs[id: UUID(0)]?.receivedBytes = 10_000_000
            $0.jobs[id: UUID(0)]?.expectedBytes = 100_000_000
        }
        #expect(store.state.jobs[id: UUID(0)]?.progress == 0.1)
        #expect(store.state.jobs[id: UUID(0)]?.estimatedSecondsRemaining == nil)

        now.setValue(start.addingTimeInterval(4))
        await store.send(.progress(id: UUID(0), TransferProgress(receivedBytes: 40_000_000, expectedBytes: 100_000_000))) {
            $0.jobs[id: UUID(0)]?.receivedBytes = 40_000_000
            $0.jobs[id: UUID(0)]?.bytesPerSecond = 10_000_000
        }
        #expect(store.state.jobs[id: UUID(0)]?.estimatedSecondsRemaining == 6)

        // A job that isn't running ignores stray progress.
        await store.send(.progress(id: UUID(1), TransferProgress(receivedBytes: 5, expectedBytes: 10)))
    }

    @Test
    func aStreamedFolderZipReportsBytesWithoutATotal() {
        var job = DownloadQueueFeature.DownloadJob(id: UUID(0), item: folder("Photos"), status: .downloading)
        job.receivedBytes = 312_000_000
        job.bytesPerSecond = 1_000_000
        #expect(job.progress == nil)
        #expect(job.estimatedSecondsRemaining == nil)
        #expect(DownloadProgressText.detail(for: job, locale: Locale(identifier: "en_US")) == "312 MB")
    }

    @Test
    func progressTextShowsSizesAndTimeLeft() {
        var job = DownloadQueueFeature.DownloadJob(id: UUID(0), item: file("movie.mkv"), status: .downloading)
        job.receivedBytes = 400_000_000
        job.expectedBytes = 1_600_000_000
        job.bytesPerSecond = 10_000_000
        #expect(DownloadProgressText.detail(for: job, locale: Locale(identifier: "en_US")) == "400 MB of 1.6 GB · 2m left")
    }

    @Test
    func cancelAllStopsTheTransferAndClearsTheQueue() async {
        let started = AsyncStream<Void>.makeStream()
        let store = TestStore(initialState: DownloadQueueFeature.State(serverURL: serverURL)) {
            DownloadQueueFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.filesClient.flushDownloadConnections = {}
            $0.filesClient.downloadItem = { _, _, _ in
                started.continuation.yield()
                try await Task.never()
                return URL(fileURLWithPath: "/tmp/never")
            }
            $0.localDownloadStore.save = { _, _, _, _ in
                Issue.record("a cancelled download must never be saved")
                return URL(fileURLWithPath: "/tmp/x")
            }
        }
        store.exhaustivity = .off

        await store.send(.enqueue([file("movie.mkv"), file("other.mkv")]))
        await store.receive(\.startNextIfIdle)
        var iterator = started.stream.makeAsyncIterator()
        await iterator.next()

        await store.send(.cancelAllTapped) {
            $0.jobs = []
            $0.isSheetPresented = false
        }
        await store.finish()
        #expect(store.state.isBarVisible == false)
    }

    @Test
    func aFolderIsSavedAsAZipNamedAfterIt() {
        let job = DownloadQueueFeature.DownloadJob(id: UUID(0), item: folder("Holiday 2026"), status: .queued)
        #expect(job.fileName == "Holiday 2026.zip")
        let fileJob = DownloadQueueFeature.DownloadJob(id: UUID(1), item: file("clip.mp4"), status: .queued)
        #expect(fileJob.fileName == "clip.mp4")
    }
}
