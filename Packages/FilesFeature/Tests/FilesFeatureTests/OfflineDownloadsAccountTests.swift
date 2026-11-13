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
struct OfflineDownloadsAccountTests: OfflineDownloadsTestSupport {
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
        store
            .setPinnedRoots = { roots in
                seen.withValue { $0.insert(CacheAccountScope.current) }; base.setPinnedRoots(roots)
            }
        store.reconcile = { paths in seen.withValue { $0.insert(CacheAccountScope.current) }; base.reconcile(paths) }
        store.localURL = { item in seen.withValue { $0.insert(CacheAccountScope.current) }; return base.localURL(item) }
        store
            .setInterrupted = { value in
                seen.withValue { $0.insert(CacheAccountScope.current) }; base.setInterrupted(value)
            }
        store.wasInterrupted = { seen.withValue { $0.insert(CacheAccountScope.current) }; return base.wasInterrupted() }
        store.lastAutoSyncAt = { seen.withValue { $0.insert(CacheAccountScope.current) }; return base.lastAutoSyncAt() }
        store
            .setLastAutoSyncAt = { date in
                seen.withValue { $0.insert(CacheAccountScope.current) }; base.setLastAutoSyncAt(date)
            }
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
                return listing([file(TestFile.aText, path: "A")], path: path)
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
