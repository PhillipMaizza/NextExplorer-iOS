import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

/// Offline pin routing, plus what a drained Save to Device queue does on iPhone and iPad.
@Suite(.isolatedDependencies)
@MainActor
struct MainTabDeviceSaveTests: MainTabTestSupport {
    private enum Constants {
        static let stagedPath = "/staged/report.pdf"
    }

    private let folder = BrowseFixtures.folder(TestFolder.docs)

    @Test(
        "A pin requested from either screen starts the offline download",
        arguments: [
            Source(
                name: "from Browse",
                action: .browse(.delegate(.offlinePinRequested([BrowseFixtures.folder("Docs")])))
            ),
            Source(
                name: "from Favorites",
                action: .favorites(.delegate(.offlinePinRequested([BrowseFixtures.folder("Docs")])))
            ),
        ]
    )
    func aPinRequestStartsTheOfflineDownload(_ source: Source) async {
        let offline = OfflineFileStore.inMemory()
        let store = Store(initialState: makeState()) {
            MainTabFeature()
        } withDependencies: {
            $0.date = .constant(MockDate.date)
            $0.uuid = .incrementing
            $0.offlineFileStore = offline
            $0.filesClient.browse = { _, path in
                BrowseResult(items: [], access: BrowseTestSupport.fullAccess, path: path)
            }
        }

        await store.send(source.action).finish()
        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: TestFolder.docs, isDirectory: true)])
    }

    @Test(
        "An unpin requested from either screen removes the pin",
        arguments: [
            Source(name: "from Browse", action: .browse(.delegate(.offlineUnpinRequested(path: "Docs")))),
            Source(name: "from Favorites", action: .favorites(.delegate(.offlineUnpinRequested(path: "Docs")))),
        ]
    )
    func anUnpinRequestRemovesThePin(_ source: Source) async {
        let offline = OfflineFileStore.inMemory()
        offline.setPinnedRoots([OfflinePinnedRoot(path: TestFolder.docs, isDirectory: true)])
        let store = makeStore { $0.offlineFileStore = offline }

        await store.send(source.action)
        await store.receive(\.offline.unpinTapped)
        await store.receive(\.offline.unpinFinished)
        await store.receive(\.offlineManage.onAppear)
        await store.receive(\.offlineManage.usagesLoaded)
        await store.finish()
        #expect(offline.pinnedRoots().isEmpty)
    }

    @Test
    func openingTheOfflineTabReadsWhatIsPinned() async {
        let offline = OfflineFileStore.inMemory()
        offline.setPinnedRoots([OfflinePinnedRoot(path: TestFolder.docs, isDirectory: true)])
        let store = makeStore { $0.offlineFileStore = offline }

        await store.send(.tabSelected(.downloads)) { $0.selectedTab = .downloads }
        await store.receive(\.offlineManage.onAppear)
        await store.receive(\.offlineManage.usagesLoaded) {
            $0.offlineManage.usages = [
                OfflinePinnedRootUsage(
                    root: OfflinePinnedRoot(path: TestFolder.docs, isDirectory: true),
                    sizeBytes: 0
                ),
            ]
        }
    }

    @Test
    func theOfflinePillShowsWhileARunWorksAndAfterItFailsButNotOtherwise() {
        var state = makeState()
        #expect(!state.isOfflineBarVisible)

        for phase in [OfflineDownloadProgress.Phase.preparing, .downloading, .failed("x")] {
            state.$offlineProgress.withLock { $0.phase = phase }
            #expect(state.isOfflineBarVisible)
        }
        for phase in [OfflineDownloadProgress.Phase.idle, .completed, .waitingForNetwork] {
            state.$offlineProgress.withLock { $0.phase = phase }
            #expect(!state.isOfflineBarVisible)
        }
    }

    @Test
    func removingAPinFromTheOfflineTabRefreshesTheBadgesOnBothBrowseScreens() async {
        let store = makeStore()

        await store.send(.offlineManage(.delegate(.changed)))
        await store.receive(\.offline.pinnedRootsRemoved)
        await store.receive(\.browse.offlineAvailabilityChanged)
        await store.receive(\.favorites.offlineAvailabilityChanged)
        await store.receive(\.downloads.offlineAvailabilityChanged)
        await store.receive(\.browse.root.computeOfflineAvailability)
    }

    #if os(iOS)
        @Test
        func picturesSavedToPhotosGetTheirOwnConfirmation() async {
            let store = makeStore()
            var summary = DownloadQueueFeature.FinishSummary(savedCount: 2, failedCount: 0)
            summary.photosCount = 2

            await store.send(.downloadQueue(.delegate(.queueFinished(summary)))) {
                $0.downloadToast = L10n.DownloadQueue.savedToPhotos
            }
        }

        @Test
        func stagedFilesOpenTheSaveToFilesPanelAndWaitForItsAnswer() async {
            let staged = URL(fileURLWithPath: Constants.stagedPath)
            let store = makeStore()
            var summary = DownloadQueueFeature.FinishSummary(savedCount: 1, failedCount: 0)
            summary.exportURLs = [staged]

            await store.send(.downloadQueue(.delegate(.queueFinished(summary)))) {
                $0.pendingExportURLs = [staged]
            }
        }

        @Test
        func aFailureDoesNotHideTheFilesThatAreReadyToExport() async {
            let staged = URL(fileURLWithPath: Constants.stagedPath)
            let store = makeStore()
            var summary = DownloadQueueFeature.FinishSummary(savedCount: 1, failedCount: 1)
            summary.exportURLs = [staged]

            await store.send(.downloadQueue(.delegate(.queueFinished(summary)))) {
                $0.pendingExportURLs = [staged]
            }
        }

        @Test
        func aFailureAloneShowsNoToast() async {
            let store = makeStore()
            var summary = DownloadQueueFeature.FinishSummary(savedCount: 1, failedCount: 1)
            summary.photosCount = 1

            await store.send(.downloadQueue(.delegate(.queueFinished(summary))))
        }

        @Test
        func savingFromTheExportPanelConfirmsAndDropsTheStagedCopy() async {
            let staged = URL(fileURLWithPath: Constants.stagedPath)
            let discarded = LockIsolated<[URL]>([])
            let store = makeStore(makeState { $0.pendingExportURLs = [staged] }) {
                $0.deviceSaver.discard = { urls in discarded.withValue { $0 += urls } }
            }

            await store.send(.deviceExportFinished(didSave: true)) {
                $0.pendingExportURLs = []
                $0.downloadToast = L10n.DownloadQueue.savedToDevice
            }
            #expect(discarded.value == [staged])
        }

        @Test
        func cancellingTheExportPanelShowsNoToastAndDropsTheStagedCopy() async {
            let staged = URL(fileURLWithPath: Constants.stagedPath)
            let discarded = LockIsolated<[URL]>([])
            let store = makeStore(makeState { $0.pendingExportURLs = [staged] }) {
                $0.deviceSaver.discard = { urls in discarded.withValue { $0 += urls } }
            }

            await store.send(.deviceExportFinished(didSave: false)) {
                $0.pendingExportURLs = []
            }
            #expect(discarded.value == [staged])
        }
    #endif
}
