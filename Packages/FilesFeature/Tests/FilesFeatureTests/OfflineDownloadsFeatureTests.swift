import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import NetworkClient
import Testing
import TestUtils

// Every store gets its own account scope: the sync effect's cancel id is that scope, and TCA keeps
// cancellation ids in one process wide registry, so stores sharing a scope would cancel each other.
@Suite(.isolatedDependencies)
@MainActor
struct OfflineDownloadsFeatureTests {
    private typealias State = OfflineDownloadsFeature.State
    private typealias Harness = TestStoreOf<OfflineDownloadsFeature>

    private let serverURL = URL(fileURLWithPath: "/")

    private nonisolated func folder(_ name: String, path: String = "") -> FileItem {
        FileItem(name: name, path: path, dateModified: MockDate.date, size: 0, kind: "directory")
    }

    private nonisolated func file(_ name: String, path: String = "", size: Int64 = 100) -> FileItem {
        FileItem(name: name, path: path, dateModified: MockDate.date, size: size, kind: "txt")
    }

    private nonisolated func access() -> FileAccess {
        FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: false, canDownload: true)
    }

    private nonisolated func listing(_ items: [FileItem], path: String = "") -> BrowseResult {
        BrowseResult(items: items, access: access(), path: path)
    }

    /// Holds every folder listing until the test opens the gate it asked for. The run's first answer
    /// writes the shared progress, so it must not land before the `send` that started it is asserted.
    private final class BrowseHold: Sendable {
        private let current = LockIsolated(AsyncGate())

        init() {
            current.value.open()
        }

        func hold() -> AsyncGate {
            let gate = AsyncGate()
            current.setValue(gate)
            return gate
        }

        func wait() async throws {
            try await current.value.wait()
        }
    }

    private func freshState(scope: String = TestID.name()) -> State {
        withDependencies {
            $0.cacheScope = CacheScopeSource(current: { scope })
        } operation: {
            State(serverURL: serverURL)
        }
    }

    private func pinnedStore(_ paths: [String]) -> OfflineFileStore {
        let offline = OfflineFileStore.inMemory()
        offline.setPinnedRoots(paths.map { OfflinePinnedRoot(path: $0, isDirectory: true) })
        return offline
    }

    private func install(
        _ values: inout DependencyValues,
        hold: BrowseHold,
        offline: OfflineFileStore,
        browse: @escaping @Sendable (String) throws -> BrowseResult,
        download: @escaping @Sendable (FileItem) async throws -> URL
    ) {
        values.date = .constant(MockDate.date)
        values.offlineFileStore = offline
        values.filesClient.flushDownloadConnections = {}
        values.filesClient.browse = { _, path in
            try await hold.wait()
            return try browse(path)
        }
        values.filesClient.offlineDownloadFile = { _, item, _ in try await download(item) }
    }

    /// A strict `TestStore`, for runs whose one shared progress write is held back until the test is ready.
    private func makeStore(
        _ state: State? = nil,
        hold: BrowseHold,
        offline: OfflineFileStore = .inMemory(),
        browse: @escaping @Sendable (String) throws -> BrowseResult,
        download: @escaping @Sendable (FileItem) async throws -> URL = { URL(fileURLWithPath: "/tmp/\($0.name)") },
        configure: (inout DependencyValues) -> Void = { _ in }
    ) -> Harness {
        TestStore(initialState: state ?? freshState()) {
            OfflineDownloadsFeature()
        } withDependencies: {
            install(&$0, hold: hold, offline: offline, browse: browse, download: download)
            configure(&$0)
        }
    }

    /// A run that goes through several actions which each write the shared progress. A `TestStore`
    /// compares the live shared value with every received action, so an effect that sends the next
    /// one straight away (the end of one file and the start of the next) cannot be asserted step by
    /// step. These runs are driven on a plain `Store` to the end and the outcome is asserted.
    private struct Run {
        let store: StoreOf<OfflineDownloadsFeature>
        let progress: Shared<OfflineDownloadProgress>

        var phase: OfflineDownloadProgress.Phase {
            progress.wrappedValue.phase
        }
    }

    private func makeRun(
        _ state: State? = nil,
        offline: OfflineFileStore = .inMemory(),
        browse: @escaping @Sendable (String) throws -> BrowseResult,
        download: @escaping @Sendable (FileItem) async throws -> URL = { URL(fileURLWithPath: "/tmp/\($0.name)") },
        configure: @escaping (inout DependencyValues) -> Void = { _ in }
    ) -> Run {
        let state = state ?? freshState()
        let store = Store(initialState: state) {
            OfflineDownloadsFeature()
        } withDependencies: {
            install(&$0, hold: BrowseHold(), offline: offline, browse: browse, download: download)
            configure(&$0)
        }
        return Run(store: store, progress: state.$progress)
    }

    private func markPreparing(_ state: inout State) {
        state.$progress.withLock { $0.phase = .preparing }
    }

    /// A manual update: the tap shows preparing at once, and the held listing is released after it is asserted.
    private func resync(_ store: Harness, hold: BrowseHold) async {
        let gate = hold.hold()
        await store.send(.resyncTapped) { markPreparing(&$0) }
        gate.open()
    }

    private func start(_ store: Harness, _ roots: [FileItem], hold: BrowseHold, pendingPins: Set<String>) async {
        let gate = hold.hold()
        await store.send(.startDownload(roots)) {
            $0.pendingPinPaths = pendingPins
            markPreparing(&$0)
        }
        gate.open()
    }

    private func receiveWaiting(_ store: Harness) async {
        await store.receive(\.waitingForNetwork) { $0.$progress.withLock { $0.phase = .waitingForNetwork } }
    }

    // MARK: Progress actions

    @Test
    func theRunActionsAdvanceTheSharedProgressAndALateSnapshotNeverLowersIt() async {
        let store = makeStore(hold: BrowseHold(), browse: { [self] path in listing([], path: path) })

        await store.send(.prepared(fileCount: 3)) {
            $0.$progress.withLock {
                $0.phase = .downloading
                $0.filesTotal = 3
            }
        }
        await store.send(.willDownload(name: "a.txt")) { $0.$progress.withLock { $0.currentName = "a.txt" } }
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

    // MARK: Downloads and syncs

    @Test
    func startDownloadWalksTheTreeDownloadsEveryFileAndPinsTheRoot() async {
        let offline = OfflineFileStore.inMemory()
        let downloaded = LockIsolated<[String]>([])
        let flushes = LockIsolated(0)
        let run = makeRun(
            offline: offline,
            browse: { [self] path in
                switch path {
                case "A": listing([file("a.txt", path: "A", size: 10), folder("B", path: "A")], path: path)
                case "A/B": listing([file("b.txt", path: "A/B", size: 20)], path: path)
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
            browse: { [self] path in listing(path == "A" ? [file("a.txt", path: "A", size: 5)] : [], path: path) },
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
            browse: { [self] path in listing([file("a.txt", path: "A")], path: path) },
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
        #expect(run.progress.wrappedValue.currentName == "a.txt")
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
            browse: { [self] path in listing([file("a.txt", path: "A"), file("b.txt", path: "A")], path: path) },
            download: { item in
                if item.name == "a.txt" {
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
            browse: { [self] path in listing(path == "A" ? [file("a.txt", path: "A")] : [], path: path) }
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
            browse: { [self] path in listing([file("a.txt", path: "A", size: 10)], path: path) },
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
            browse: { [self] path in listing([file("a.txt", path: path)], path: path) },
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
                case "A": listing([file("a.txt", path: "A", size: 10), folder("Locked", path: "A")], path: path)
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

    // MARK: Pruning offline files

    private func storeWithSlots(_ paths: Set<String>) -> (store: OfflineFileStore, slots: LockIsolated<Set<String>>) {
        let slots = LockIsolated(paths)
        var offline = OfflineFileStore.inMemory(
            localURLs: Dictionary(uniqueKeysWithValues: paths.map { ($0, URL(fileURLWithPath: "/tmp/\($0)")) })
        )
        offline.setPinnedRoots([OfflinePinnedRoot(path: "A", isDirectory: true)])
        offline.reconcile = { current in
            guard let current else { return }
            slots.withValue { $0 = $0.intersection(current) }
        }
        return (offline, slots)
    }

    @Test
    func aSyncWithOneFailedSubfolderNeverPrunesOfflineSlots() async {
        let (offline, slots) = storeWithSlots(["A/a.txt", "A/Slow/b.txt"])
        let hold = BrowseHold()
        let store = makeStore(hold: hold, offline: offline) { [self] path in
            guard path == "A" else { throw FilesClientError.offline }
            return listing([file("a.txt", path: "A"), folder("Slow", path: "A")], path: path)
        }

        await resync(store, hold: hold)
        await receiveWaiting(store)

        #expect(slots.value == ["A/a.txt", "A/Slow/b.txt"])
    }

    @Test
    func aSyncWhereEveryFolderFailsKeepsEverySlotAndShowsWaiting() async {
        let (offline, slots) = storeWithSlots(["A/a.txt", "A/Sub/b.txt"])
        let hold = BrowseHold()
        let store = makeStore(hold: hold, offline: offline) { _ in throw FilesClientError.offline }

        await resync(store, hold: hold)
        await receiveWaiting(store)

        #expect(slots.value == ["A/a.txt", "A/Sub/b.txt"])
        #expect(store.state.progress.phase == .waitingForNetwork)
    }

    @Test
    func aCompleteWalkStillPrunesFilesTheServerNoLongerLists() async {
        let (offline, slots) = storeWithSlots(["A/a.txt", "A/gone.txt"])
        let run = makeRun(offline: offline, browse: { [self] path in listing([file("a.txt", path: "A")], path: path) })

        await run.store.send(.resyncTapped).finish()

        #expect(run.phase == .completed)
        #expect(slots.value == ["A/a.txt"])
    }

    // MARK: A folder the server answers 404 for

    /// Answers `A` and `B` with `rootError`, and the parent of a pinned folder with `parent`.
    private func notFoundStore(
        offline: OfflineFileStore, hold: BrowseHold, rootError: FilesClientError, parent: @escaping @Sendable () throws -> BrowseResult
    ) -> Harness {
        makeStore(hold: hold, offline: offline) { path in
            guard path.isEmpty else { throw rootError }
            return try parent()
        }
    }

    @Test
    func aSingleNotFoundNeverUnpinsAFolderWhoseParentCannotBeListed() async {
        let offline = pinnedStore(["A"])
        let hold = BrowseHold()
        let store = notFoundStore(offline: offline, hold: hold, rootError: .server(statusCode: 404)) { throw FilesClientError.offline }

        await resync(store, hold: hold)
        await receiveWaiting(store)

        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])
        #expect(store.state.progress.phase == .waitingForNetwork)
    }

    @Test
    func aTransientNotFoundKeepsTheFilesUnderTheFolder() async {
        let (offline, slots) = storeWithSlots(["A/a.txt", "A/Sub/b.txt"])
        let hold = BrowseHold()
        let store = notFoundStore(offline: offline, hold: hold, rootError: .server(statusCode: 404)) { throw FilesClientError.timedOut }

        await resync(store, hold: hold)
        await receiveWaiting(store)

        #expect(slots.value == ["A/a.txt", "A/Sub/b.txt"])
        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])
    }

    @Test
    func aFolderTheParentListingOmitsIsUnpinnedAndTheUserIsToldWhich() async {
        let offline = pinnedStore(["A", "B"])
        let hold = BrowseHold()
        let store = notFoundStore(offline: offline, hold: hold, rootError: .server(statusCode: 404)) { [self] in
            listing([folder("B")])
        }

        await resync(store, hold: hold)
        await store.receive(\.pinsRemoved) {
            $0.$progress.withLock { $0.phase = .failed(L10n.Offline.pinRemoved("A")) }
        }

        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "B", isDirectory: true)])
        #expect(!store.state.progress.isActive)
    }

    @Test
    func aFolderTheParentListingStillShowsKeepsItsPinAndItsStrikes() async {
        let offline = pinnedStore(["A"])
        let hold = BrowseHold()
        let store = notFoundStore(offline: offline, hold: hold, rootError: .server(statusCode: 404)) { [self] in
            listing([folder("A")])
        }

        await resync(store, hold: hold)
        await receiveWaiting(store)
        await resync(store, hold: hold)
        await receiveWaiting(store)
        await resync(store, hold: hold)
        await receiveWaiting(store)

        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])
        #expect(offline.recordMissingRoot("A") == 1, "a folder the parent lists is not missing, so earlier strikes reset")
    }

    @Test
    func twoNotFoundSyncsInARowUnpinAFolderWhoseParentCannotBeListed() async {
        let offline = pinnedStore(["A"])
        let hold = BrowseHold()
        let store = notFoundStore(offline: offline, hold: hold, rootError: .server(statusCode: 404)) { throw FilesClientError.offline }

        await resync(store, hold: hold)
        await receiveWaiting(store)
        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])

        await resync(store, hold: hold)
        await store.receive(\.pinsRemoved) {
            $0.$progress.withLock { $0.phase = .failed(L10n.Offline.pinRemoved("A")) }
        }

        #expect(offline.pinnedRoots().isEmpty)
    }

    @Test
    func aSuccessfulListingBetweenTwoNotFoundSyncsResetsTheStrikes() async {
        let offline = pinnedStore(["A"])
        let isHealthy = LockIsolated(false)
        let run = makeRun(offline: offline) { [self] path in
            if isHealthy.value {
                return listing([], path: path)
            }
            throw FilesClientError.server(statusCode: 404)
        }

        await run.store.send(.resyncTapped).finish()
        #expect(run.phase == .waitingForNetwork)
        isHealthy.setValue(true)
        await run.store.send(.resyncTapped).finish()
        #expect(run.phase == .completed)
        isHealthy.setValue(false)
        await run.store.send(.resyncTapped).finish()
        #expect(run.phase == .waitingForNetwork)

        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])
    }

    @Test(arguments: ["Access denied", "Path not found.", "path not found", "ACCESS DENIED."])
    func anAccessOrPathNotFoundMessageNeverCountsAsTheFolderBeingGone(message: String) async {
        let offline = pinnedStore(["A"])
        let hold = BrowseHold()
        let store = notFoundStore(offline: offline, hold: hold, rootError: .serverMessage(statusCode: 404, message: message)) {
            throw FilesClientError.offline
        }

        for _ in 0 ..< 3 {
            await resync(store, hold: hold)
            await receiveWaiting(store)
        }

        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])
    }

    @Test
    func aNotFoundWithAnotherMessageStillNeedsTwoSyncs() async {
        let offline = pinnedStore(["A"])
        let hold = BrowseHold()
        let store = notFoundStore(offline: offline, hold: hold, rootError: .serverMessage(statusCode: 404, message: "Share expired")) {
            throw FilesClientError.offline
        }

        await resync(store, hold: hold)
        await receiveWaiting(store)
        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])
        await resync(store, hold: hold)
        await store.receive(\.pinsRemoved) {
            $0.$progress.withLock { $0.phase = .failed(L10n.Offline.pinRemoved("A")) }
        }

        #expect(offline.pinnedRoots().isEmpty)
    }

    @Test
    func aMissingSubfolderOfAPinnedRootNeverUnpinsAnythingAndLeavesTheWalkIncomplete() async {
        let (offline, slots) = storeWithSlots(["A/a.txt", "A/Gone/b.txt"])
        let hold = BrowseHold()
        let store = makeStore(hold: hold, offline: offline) { [self] path in
            guard path == "A" else { throw FilesClientError.server(statusCode: 404) }
            return listing([file("a.txt", path: "A"), folder("Gone", path: "A")], path: path)
        }

        await resync(store, hold: hold)
        await receiveWaiting(store)

        #expect(slots.value == ["A/a.txt", "A/Gone/b.txt"], "a partial walk never prunes")
        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])
    }

    // MARK: Other listing failures

    @Test
    func aForbiddenPinnedFolderKeepsItsPinAndReportsAnAccessMessage() async {
        let offline = pinnedStore(["A"])
        let hold = BrowseHold()
        let store = makeStore(hold: hold, offline: offline) { _ in throw FilesClientError.forbidden(message: nil) }

        await resync(store, hold: hold)
        await store.receive(\.failed) {
            $0.$progress.withLock { $0.phase = .failed(FilesClientError.forbidden(message: nil).userMessage) }
        }

        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])
    }

    @Test
    func aForbiddenFolderIsSilentForAnAutomaticSync() async {
        let offline = pinnedStore(["A"])
        let hold = BrowseHold()
        let store = makeStore(hold: hold, offline: offline) { _ in throw FilesClientError.forbidden(message: nil) }

        let gate = hold.hold()
        await store.send(.autoSync(force: false))
        gate.open()
        await store.receive(\.autoSyncFailed)

        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])
        #expect(store.state.progress.phase == .idle)
    }

    @Test(arguments: [FilesClientError.offline, .timedOut, .server(statusCode: 500), .server(statusCode: 503)])
    func offlineTimeoutAndServerErrorsStayIncompleteAndKeepThePin(error: FilesClientError) async {
        let offline = pinnedStore(["A"])
        let hold = BrowseHold()
        let store = makeStore(hold: hold, offline: offline) { _ in throw error }

        await resync(store, hold: hold)
        await receiveWaiting(store)

        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])
        #expect(store.state.progress.phase == .waitingForNetwork)
    }

    @Test
    func walkClassifiesEachFailureOfAFolderListing() async throws {
        let result = try await OfflineDownloadsFeature.walk(
            roots: [folder("A")], serverURL: serverURL,
            filesClient: withDependencies {
                $0.filesClient.browse = { _, path in
                    switch path {
                    case "A":
                        BrowseResult(
                            items: [folder("Gone", path: "A"), folder("Locked", path: "A"), folder("Down", path: "A"), file("a.txt", path: "A")],
                            access: access(), path: path
                        )
                    case "A/Gone": throw FilesClientError.server(statusCode: 404)
                    case "A/Locked": throw FilesClientError.forbidden(message: nil)
                    default: throw FilesClientError.server(statusCode: 502)
                    }
                }
            } operation: {
                @Dependency(\.filesClient) var client
                return client
            }
        )
        #expect(result.goneFolders == ["A/Gone"])
        #expect(result.ambiguousGoneFolders.isEmpty)
        #expect(result.forbiddenFolders == ["A/Locked"])
        #expect(result.failedFolders == ["A/Down"])
        #expect(result.hasIncompleteWalk)
        #expect(result.hasForbiddenFolders)
    }

    @Test
    func walkReportsTheFoldersThatFailedToList() async throws {
        let result = try await OfflineDownloadsFeature.walk(
            roots: [folder("A")], serverURL: serverURL,
            filesClient: withDependencies {
                $0.filesClient.browse = { _, path in
                    switch path {
                    case "A":
                        BrowseResult(items: [file("a.txt", path: "A"), folder("Bad", path: "A")], access: access(), path: path)
                    default:
                        throw FilesClientError.offline
                    }
                }
            } operation: {
                @Dependency(\.filesClient) var client
                return client
            }
        )
        #expect(result.files.map(\.id) == ["A/a.txt"])
        #expect(result.failedFolders == ["A/Bad"])
        #expect(result.hasIncompleteWalk)
    }

    @Test
    func autoSyncDoesNothingWhileOffline() async {
        let offline = pinnedStore(["A"])
        let browseCalls = LockIsolated(0)
        let store = makeStore(
            hold: BrowseHold(),
            offline: offline,
            browse: { [self] path in
                browseCalls.withValue { $0 += 1 }
                return listing([], path: path)
            },
            configure: { $0.connectivity = ConnectivityClient(isOnline: { false }, events: { AsyncStream { _ in } }) }
        )

        await store.send(.autoSync(force: true))
        #expect(browseCalls.value == 0)
        #expect(store.state.progress.phase == .idle)
    }

    @Test
    func removeAllOfflineClearsTheProgressAndTheCurrentAccountsFiles() async {
        let removals = LockIsolated(0)
        var offline = pinnedStore(["A"])
        offline.removeCurrentAccount = { removals.withValue { $0 += 1 } }
        var state = freshState()
        state.$progress.withLock { $0.phase = .completed }
        let store = makeStore(state, hold: BrowseHold(), offline: offline, browse: { [self] path in listing([], path: path) })

        await store.send(.removeAllOfflineTapped) { $0.$progress.withLock { $0 = OfflineDownloadProgress() } }
        await store.finish()

        #expect(removals.value == 1)
    }

    // MARK: Account scope

    private func accounts() -> (a: String, b: String) {
        let id = TestID.name()
        return ("https://files.example.com|alice-\(id)", "https://files.example.com|bob-\(id)")
    }

    private final class ScopeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var scope: String

        init(_ scope: String) {
            self.scope = scope
        }

        var value: String {
            get { lock.withLock { scope } }
            set { lock.withLock { scope = newValue } }
        }
    }

    /// A store whose every call records the scope it ran under.
    private func recordingStore(
        seen: LockIsolated<Set<String>>, base: OfflineFileStore
    ) -> OfflineFileStore {
        var store = base
        store.pinnedRoots = { seen.withValue { $0.insert(CacheAccountScope.current) }; return base.pinnedRoots() }
        store.setPinnedRoots = { roots in seen.withValue { $0.insert(CacheAccountScope.current) }; base.setPinnedRoots(roots) }
        store.reconcile = { paths in seen.withValue { $0.insert(CacheAccountScope.current) }; base.reconcile(paths) }
        store.localURL = { item in seen.withValue { $0.insert(CacheAccountScope.current) }; return base.localURL(item) }
        store.setInterrupted = { value in seen.withValue { $0.insert(CacheAccountScope.current) }; base.setInterrupted(value) }
        store.wasInterrupted = { seen.withValue { $0.insert(CacheAccountScope.current) }; return base.wasInterrupted() }
        store.lastAutoSyncAt = { seen.withValue { $0.insert(CacheAccountScope.current) }; return base.lastAutoSyncAt() }
        store.setLastAutoSyncAt = { date in seen.withValue { $0.insert(CacheAccountScope.current) }; base.setLastAutoSyncAt(date) }
        return store
    }

    private func scopedState(_ box: ScopeBox) -> State {
        withDependencies {
            $0.cacheScope = CacheScopeSource(current: { box.value })
        } operation: {
            State(serverURL: serverURL)
        }
    }

    private func scopedRun(box: ScopeBox, seen: LockIsolated<Set<String>>, base: OfflineFileStore) -> Run {
        makeRun(
            scopedState(box),
            offline: recordingStore(seen: seen, base: base),
            browse: { [self] path in
                seen.withValue { $0.insert(CacheAccountScope.current) }
                return listing([file("a.txt", path: "A")], path: path)
            },
            download: { _ in
                seen.withValue { $0.insert(CacheAccountScope.current) }
                return URL(fileURLWithPath: "/tmp/a.txt")
            },
            configure: { $0.cacheScope = CacheScopeSource(current: { box.value }) }
        )
    }

    @Test
    func aSyncStartedForOneAccountKeepsUsingItAfterTheActiveAccountChanges() async {
        let (accountA, accountB) = accounts()
        let box = ScopeBox(accountA)
        let seen = LockIsolated<Set<String>>([])
        let run = scopedRun(box: box, seen: seen, base: pinnedStore(["A"]))
        box.value = accountB

        await run.store.send(.resyncTapped).finish()

        #expect(run.phase == .completed)
        #expect(seen.value == [accountA])
    }

    @Test
    func aDownloadStartedForOneAccountKeepsUsingItAfterTheActiveAccountChanges() async {
        let (accountA, accountB) = accounts()
        let box = ScopeBox(accountA)
        let seen = LockIsolated<Set<String>>([])
        let run = scopedRun(box: box, seen: seen, base: .inMemory())
        box.value = accountB

        await run.store.send(.startDownload([folder("A")])).finish()

        #expect(run.phase == .completed)
        #expect(seen.value == [accountA])
    }

    // MARK: Leaving an account

    private struct HangingSync {
        let run: Run
        let started: AsyncStream<Void>
        let gate: AsyncGate
        let wasCancelled: LockIsolated<Bool>
    }

    private func hangingSync(scope: String) -> HangingSync {
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let gate = AsyncGate()
        let wasCancelled = LockIsolated(false)
        let run = makeRun(
            freshState(scope: scope),
            offline: pinnedStore(["A"]),
            browse: { _ in throw FilesClientError.offline },
            configure: {
                $0.filesClient.browse = { [self] _, path in
                    startedContinuation.yield()
                    do {
                        try await gate.wait()
                    } catch {
                        wasCancelled.setValue(true)
                        throw error
                    }
                    return listing([], path: path)
                }
            }
        )
        return HangingSync(run: run, started: started, gate: gate, wasCancelled: wasCancelled)
    }

    @Test
    func leavingAnAccountCancelsItsRunningSyncAndClearsItsProgress() async {
        let (accountA, _) = accounts()
        let hanging = hangingSync(scope: accountA)

        let task = hanging.run.store.send(.resyncTapped)
        var started = hanging.started.makeAsyncIterator()
        _ = await started.next()
        #expect(hanging.run.phase == .preparing)

        await hanging.run.store.send(.accountDeactivated(scope: accountA)).finish()
        await task.finish()

        #expect(hanging.wasCancelled.value)
        #expect(hanging.run.phase == .idle)
    }

    @Test
    func leavingAnotherAccountLeavesThisAccountsSyncRunning() async {
        let (accountA, accountB) = accounts()
        let hanging = hangingSync(scope: accountB)

        let task = hanging.run.store.send(.resyncTapped)
        var started = hanging.started.makeAsyncIterator()
        _ = await started.next()
        // The shared progress row is cleared whichever account is left, but this sync is not cancelled.
        await hanging.run.store.send(.accountDeactivated(scope: accountA)).finish()
        #expect(hanging.run.phase == .idle)

        hanging.gate.open()
        await task.finish()

        #expect(!hanging.wasCancelled.value)
        #expect(hanging.run.phase == .completed)
    }

    // MARK: Waiting for network

    @Test
    func aSyncStartingOnceBackOnlineClearsTheWaitingNote() async {
        var state = freshState()
        state.$progress.withLock { $0.phase = .waitingForNetwork }
        let store = makeStore(state, hold: BrowseHold(), browse: { [self] path in listing([], path: path) })

        await store.send(.autoSync(force: true)) { $0.$progress.withLock { $0.phase = .idle } }
    }

    @Test
    func theWaitingNoteIsNotAnActiveRunSoPinsStayVisible() async {
        let store = makeStore(
            hold: BrowseHold(),
            offline: pinnedStore(["A"]),
            browse: { [self] path in listing([], path: path) },
            configure: { $0.connectivity = ConnectivityClient(isOnline: { false }, events: { AsyncStream { _ in } }) }
        )

        await store.send(.resyncTapped) { $0.$progress.withLock { $0.phase = .waitingForNetwork } }

        #expect(!store.state.progress.isActive)
        #expect(store.state.progress.fractionComplete == 0)
    }
}
