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

/// Holds every folder listing until the test opens the gate it asked for. The run's first answer
/// writes the shared progress, so it must not land before the `send` that started it is asserted.
final class OfflineDownloadsBrowseHold: Sendable {
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

/// A run that goes through several actions which each write the shared progress. A `TestStore`
/// compares the live shared value with every received action, so an effect that sends the next
/// one straight away (the end of one file and the start of the next) cannot be asserted step by
/// step. These runs are driven on a plain `Store` to the end and the outcome is asserted.
struct OfflineDownloadsRun {
    let store: StoreOf<OfflineDownloadsFeature>
    let progress: Shared<OfflineDownloadProgress>

    var phase: OfflineDownloadProgress.Phase {
        progress.wrappedValue.phase
    }
}

@MainActor
protocol OfflineDownloadsTestSupport {}

extension OfflineDownloadsTestSupport {
    typealias State = OfflineDownloadsFeature.State
    typealias Harness = TestStoreOf<OfflineDownloadsFeature>

    typealias BrowseHold = OfflineDownloadsBrowseHold
    typealias Run = OfflineDownloadsRun

    var serverURL: URL {
        URL(fileURLWithPath: "/")
    }

    nonisolated func folder(_ name: String, path: String = "") -> FileItem {
        FileItem(name: name, path: path, dateModified: MockDate.date, size: 0, kind: FileItem.directoryKind)
    }

    nonisolated func file(_ name: String, path: String = "", size: Int64 = 100) -> FileItem {
        FileItem(name: name, path: path, dateModified: MockDate.date, size: size, kind: TestKind.text)
    }

    nonisolated func access() -> FileAccess {
        FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: false, canDownload: true)
    }

    nonisolated func listing(_ items: [FileItem], path: String = "") -> BrowseResult {
        BrowseResult(items: items, access: access(), path: path)
    }

    func freshState(scope: String = TestID.name()) -> State {
        withDependencies {
            $0.cacheScope = CacheScopeSource(current: { scope })
        } operation: {
            State(serverURL: serverURL)
        }
    }

    func pinnedStore(_ paths: [String]) -> OfflineFileStore {
        let offline = OfflineFileStore.inMemory()
        offline.setPinnedRoots(paths.map { OfflinePinnedRoot(path: $0, isDirectory: true) })
        return offline
    }

    func install(
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
    func makeStore(
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

    func makeRun(
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

    func markPreparing(_ state: inout State) {
        state.$progress.withLock { $0.phase = .preparing }
    }

    /// A manual update: the tap shows preparing at once, and the held listing is released after it is asserted.
    func resync(_ store: Harness, hold: BrowseHold) async {
        let gate = hold.hold()
        await store.send(.resyncTapped) { markPreparing(&$0) }
        gate.open()
    }

    func start(_ store: Harness, _ roots: [FileItem], hold: BrowseHold, pendingPins: Set<String>) async {
        let gate = hold.hold()
        await store.send(.startDownload(roots)) {
            $0.pendingPinPaths = pendingPins
            markPreparing(&$0)
        }
        gate.open()
    }

    func receiveWaiting(_ store: Harness) async {
        await store.receive(\.waitingForNetwork) { $0.$progress.withLock { $0.phase = .waitingForNetwork } }
    }
}
