import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import NetworkClient
import Testing
import TestUtils

/// A file uploaded into a folder kept on the device is kept too: only the pinned folders that keep
/// the upload's destination are walked again.
@Suite(.isolatedDependencies)
@MainActor
struct OfflineDownloadsUploadLandedTests: OfflineDownloadsTestSupport {
    private enum Constants {
        static let kept = "A"
        static let keptSubfolder = "A/Sub"
        static let other = "B"
        static let notPinned = "C"
        static let uploaded = "new.txt"
        static let excludedSubfolder = "A/Skip"
    }

    private func recordingRun(
        offline: OfflineFileStore,
        listed: LockIsolated<[String]>,
        downloaded: LockIsolated<[String]>,
        configure: @escaping (inout DependencyValues) -> Void = { _ in }
    ) -> Run {
        makeRun(
            offline: offline,
            browse: { [self] path in
                listed.withValue { $0.append(path) }
                return listing([file(Constants.uploaded, path: path)], path: path)
            },
            download: { item in
                downloaded.withValue { $0.append(item.id) }
                return URL(fileURLWithPath: "/tmp/\(item.name)")
            },
            configure: configure
        )
    }

    @Test
    func anUploadIntoAKeptFolderDownloadsItAndWalksOnlyThatFolder() async {
        let offline = pinnedStore([Constants.kept, Constants.other])
        let listed = LockIsolated<[String]>([])
        let downloaded = LockIsolated<[String]>([])
        let run = recordingRun(offline: offline, listed: listed, downloaded: downloaded)

        await run.store.send(.uploadsLanded(destinations: [Constants.keptSubfolder])).finish()

        #expect(listed.value == ["A"])
        #expect(downloaded.value == ["A/new.txt"])
        #expect(run.phase == .completed)
        #expect(offline.lastAutoSyncAt() == nil)
    }

    @Test
    func anUploadOutsideEveryKeptFolderDoesNothing() async {
        let offline = pinnedStore([Constants.kept])
        let listed = LockIsolated<[String]>([])
        let downloaded = LockIsolated<[String]>([])
        let run = recordingRun(offline: offline, listed: listed, downloaded: downloaded)

        await run.store.send(.uploadsLanded(destinations: [Constants.notPinned])).finish()

        #expect(listed.value.isEmpty)
        #expect(run.phase == .idle)
    }

    @Test
    func anUploadIntoAFolderTakenOffTheDeviceIsNotKept() async {
        let offline = OfflineFileStore.inMemory()
        offline.setPinnedRoots([
            OfflinePinnedRoot(path: Constants.kept, isDirectory: true, excludedPaths: [Constants.excludedSubfolder]),
        ])
        let listed = LockIsolated<[String]>([])
        let downloaded = LockIsolated<[String]>([])
        let run = recordingRun(offline: offline, listed: listed, downloaded: downloaded)

        await run.store.send(.uploadsLanded(destinations: [Constants.excludedSubfolder])).finish()

        #expect(listed.value.isEmpty)
    }

    @Test
    func offlineTheUploadWaitsForTheNextSync() async {
        let offline = pinnedStore([Constants.kept])
        let listed = LockIsolated<[String]>([])
        let downloaded = LockIsolated<[String]>([])
        let run = recordingRun(offline: offline, listed: listed, downloaded: downloaded) {
            $0.connectivity = ConnectivityClient(isOnline: { false }, events: { AsyncStream { _ in } })
        }

        await run.store.send(.uploadsLanded(destinations: [Constants.kept])).finish()

        #expect(listed.value.isEmpty)
        #expect(run.phase == .idle)
    }
}
