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
struct MainTabOfflineTabTests: MainTabTestSupport {
    @Test(
        "A download requested from either screen is queued app wide and fetched through the client",
        arguments: [
            Source(name: "from Browse", action: .browse(.delegate(.downloadRequested([MainTabOfflineTabTests.movie])))),
            Source(
                name: "from Favorites",
                action: .favorites(.delegate(.downloadRequested([MainTabOfflineTabTests.movie])))
            ),
        ]
    )
    func downloadRequestedEnqueuesIntoTheAppWideDownloadQueue(_ source: Source) async throws {
        let requested = LockIsolated<[String]>([])
        let started = AsyncGate()
        let store = makeStore {
            $0.filesClient.flushDownloadConnections = {}
            $0.filesClient.downloadItem = { _, item, _ in
                requested.withValue { $0.append(item.id) }
                started.open()
                try await suspendUntilCancelled()
                throw CancellationError()
            }
        }

        await store.send(source.action)
        await store.receive(\.downloadQueue.enqueue) {
            $0.downloadQueue.jobs = [DownloadQueueFeature.DownloadJob(id: UUID(0), item: Self.movie, status: .queued)]
        }
        await store.receive(\.downloadQueue.startNextIfIdle) {
            $0.downloadQueue.jobs[id: UUID(0)]?.status = .downloading
            $0.downloadQueue.jobs[id: UUID(0)]?.startedAt = MockDate.date
        }
        try await started.wait()
        await store.send(.downloadQueue(.cancelAllTapped)) {
            $0.downloadQueue.jobs = []
        }
        await store.finish()
        #expect(requested.value == ["Files/movie.mkv"])
    }

    private nonisolated static let movie = FileItem(
        name: "movie.mkv",
        path: TestFolder.files,
        dateModified: MockDate.date,
        size: 1,
        kind: "mkv"
    )

    #if os(macOS)
        @Test("A drained queue shows the saved toast and Open takes the user to Downloads")
        func downloadQueueFinishedShowsTheSavedToastAndOpenGoesToDownloads() async {
            let store = makeStore { $0.localDownloadStore.list = { _ in [] } }

            await store.send(.downloadQueue(.delegate(.queueFinished(.init(savedCount: 3, failedCount: 0))))) {
                $0.downloadToast = L10n.DownloadQueue.savedMany(3)
            }
            await store.send(.openDownloadsTab) {
                $0.downloadToast = nil
                $0.selectedTab = .downloads
            }
            await store.receive(\.downloads.refreshButtonTapped) {
                $0.downloads.phase = .loading
            }
            await store.receive(\.downloads.downloadsResponse.success) {
                $0.downloads.phase = .loaded
            }
        }

        @Test("A single saved file gets the singular toast")
        func aSingleSavedFileGetsTheSingularToast() async {
            let store = makeStore()

            await store.send(.downloadQueue(.delegate(.queueFinished(.init(savedCount: 1, failedCount: 0))))) {
                $0.downloadToast = L10n.DownloadQueue.savedOne
            }
            await store.send(.dismissDownloadToast) {
                $0.downloadToast = nil
            }
        }
    #endif

    @Test("A drained queue with a failure shows no toast, the failed bar owns it")
    func downloadQueueFinishedWithFailuresShowsNoToast() async {
        let store = makeStore()

        await store.send(.downloadQueue(.delegate(.queueFinished(.init(savedCount: 1, failedCount: 1)))))
    }

    @Test("A saved download refreshes the Downloads tab and the offline badges on both browse screens")
    func aSavedDownloadRefreshesTheDownloadsTabAndOfflineBadges() async {
        let store = makeStore { $0.localDownloadStore.list = { _ in [] } }

        await store.send(.downloadQueue(.delegate(.itemSaved)))
        await store.receive(\.downloads.refreshButtonTapped) {
            $0.downloads.phase = .loading
        }
        await store.receive(\.browse.offlineAvailabilityChanged)
        await store.receive(\.favorites.offlineAvailabilityChanged)
        await store.receive(\.downloads.offlineAvailabilityChanged)
        await store.receive(\.browse.root.computeOfflineAvailability)
        await store.receive(\.downloads.downloadsResponse.success) {
            $0.downloads.phase = .loaded
        }
    }
}
