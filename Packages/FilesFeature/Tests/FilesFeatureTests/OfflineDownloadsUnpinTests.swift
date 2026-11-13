import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import NetworkClient
import Testing
import TestUtils

/// Unpinning while a run is going: the run stops, the root goes, and what is still pinned syncs again.
@Suite(.isolatedDependencies)
@MainActor
struct OfflineDownloadsUnpinTests: OfflineDownloadsTestSupport {
    private enum Constants {
        static let rootA = "A"
        static let rootB = "B"
    }

    private nonisolated let online = ConnectivityClient(isOnline: { true }, events: { AsyncStream { _ in } })

    @Test
    func unpinningWhileARunIsActiveStopsItDropsTheRootAndSyncsTheRest() async {
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let gate = AsyncGate()
        let calls = LockIsolated(0)
        let wasCancelled = LockIsolated(false)
        let listedAfterCancel = LockIsolated<[String]>([])
        let offline = pinnedStore([Constants.rootA, Constants.rootB])
        let run = makeRun(
            offline: offline,
            browse: { _ in throw FilesClientError.offline },
            configure: { [self] in
                $0.connectivity = online
                $0.filesClient.browse = { [self] _, path in
                    let call = calls.withValue { value -> Int in
                        value += 1
                        return value
                    }
                    if call == 1 {
                        startedContinuation.yield()
                        do {
                            try await gate.wait()
                        } catch {
                            wasCancelled.setValue(true)
                            throw error
                        }
                    }
                    if wasCancelled.value {
                        listedAfterCancel.withValue { $0.append(path) }
                    }
                    return listing([], path: path)
                }
            }
        )

        let task = run.store.send(.resyncTapped)
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        await run.store.send(.unpinTapped(path: Constants.rootA)).finish()
        await task.finish()

        #expect(wasCancelled.value)
        #expect(offline.pinnedRoots().map(\.path) == [Constants.rootB])
        #expect(listedAfterCancel.value == [Constants.rootB], "only the root still pinned syncs again")
        #expect(run.phase == .idle, "nothing new to fetch, so the sync ends without a status")
    }

    @Test
    func unpinningWhenNothingRunsDoesNotStartASync() async {
        let calls = LockIsolated(0)
        let offline = pinnedStore([Constants.rootA, Constants.rootB])
        let run = makeRun(
            offline: offline,
            browse: { path in
                calls.withValue { $0 += 1 }
                return BrowseResult(
                    items: [],
                    access: FileAccess(
                        canRead: true,
                        canWrite: true,
                        canUpload: true,
                        canDelete: true,
                        canShare: false,
                        canDownload: true
                    ),
                    path: path
                )
            },
            configure: { [self] in $0.connectivity = online }
        )

        await run.store.send(.unpinTapped(path: Constants.rootA)).finish()

        #expect(calls.value == 0)
        #expect(offline.pinnedRoots().map(\.path) == [Constants.rootB])
        #expect(run.phase == .idle)
    }

    @Test
    func aSyncWithNothingPinnedStillDropsLeftoverCopies() async {
        let reconciles = LockIsolated<[Set<String>?]>([])
        var offline = OfflineFileStore.inMemory()
        offline.reconcile = { paths in reconciles.withValue { $0.append(paths) } }
        let run = makeRun(
            offline: offline,
            browse: { _ in throw FilesClientError.offline },
            configure: { [self] in $0.connectivity = online }
        )

        await run.store.send(.autoSync(force: true)).finish()

        #expect(reconciles.value == [nil])
    }
}
