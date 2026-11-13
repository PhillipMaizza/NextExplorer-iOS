import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import NetworkClient
import Testing
import TestUtils

/// A sync that cannot fit on the device says so instead of filling the disk and failing file by file.
@Suite(.isolatedDependencies)
@MainActor
struct OfflineDownloadsSpaceTests: OfflineDownloadsTestSupport {
    private enum Constants {
        static let root = "A"
        static let fileSize: Int64 = 500
    }

    private func run(freeBytes: Int64, downloaded: LockIsolated<[String]>) -> Run {
        makeRun(
            offline: pinnedStore([Constants.root]),
            browse: { [self] path in
                listing([file(TestFile.aText, path: path, size: Constants.fileSize)], path: path)
            },
            download: { item in
                downloaded.withValue { $0.append(item.name) }
                return URL(fileURLWithPath: "/tmp/\(item.name)")
            },
            configure: {
                $0.deviceStorage = DeviceStorageClient(freeBytes: { freeBytes })
                $0.connectivity = ConnectivityClient(isOnline: { true }, events: { AsyncStream { _ in } })
            }
        )
    }

    @Test
    func aSyncThatDoesNotFitFailsBeforeDownloadingAnything() async {
        let downloaded = LockIsolated<[String]>([])
        let run = run(freeBytes: Constants.fileSize - 1, downloaded: downloaded)

        await run.store.send(.resyncTapped).finish()

        #expect(run.phase == .failed(L10n.Offline.selectionInsufficientSpace))
        #expect(downloaded.value.isEmpty)
    }

    @Test
    func aSyncThatFitsExactlyDownloads() async {
        let downloaded = LockIsolated<[String]>([])
        let run = run(freeBytes: Constants.fileSize, downloaded: downloaded)

        await run.store.send(.resyncTapped).finish()

        #expect(run.phase == .completed)
        #expect(downloaded.value == [TestFile.aText])
    }
}
