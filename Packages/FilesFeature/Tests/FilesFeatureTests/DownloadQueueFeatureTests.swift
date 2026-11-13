import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import NetworkClient
import Testing
import TestUtils

@MainActor
@Suite(.isolatedDependencies)
struct DownloadQueueFeatureTests {
    private let serverURL = URL(fileURLWithPath: "/")

    private nonisolated func file(_ name: String, size: Int64 = 10) -> FileItem {
        FileItem(
            name: name,
            path: TestFolder.files,
            dateModified: MockDate.date,
            size: size,
            kind: (name as NSString).pathExtension
        )
    }

    private nonisolated func folder(_ name: String) -> FileItem {
        FileItem(name: name, path: TestFolder.files, dateModified: MockDate.date, size: 0, kind: FileItem.directoryKind)
    }

    private typealias Job = DownloadQueueFeature.DownloadJob
    private typealias Summary = DownloadQueueFeature.FinishSummary

    /// What a drained queue reports for pictures and videos that finished: on a phone they went to Photos.
    private func finished(saved: Int, failed: Int) -> Summary {
        var summary = Summary(savedCount: saved, failedCount: failed)
        #if os(iOS)
            summary.photosCount = saved
        #endif
        return summary
    }

    private nonisolated func temporaryFile() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(TestID.name())
        FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
        return url
    }

    /// A store whose downloads answer from the closures given, with ids and the clock fixed.
    private func makeStore(
        _ state: DownloadQueueFeature.State? = nil,
        configure: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<DownloadQueueFeature> {
        TestStore(initialState: state ?? DownloadQueueFeature.State(serverURL: serverURL)) {
            DownloadQueueFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(MockDate.date)
            $0.filesClient.flushDownloadConnections = {}
            $0.localDownloadStore.save = { source, _, _ in source }
            $0.deviceSaver = DeviceSaver(
                saveToPhotos: { _, _ in },
                stage: { _, name in URL(fileURLWithPath: "/staged/\(name)") },
                discard: { _ in }
            )
            configure(&$0)
        }
    }

    /// Receives the start of the next queued job: it turns to downloading and records when it began.
    private func receiveStart(_ store: TestStoreOf<DownloadQueueFeature>, id: Int) async {
        await store.receive(\.startNextIfIdle) {
            $0.jobs[id: UUID(id)]?.status = .downloading
            $0.jobs[id: UUID(id)]?.startedAt = MockDate.date
        }
    }

    #if os(macOS)
        @Test
        func itemsDownloadOneAtATimeIntoDownloadsAndTheQueueFinishes() async {
            let requested = LockIsolated<[String]>([])
            let saved = LockIsolated<[String]>([])
            let flushes = LockIsolated(0)
            let store = makeStore {
                $0.filesClient.flushDownloadConnections = { flushes.withValue { $0 += 1 } }
                $0.filesClient.downloadItem = { _, item, _ in
                    requested.withValue { $0.append(item.id) }
                    return temporaryFile()
                }
                $0.localDownloadStore.save = { source, name, _ in
                    saved.withValue { $0.append(name) }
                    return source
                }
            }

            await store.send(.enqueue([file("movie.mkv"), folder(TestFolder.photos)])) {
                $0.jobs = [
                    Job(id: UUID(0), item: file("movie.mkv"), status: .queued),
                    Job(id: UUID(1), item: folder(TestFolder.photos), status: .queued),
                ]
            }
            await receiveStart(store, id: 0)
            await store.receive(\.downloadResponse) { $0.jobs[id: UUID(0)]?.status = .completed }
            await store.receive(.delegate(.itemSaved))
            await receiveStart(store, id: 1)
            await store.receive(\.downloadResponse) { $0.jobs[id: UUID(1)]?.status = .completed }
            await store.receive(.delegate(.itemSaved))
            await store.receive(.delegate(.queueFinished(Summary(savedCount: 2, failedCount: 0))))

            #expect(requested.value == ["Files/movie.mkv", "Files/Photos"])
            #expect(saved.value == ["movie.mkv", "Photos.zip"])
            #expect(flushes.value == 2)
            #expect(store.state.isActive == false)
            #expect(store.state.isBarVisible == false)
        }
    #endif

    @Test
    func aFailedItemStaysOnTheFailedBarWhileTheRestFinish() async {
        let store = makeStore {
            $0.filesClient.downloadItem = { _, item, _ in
                if item.name == "broken.bin" {
                    throw FilesClientError.network("timed out")
                }
                return temporaryFile()
            }
        }
        let failure = FilesClientError.network("timed out").userMessage

        await store.send(.enqueue([file("broken.bin"), file("ok.jpg")])) {
            $0.jobs = [
                Job(id: UUID(0), item: file("broken.bin"), status: .queued),
                Job(id: UUID(1), item: file("ok.jpg"), status: .queued),
            ]
        }
        await receiveStart(store, id: 0)
        await store.receive(\.downloadResponse) { $0.jobs[id: UUID(0)]?.status = .failed(failure) }
        await receiveStart(store, id: 1)
        await store.receive(\.downloadResponse) { $0.jobs[id: UUID(1)]?.status = .completed }
        await store.receive(.delegate(.itemSaved))
        await store.receive(.delegate(.queueFinished(finished(saved: 1, failed: 1))))

        #expect(store.state.failedCount == 1)
        #expect(store.state.isBarVisible)
    }

    @Test
    func retryRequeuesAFailedItem() async {
        let attempts = LockIsolated(0)
        let store = makeStore {
            $0.filesClient.downloadItem = { _, _, _ in
                let attempt = attempts.withValue { $0 += 1; return $0 }
                if attempt == 1 {
                    throw FilesClientError.offline
                }
                return temporaryFile()
            }
        }
        let failure = FilesClientError.offline.userMessage

        await store.send(.enqueue([file("movie.mov")])) {
            $0.jobs = [Job(id: UUID(0), item: file("movie.mov"), status: .queued)]
        }
        await receiveStart(store, id: 0)
        await store.receive(\.downloadResponse) { $0.jobs[id: UUID(0)]?.status = .failed(failure) }
        await store.receive(.delegate(.queueFinished(finished(saved: 0, failed: 1))))

        await store.send(.retryAllFailedTapped) {
            $0.jobs[id: UUID(0)]?.status = .queued
            $0.jobs[id: UUID(0)]?.startedAt = nil
        }
        await receiveStart(store, id: 0)
        await store.receive(\.downloadResponse) { $0.jobs[id: UUID(0)]?.status = .completed }
        await store.receive(.delegate(.itemSaved))
        await store.receive(.delegate(.queueFinished(finished(saved: 1, failed: 0))))
        #expect(attempts.value == 2)
    }

    @Test
    func retryingASingleFailedItemRequeuesOnlyThatOne() async {
        var failed = Job(id: UUID(0), item: file("a.mkv"), status: .failed("boom"))
        failed.startedAt = MockDate.date
        var state = DownloadQueueFeature.State(serverURL: serverURL)
        state.jobs = [failed, Job(id: UUID(1), item: file("b.mkv"), status: .failed("boom"))]
        let store = makeStore(state) {
            $0.filesClient.downloadItem = { _, _, _ in
                try await suspendUntilCancelled()
                return URL(fileURLWithPath: "/tmp/never")
            }
        }

        await store.send(.retryTapped(id: UUID(0))) {
            $0.jobs[id: UUID(0)]?.status = .queued
            $0.jobs[id: UUID(0)]?.startedAt = nil
        }
        await receiveStart(store, id: 0)
        await store.send(.cancelJobTapped(id: UUID(0))) { $0.jobs.remove(id: UUID(0)) }
        await store.receive(\.startNextIfIdle)
        await store.finish()
        #expect(store.state.jobs[id: UUID(1)]?.status == .failed("boom"))
    }

    @Test
    func retryingAnItemThatDidNotFailDoesNothing() async {
        var state = DownloadQueueFeature.State(serverURL: serverURL)
        state.jobs = [Job(id: UUID(0), item: file("a.mkv"), status: .completed)]
        let store = makeStore(state)

        await store.send(.retryTapped(id: UUID(0)))
        await store.send(.retryAllFailedTapped)
    }

    @Test
    func progressTracksBytesAndDerivesARateAndTimeLeft() async {
        let start = MockDate.date
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
        await store.send(.progress(
            id: UUID(0),
            TransferProgress(receivedBytes: 10_000_000, expectedBytes: 100_000_000)
        )) {
            $0.jobs[id: UUID(0)]?.receivedBytes = 10_000_000
            $0.jobs[id: UUID(0)]?.expectedBytes = 100_000_000
        }
        #expect(store.state.jobs[id: UUID(0)]?.progress == 0.1)
        #expect(store.state.jobs[id: UUID(0)]?.estimatedSecondsRemaining == nil)

        now.setValue(start.addingTimeInterval(4))
        await store.send(.progress(
            id: UUID(0),
            TransferProgress(receivedBytes: 40_000_000, expectedBytes: 100_000_000)
        )) {
            $0.jobs[id: UUID(0)]?.receivedBytes = 40_000_000
            $0.jobs[id: UUID(0)]?.bytesPerSecond = 10_000_000
        }
        #expect(store.state.jobs[id: UUID(0)]?.estimatedSecondsRemaining == 6)

        // A job that isn't running ignores stray progress.
        await store.send(.progress(id: UUID(1), TransferProgress(receivedBytes: 5, expectedBytes: 10)))
    }

    @Test
    func aStreamedFolderZipReportsBytesWithoutATotal() {
        var job = DownloadQueueFeature.DownloadJob(id: UUID(0), item: folder(TestFolder.photos), status: .downloading)
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
        #expect(DownloadProgressText
            .detail(for: job, locale: Locale(identifier: "en_US")) == "400 MB of 1.6 GB · 2m left")
    }

    @Test
    func cancelAllStopsTheTransferAndClearsTheQueue() async {
        let started = AsyncStream<Void>.makeStream()
        let store = makeStore {
            $0.filesClient.downloadItem = { _, _, _ in
                started.continuation.yield()
                try await suspendUntilCancelled()
                return URL(fileURLWithPath: "/tmp/never")
            }
            $0.localDownloadStore.save = { _, _, _ in
                Issue.record("a cancelled download must never be saved")
                return URL(fileURLWithPath: "/tmp/x")
            }
        }

        await store.send(.enqueue([file("movie.mkv"), file("other.mkv")])) {
            $0.jobs = [
                Job(id: UUID(0), item: file("movie.mkv"), status: .queued),
                Job(id: UUID(1), item: file("other.mkv"), status: .queued),
            ]
        }
        await receiveStart(store, id: 0)
        var iterator = started.stream.makeAsyncIterator()
        await iterator.next()

        await store.send(.cancelAllTapped) { $0.jobs = [] }
        await store.finish()
        #expect(store.state.isBarVisible == false)
    }

    @Test
    func cancellingTheLastPendingDownloadAfterSomeSavedStillReportsTheSavedItems() async {
        var state = DownloadQueueFeature.State(serverURL: serverURL)
        state.jobs = [
            Job(id: UUID(0), item: file("a.mkv"), status: .completed),
            Job(id: UUID(1), item: file("b.mkv"), status: .downloading),
        ]
        let store = makeStore(state)

        await store.send(.cancelJobTapped(id: UUID(1))) { $0.jobs.remove(id: UUID(1)) }
        await store.receive(\.startNextIfIdle)
        await store.receive(.delegate(.queueFinished(Summary(savedCount: 1, failedCount: 0))))
    }

    @Test
    func cancellingADownloadWhileOthersAreStillQueuedDoesNotAnnounceTheQueueFinished() async {
        var state = DownloadQueueFeature.State(serverURL: serverURL)
        state.jobs = [
            Job(id: UUID(0), item: file("a.mkv"), status: .completed),
            Job(id: UUID(1), item: file("b.mkv"), status: .downloading),
            Job(id: UUID(2), item: file("c.mkv"), status: .queued),
        ]
        let store = makeStore(state) {
            $0.filesClient.downloadItem = { _, _, _ in
                try await suspendUntilCancelled()
                return URL(fileURLWithPath: "/tmp/never")
            }
        }

        await store.send(.cancelJobTapped(id: UUID(1))) { $0.jobs.remove(id: UUID(1)) }
        await receiveStart(store, id: 2)
        await store.send(.cancelAllTapped) { $0.jobs = [] }
        await store.receive(.delegate(.queueFinished(Summary(savedCount: 1, failedCount: 0))))
        await store.finish()
    }

    @Test
    func cancelAllAfterSomeSavedReportsThemButClearingAFinishedQueueDoesNot() async {
        var state = DownloadQueueFeature.State(serverURL: serverURL)
        state.jobs = [
            Job(id: UUID(0), item: file("a.mkv"), status: .completed),
            Job(id: UUID(1), item: file("b.mkv"), status: .downloading),
        ]
        let store = makeStore(state)
        await store.send(.cancelAllTapped) { $0.jobs = [] }
        await store.receive(.delegate(.queueFinished(Summary(savedCount: 1, failedCount: 0))))

        var finished = DownloadQueueFeature.State(serverURL: serverURL)
        finished.jobs = [Job(id: UUID(2), item: file("c.mkv"), status: .completed)]
        let finishedStore = makeStore(finished)
        await finishedStore.send(.cancelAllTapped) { $0.jobs = [] }
    }

    @Test
    func aFolderIsSavedAsAZipNamedAfterIt() {
        let job = DownloadQueueFeature.DownloadJob(id: UUID(0), item: folder("Holiday 2026"), status: .queued)
        #expect(job.fileName == "Holiday 2026.zip")
        let fileJob = DownloadQueueFeature.DownloadJob(id: UUID(1), item: file("clip.mp4"), status: .queued)
        #expect(fileJob.fileName == "clip.mp4")
    }
}
