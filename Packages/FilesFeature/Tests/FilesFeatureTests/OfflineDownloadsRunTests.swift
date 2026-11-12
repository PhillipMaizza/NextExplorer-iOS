import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import NetworkClient
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct OfflineDownloadsRunTests: OfflineDownloadsTestSupport {
    @Test
    func theRunActionsAdvanceTheSharedProgressAndALateSnapshotNeverLowersIt() async {
        let store = makeStore(hold: BrowseHold(), browse: { [self] path in listing([], path: path) })

        await store.send(.prepared(fileCount: 3)) {
            $0.$progress.withLock {
                $0.phase = .downloading
                $0.filesTotal = 3
            }
        }
        await store.send(.willDownload(name: TestFile.aText)) { $0.$progress.withLock { $0.currentName = TestFile.aText } }
        await store.send(.progressed(filesDone: 1, unitsDone: 1.5)) {
            $0.$progress.withLock {
                $0.filesDone = 1
                $0.unitsDone = 1.5
            }
        }
        // An out of order snapshot from a concurrent task must not move the bar back.
        await store.send(.progressed(filesDone: 0, unitsDone: 1.0))
        #expect(store.state.progress.currentFileNumber == 2)
        #expect(store.state.progress.fractionComplete == 0.5)

        await store.send(.completed) {
            $0.$progress.withLock {
                $0.phase = .completed
                $0.currentName = ""
            }
        }
        #expect(store.state.progress.fractionComplete == 1)
    }

    @Test
    func aFailureKeepsThePinsAndClearsTheInterruptedMarker() async {
        let offline = pinnedStore(["A"])
        offline.setInterrupted(true)
        var state = freshState()
        state.pendingPinPaths = ["A"]
        let store = makeStore(state, hold: BrowseHold(), offline: offline, browse: { [self] path in listing([], path: path) })

        await store.send(.failed("Boom")) {
            $0.pendingPinPaths = []
            $0.$progress.withLock { $0.phase = .failed("Boom") }
        }

        #expect(offline.wasInterrupted() == false)
        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])
        #expect(!store.state.progress.isActive)
    }

    @Test
    func startDownloadWalksTheTreeDownloadsEveryFileAndPinsTheRoot() async {
        let offline = OfflineFileStore.inMemory()
        let downloaded = LockIsolated<[String]>([])
        let flushes = LockIsolated(0)
        let run = makeRun(
            offline: offline,
            browse: { [self] path in
                switch path {
                case "A": listing([file(TestFile.aText, path: "A", size: 10), folder("B", path: "A")], path: path)
                case "A/B": listing([file(TestFile.bText, path: "A/B", size: 20)], path: path)
                default: listing([], path: path)
                }
            },
            download: { item in
                downloaded.withValue { $0.append(item.id) }
                return URL(fileURLWithPath: "/tmp/\(item.name)")
            },
            configure: { $0.filesClient.flushDownloadConnections = { flushes.withValue { $0 += 1 } } }
        )

        await run.store.send(.startDownload([folder("A")])).finish()

        #expect(run.progress.wrappedValue.phase == .completed)
        #expect(run.progress.wrappedValue.filesTotal == 2)
        #expect(run.progress.wrappedValue.filesDone == 2)
        #expect(run.progress.wrappedValue.fractionComplete == 1)
        #expect(run.progress.wrappedValue.currentName == "")
        #expect(downloaded.value == ["A/a.txt", "A/B/b.txt"])
        #expect(flushes.value == 1)
        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])
        #expect(offline.wasInterrupted() == false)
    }

    @Test
    func resyncReDownloadsThePinnedRoots() async {
        let offline = pinnedStore(["A"])
        let downloaded = LockIsolated<[String]>([])
        let run = makeRun(
            offline: offline,
            browse: { [self] path in listing(path == "A" ? [file(TestFile.aText, path: "A", size: 5)] : [], path: path) },
            download: { item in
                downloaded.withValue { $0.append(item.id) }
                return URL(fileURLWithPath: "/tmp/\(item.name)")
            }
        )

        await run.store.send(.resyncTapped).finish()

        #expect(run.phase == .completed)
        #expect(downloaded.value == ["A/a.txt"])
        #expect(offline.lastAutoSyncAt() == MockDate.date)
    }

    @Test
    func autoSyncDownloadsOnlyTheNewFilesInPinnedFolders() async {
        let offline = OfflineFileStore.inMemory(localURLs: ["A/old.txt": URL(fileURLWithPath: "/tmp/old.txt")])
        offline.setPinnedRoots([OfflinePinnedRoot(path: "A", isDirectory: true)])
        let downloaded = LockIsolated<[String]>([])
        let run = makeRun(
            offline: offline,
            browse: { [self] path in
                listing(path == "A" ? [file("old.txt", path: "A"), file("new.txt", path: "A")] : [], path: path)
            },
            download: { item in
                downloaded.withValue { $0.append(item.id) }
                return URL(fileURLWithPath: "/tmp/\(item.name)")
            }
        )

        await run.store.send(.autoSync(force: false)).finish()

        #expect(downloaded.value == ["A/new.txt"]) // old.txt already offline, skipped
        #expect(run.progress.wrappedValue.filesTotal == 1)
        #expect(run.phase == .completed)
    }

    @Test
    func autoSyncIsThrottledButAForcedSyncBypassesIt() async {
        let offline = pinnedStore(["A"])
        offline.setLastAutoSyncAt(MockDate.date)
        let downloaded = LockIsolated<[String]>([])
        let run = makeRun(
            offline: offline,
            browse: { [self] path in listing(path == "A" ? [file("new.txt", path: "A")] : [], path: path) },
            download: { item in
                downloaded.withValue { $0.append(item.id) }
                return URL(fileURLWithPath: "/tmp/\(item.name)")
            },
            configure: { $0.date = .constant(MockDate.date.addingTimeInterval(100)) } // under the 300s throttle
        )

        // Throttled: too soon since the last sync, so nothing runs.
        await run.store.send(.autoSync(force: false)).finish()
        #expect(downloaded.value.isEmpty)
        #expect(run.phase == .idle)

        // Forced (a reconnect): runs regardless of the throttle.
        await run.store.send(.autoSync(force: true)).finish()
        #expect(downloaded.value == ["A/new.txt"])
        #expect(run.phase == .completed)
    }

    @Test
    func autoSyncRunsOnceTheThrottleHasPassed() async {
        let offline = pinnedStore(["A"])
        offline.setLastAutoSyncAt(MockDate.date)
        let run = makeRun(
            offline: offline,
            browse: { [self] path in listing(path == "A" ? [file("new.txt", path: "A")] : [], path: path) },
            configure: { $0.date = .constant(MockDate.date.addingTimeInterval(301)) }
        )

        await run.store.send(.autoSync(force: false)).finish()

        #expect(run.phase == .completed)
        #expect(offline.lastAutoSyncAt() == MockDate.date.addingTimeInterval(301))
    }

    @Test
    func theInterruptedMarkerIsSetWhileDownloadingAndClearsWhenItCompletes() async {
        let offline = OfflineFileStore.inMemory()
        let downloadGate = AsyncGate()
        let startedStream = AsyncStream<Void>.makeStream()
        let run = makeRun(
            offline: offline,
            browse: { [self] path in listing([file(TestFile.aText, path: "A")], path: path) },
            download: { _ in
                startedStream.continuation.yield()
                try await downloadGate.wait()
                return URL(fileURLWithPath: "/tmp/a.txt")
            }
        )

        let task = run.store.send(.startDownload([folder("A")]))
        var iterator = startedStream.stream.makeAsyncIterator()
        _ = await iterator.next()

        #expect(run.phase == .downloading)
        #expect(run.progress.wrappedValue.currentName == TestFile.aText)
        #expect(offline.wasInterrupted())

        downloadGate.open()
        await task.finish()
        #expect(run.phase == .completed)
        #expect(offline.wasInterrupted() == false)
    }

    @Test
    func aFailedFileStaysPendingButStillAdvancesTheBar() async {
        let run = makeRun(
            offline: pinnedStore(["A"]),
            browse: { [self] path in listing([file(TestFile.aText, path: "A"), file(TestFile.bText, path: "A")], path: path) },
            download: { item in
                if item.name == TestFile.aText {
                    throw FilesClientError.timedOut
                }
                return URL(fileURLWithPath: "/tmp/\(item.name)")
            }
        )

        await run.store.send(.resyncTapped).finish()

        #expect(run.phase == .completed)
        #expect(run.progress.wrappedValue.filesDone == 1)
        #expect(run.progress.wrappedValue.unitsDone == 2)
    }

    @Test
    func autoSyncStaysSilentWhenNothingIsNew() async {
        let offline = OfflineFileStore.inMemory(localURLs: ["A/a.txt": URL(fileURLWithPath: "/tmp/a.txt")])
        offline.setPinnedRoots([OfflinePinnedRoot(path: "A", isDirectory: true)])
        let run = makeRun(
            offline: offline,
            browse: { [self] path in listing(path == "A" ? [file(TestFile.aText, path: "A")] : [], path: path) }
        )

        await run.store.send(.autoSync(force: false)).finish()

        #expect(run.phase == .idle)
        #expect(offline.lastAutoSyncAt() == MockDate.date)
    }

    @Test
    func cancellingAFreshDownloadRollsBackItsNewlyAddedPins() async {
        let offline = OfflineFileStore.inMemory()
        let startedStream = AsyncStream<Void>.makeStream()
        let run = makeRun(
            offline: offline,
            browse: { [self] path in listing([file(TestFile.aText, path: "A", size: 10)], path: path) },
            // A cancellable hang, so the run is still in flight when the cancel arrives.
            download: { item in
                startedStream.continuation.yield()
                try await suspendUntilCancelled()
                return URL(fileURLWithPath: "/tmp/\(item.name)")
            }
        )

        let task = run.store.send(.startDownload([folder("A")]))
        var iterator = startedStream.stream.makeAsyncIterator()
        _ = await iterator.next()
        // Pins are written up front (so an app kill can resume).
        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])

        await run.store.send(.cancelTapped).finish()
        await task.finish()
        // A user cancel rolls the pin it just added back, so the manage screen doesn't show a phantom
        // "downloaded" folder that has no files.
        #expect(offline.pinnedRoots().isEmpty)
        #expect(run.phase == .idle)
        #expect(offline.wasInterrupted() == false)
    }

    @Test
    func cancellingKeepsPinsThatWereAlreadyThereBeforeTheRun() async {
        let offline = pinnedStore(["Old"])
        let startedStream = AsyncStream<Void>.makeStream()
        let run = makeRun(
            offline: offline,
            browse: { [self] path in listing([file(TestFile.aText, path: path)], path: path) },
            download: { _ in
                startedStream.continuation.yield()
                try await suspendUntilCancelled()
                return URL(fileURLWithPath: "/tmp/a.txt")
            }
        )

        let task = run.store.send(.startDownload([folder("New")]))
        var iterator = startedStream.stream.makeAsyncIterator()
        _ = await iterator.next()

        await run.store.send(.cancelTapped).finish()
        await task.finish()

        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "Old", isDirectory: true)])
    }

    @Test
    func startDownloadWithNoRootsIsANoOp() async {
        let store = makeStore(hold: BrowseHold(), browse: { [self] path in listing([], path: path) })

        await store.send(.startDownload([]))
        #expect(store.state.progress.phase == .idle)
    }

    @Test
    func anUnreadableSubfolderIsSkippedNotFatal() async {
        let downloaded = LockIsolated<[String]>([])
        let run = makeRun(
            browse: { [self] path in
                switch path {
                case "A": listing([file(TestFile.aText, path: "A", size: 10), folder("Locked", path: "A")], path: path)
                case "A/Locked": throw FilesClientError.forbidden(message: nil)
                default: listing([], path: path)
                }
            },
            download: { item in
                downloaded.withValue { $0.append(item.id) }
                return URL(fileURLWithPath: "/tmp/\(item.name)")
            }
        )

        await run.store.send(.startDownload([folder("A")])).finish()

        #expect(run.phase == .completed)
        #expect(downloaded.value == ["A/a.txt"])
    }

    @Test
    func aPinnedRootThatCannotBeListedWaitsForNetworkInsteadOfCompleting() async {
        let offline = OfflineFileStore.inMemory()
        let hold = BrowseHold()
        let store = makeStore(hold: hold, offline: offline, browse: { _ in throw FilesClientError.offline })

        await start(store, [folder("A")], hold: hold, pendingPins: ["A"])
        await store.receive(\.waitingForNetwork) {
            $0.pendingPinPaths = []
            $0.$progress.withLock { $0.phase = .waitingForNetwork }
        }

        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])
        #expect(offline.wasInterrupted() == false)
    }
}
