import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Localization
import NetworkClient

/// The offline download engine. A session lifetime sibling of the tab features (mounted by
/// `MainTabFeature`), so the long running download effect it starts survives the user leaving the
/// Settings screen where it was kicked off. It walks each pinned root over `GET /api/browse`,
/// downloads every file it finds into the durable offline store (`FilesClient.offlineDownloadFile`),
/// and publishes progress through `@Shared` so Settings can render it live.
@Reducer
public struct OfflineDownloadsFeature {
    @ObservableState
    public struct State: Equatable {
        public var serverURL: URL
        @Shared(.inMemory(OfflineDownloadProgress.sharedKey)) public var progress = OfflineDownloadProgress()
        /// Roots this in flight `startDownload` newly added to the manifest (ones not already pinned).
        /// Kept so an explicit cancel can roll them back: a pin is written up front so an app kill can
        /// resume, but a user who cancels never wanted those folders pinned, and leaving them makes the
        /// manage screen list folders as downloaded when nothing was.
        public var pendingPinPaths: Set<String> = []

        public init(serverURL: URL = URL(fileURLWithPath: "/")) {
            self.serverURL = serverURL
        }
    }

    public enum Action: Sendable {
        /// Start (or add to) an offline download for the chosen roots. Folders are walked
        /// recursively; files are downloaded directly.
        case startDownload([FileItem])
        case prepared(fileCount: Int)
        case willDownload(name: String)
        case progressed(filesDone: Int, unitsDone: Double)
        case completed
        /// The pinned roots could not be listed (offline or the server is unreachable): nothing was
        /// downloaded yet and the next sync will pick them up.
        case waitingForNetwork
        case failed(String)
        case cancelTapped
        case removeAllOfflineTapped
        /// Manual "Update Offline Files": re-walk the pinned roots and download only the new/changed
        /// files. Shows progress and a completion even when nothing needed downloading.
        case resyncTapped
        /// Automatic sync on app open / foreground / reconnect: same as `resyncTapped` but silent:
        /// it only surfaces progress if there is actually something new to download, so a launch with
        /// nothing changed shows nothing. `force` bypasses the foreground throttle (used on reconnect).
        case autoSync(force: Bool)
        /// A background sync failed; clear any progress it was showing without an error banner.
        case autoSyncFailed
    }

    @Dependency(\.filesClient) var filesClient
    @Dependency(\.offlineFileStore) var offlineFileStore
    @Dependency(\.date) var date
    @Dependency(\.connectivity) var connectivity

    private enum Constants {
        /// Files download one at a time, on purpose. The backend streams a single `/api/download` well
        /// but chokes serving several at once over one connection (streams starve), and a starved
        /// stream would hold its slot for minutes under the generous timeout and stall the whole run.
        /// Serial also makes the "X of Y files" count honest and legible: exactly one file is in flight,
        /// so the number is unambiguous instead of several partial files summing to a confusing bar.
        static let maxConcurrentDownloads = 1
        /// How many folder listings to fetch at once while walking the tree in the preparing phase.
        /// Higher than the download fan out: `browse` calls are small and latency bound, so the walk
        /// finishes far quicker without the bandwidth pressure of concurrent file transfers.
        static let maxConcurrentBrowses = 8
        static let downloadTaskName = "OfflineDownload"
        static let syncTaskName = "OfflineSync"
        /// Minimum gap between automatic foreground syncs, so re-walking every pinned folder doesn't
        /// run on every quick app switch. A reconnect or a manual update bypasses it.
        static let autoSyncMinInterval: TimeInterval = 300
        static let notFoundStatusCode = 404
    }

    private enum CancelID { case download }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .startDownload(roots):
                guard !roots.isEmpty else { return .none }
                state.$progress.withLock {
                    $0 = OfflineDownloadProgress()
                    $0.phase = .preparing
                }
                let serverURL = state.serverURL
                let filesClient = filesClient
                let offlineFileStore = offlineFileStore
                let existingRoots = offlineFileStore.pinnedRoots()
                let existingPaths = Set(existingRoots.map(\.path))
                let newRoots = roots.map { OfflinePinnedRoot(path: $0.id, isDirectory: $0.isDirectory) }
                // Track only the genuinely new pins, so a cancel rolls back exactly what this run added.
                state.pendingPinPaths = Set(newRoots.map(\.path)).subtracting(existingPaths)
                return .run { send in
                    // Record the pins up front, so an interrupted run (app killed mid download) keeps
                    // its roots and a later sync resumes the missing files instead of losing them.
                    offlineFileStore.setPinnedRoots(Self.mergedRoots(existing: existingRoots, adding: newRoots))

                    let walk = try await Self.walk(roots: roots, serverURL: serverURL, filesClient: filesClient)
                    let files = walk.files
                    guard !(files.isEmpty && walk.hasIncompleteWalk) else {
                        await send(.waitingForNetwork)
                        return
                    }
                    await send(.prepared(fileCount: files.count))
                    offlineFileStore.setInterrupted(true)
                    await BackgroundActivity.run(name: Constants.downloadTaskName) {
                        await Self.runDownloads(files, serverURL: serverURL, filesClient: filesClient, send: send)
                    }
                    if Task.isCancelled {
                        return
                    }
                    await send(.completed)
                } catch: { error, send in
                    guard !(error is CancellationError) else { return }
                    await send(.failed((error as? FilesClientError)?.userMessage ?? L10n.Offline.downloadFailed))
                }
                .cancellable(id: CancelID.download, cancelInFlight: true)

            case .resyncTapped:
                guard !state.progress.isActive else { return .none }
                guard connectivity.isOnline() else {
                    state.$progress.withLock {
                        $0 = OfflineDownloadProgress()
                        $0.phase = .waitingForNetwork
                    }
                    return .none
                }
                state.$progress.withLock {
                    $0 = OfflineDownloadProgress()
                    $0.phase = .preparing
                }
                return syncPinnedRoots(state: &state, announceWhenNothingPending: true)

            case let .autoSync(force):
                // Never stomp a run already in progress (a manual download, or an earlier auto-sync).
                guard !state.progress.isActive else { return .none }
                // An offline sync can only fail, and a failed listing must not look like an empty server.
                guard connectivity.isOnline() else { return .none }
                // Throttle automatic foreground syncs; a reconnect or manual update forces through.
                if !force, let last = offlineFileStore.lastAutoSyncAt(),
                   date.now.timeIntervalSince(last) < Constants.autoSyncMinInterval
                {
                    return .none
                }
                // A download interrupted by an app kill left its marker: show a resuming state and
                // announce completion so the flag clears even if nothing turned out to be pending.
                let resuming = offlineFileStore.wasInterrupted()
                if resuming {
                    state.$progress.withLock {
                        $0 = OfflineDownloadProgress()
                        $0.phase = .preparing
                    }
                }
                return syncPinnedRoots(state: &state, announceWhenNothingPending: resuming)

            case .autoSyncFailed:
                offlineFileStore.setInterrupted(false)
                state.$progress.withLock {
                    if $0.isActive {
                        $0 = OfflineDownloadProgress()
                    }
                }
                return .none

            case let .prepared(fileCount):
                state.$progress.withLock {
                    $0.phase = .downloading
                    $0.filesTotal = fileCount
                }
                return .none

            case let .willDownload(name):
                state.$progress.withLock { $0.currentName = name }
                return .none

            case let .progressed(filesDone, unitsDone):
                state.$progress.withLock {
                    // Guard against an out of order snapshot from a concurrent task lowering the bar.
                    $0.filesDone = max($0.filesDone, filesDone)
                    $0.unitsDone = max($0.unitsDone, unitsDone)
                }
                return .none

            case .completed:
                offlineFileStore.setInterrupted(false)
                state.pendingPinPaths = []
                state.$progress.withLock {
                    $0.phase = .completed
                    $0.currentName = ""
                }
                return .none

            case .waitingForNetwork:
                offlineFileStore.setInterrupted(false)
                state.pendingPinPaths = []
                state.$progress.withLock {
                    $0.phase = .waitingForNetwork
                    $0.currentName = ""
                }
                return .none

            case let .failed(message):
                offlineFileStore.setInterrupted(false)
                // A failed run keeps its pins so a retry / next sync can resume the missing files.
                state.pendingPinPaths = []
                state.$progress.withLock { $0.phase = .failed(message) }
                return .none

            case .cancelTapped:
                offlineFileStore.setInterrupted(false)
                // Roll back the pins this run added but the user chose not to keep, so the manage
                // screen doesn't list folders as downloaded when nothing was. Slots already fetched
                // for a reverted root are dropped by `reconcile`.
                let rolledBack = state.pendingPinPaths
                state.pendingPinPaths = []
                let offlineFileStore = offlineFileStore
                state.$progress.withLock { $0 = OfflineDownloadProgress() }
                return .merge(
                    .cancel(id: CancelID.download),
                    .run { _ in
                        if !rolledBack.isEmpty {
                            offlineFileStore.setPinnedRoots(
                                offlineFileStore.pinnedRoots().filter { !rolledBack.contains($0.path) }
                            )
                            offlineFileStore.reconcile(nil)
                        }
                    }
                )

            case .removeAllOfflineTapped:
                let offlineFileStore = offlineFileStore
                state.$progress.withLock { $0 = OfflineDownloadProgress() }
                return .merge(
                    .cancel(id: CancelID.download),
                    // Only this account's offline files (slots + manifest), never another account's
                    // on a shared device.
                    .run { _ in offlineFileStore.removeCurrentAccount() }
                )
            }
        }
    }

    /// Re-walks the pinned roots and downloads only the files not already present offline (new files,
    /// or ones whose server `size`/`dateModified` changed so their staleness key no longer matches).
    /// `announceWhenNothingPending` shows a completion for a manual tap; an automatic sync stays silent
    /// when there is nothing new.
    private func syncPinnedRoots(state: inout State, announceWhenNothingPending: Bool) -> Effect<Action> {
        let roots = offlineFileStore.pinnedRoots()
        guard !roots.isEmpty else { return .none }
        let rootItems = roots.map(Self.fileItem(from:))
        let serverURL = state.serverURL
        let filesClient = filesClient
        let offlineFileStore = offlineFileStore
        let now = date.now
        return .run { send in
            offlineFileStore.setLastAutoSyncAt(now)
            let walk = try await Self.walk(roots: rootItems, serverURL: serverURL, filesClient: filesClient)
            let files = walk.files
            // A pinned folder the server answers 404 for was deleted there: unpin it and drop its
            // slots, which finishes the sync normally instead of leaving every later sync incomplete.
            let pinnedPaths = Set(roots.map(\.path))
            for gonePath in walk.goneFolders where pinnedPaths.contains(gonePath) {
                offlineFileStore.removeRoot(gonePath)
            }
            if walk.hasIncompleteWalk || walk.hasForbiddenFolders {
                // A folder that failed to list says nothing about its files, so never prune on a
                // partial walk: only orphans left by an unpinned root are safe to drop. A forbidden
                // folder keeps its pin and its files for the same reason.
                offlineFileStore.reconcile(nil)
            } else {
                // A complete walk of every pinned root: prune slots the server no longer lists
                // (deleted upstream) and any orphans left by an unpinned root.
                offlineFileStore.reconcile(Set(files.map(\.id)))
            }
            let pending = files.filter { offlineFileStore.localURL($0) == nil }
            guard !pending.isEmpty else {
                if walk.hasIncompleteWalk {
                    if announceWhenNothingPending {
                        await send(.waitingForNetwork)
                    } else {
                        await send(.autoSyncFailed)
                    }
                } else if walk.hasForbiddenFolders {
                    await send(announceWhenNothingPending ? .failed(Self.forbiddenMessage) : .autoSyncFailed)
                } else if announceWhenNothingPending {
                    await send(.prepared(fileCount: 0))
                    await send(.completed)
                }
                return
            }
            if Task.isCancelled {
                return
            }
            await send(.prepared(fileCount: pending.count))
            offlineFileStore.setInterrupted(true)
            await BackgroundActivity.run(name: Constants.syncTaskName) {
                await Self.runDownloads(pending, serverURL: serverURL, filesClient: filesClient, send: send)
            }
            if Task.isCancelled {
                return
            }
            await send(walk.hasForbiddenFolders && announceWhenNothingPending ? .failed(Self.forbiddenMessage) : .completed)
        } catch: { error, send in
            guard !(error is CancellationError) else { return }
            // A background sync failure stays quiet (no error banner); clear any partial progress.
            await send(.autoSyncFailed)
        }
        .cancellable(id: CancelID.download, cancelInFlight: true)
    }

    static var forbiddenMessage: String {
        FilesClientError.forbidden(message: nil).userMessage
    }

    /// Reconstructs a root `FileItem` from a manifest entry: parent + name reproduce the id, and
    /// `isDirectory` drives whether the pipeline walks it (`browse`) or downloads it directly.
    static func fileItem(from root: OfflinePinnedRoot) -> FileItem {
        FileItem(
            name: (root.path as NSString).lastPathComponent,
            path: (root.path as NSString).deletingLastPathComponent,
            dateModified: Date(),
            size: 0,
            kind: root.isDirectory ? "directory" : (root.path as NSString).pathExtension
        )
    }

    /// Merges pinned roots by path, so re-pinning a folder updates rather than duplicates its entry.
    static func mergedRoots(existing: [OfflinePinnedRoot], adding: [OfflinePinnedRoot]) -> [OfflinePinnedRoot] {
        var byPath = Dictionary(existing.map { ($0.path, $0) }, uniquingKeysWith: { _, new in new })
        for root in adding {
            byPath[root.path] = root
        }
        return Array(byPath.values)
    }

    /// Downloads `files` bounded-concurrently, replenishing the pool as each finishes, and reports
    /// progress. Already-present files return from `offlineDownloadFile` with no network, so passing a
    /// mix is cheap.
    private static func runDownloads(
        _ files: [FileItem], serverURL: URL, filesClient: FilesClient, send: Send<Action>
    ) async {
        // Start from a fresh socket: the download session may have sat idle since the last run, and a
        // reused keep alive connection the server already dropped would stall the first file until it
        // timed out.
        await filesClient.flushDownloadConnections()
        let counter = DownloadProgressCounter()
        // Progress flows through this stream and out via one forwarder task. The byte callback (already
        // throttled in the network delegate) only does a cheap synchronous `yield`, so nothing spawns
        // an unstructured task on the transfer hot path, and the sole caller of `send` is the
        // forwarder, keeping updates ordered and bounded.
        let (events, continuation) = AsyncStream<Action>.makeStream()
        await withTaskGroup(of: Void.self) { outer in
            outer.addTask {
                for await action in events {
                    await send(action)
                }
            }
            outer.addTask {
                await withTaskGroup(of: Void.self) { group in
                    var iterator = files.makeIterator()
                    var nextKey = 0
                    func addNext() -> Bool {
                        guard let file = iterator.next() else { return false }
                        let key = nextKey
                        nextKey += 1
                        group.addTask {
                            if Task.isCancelled {
                                return
                            }
                            continuation.yield(.willDownload(name: file.name))
                            let url = try? await filesClient.offlineDownloadFile(serverURL, file) { fraction in
                                if let snapshot = counter.progress(key: key, fileFraction: fraction) {
                                    continuation.yield(.progressed(filesDone: snapshot.filesDone, unitsDone: snapshot.unitsDone))
                                }
                            }
                            // A failed file (nil) still advances the bar (so it never stalls) but is
                            // not counted as done: it stays pending and the next sync retries it,
                            // instead of the run falsely reporting every file present.
                            let snapshot = counter.complete(key: key, success: url != nil)
                            continuation.yield(.progressed(filesDone: snapshot.filesDone, unitsDone: snapshot.unitsDone))
                        }
                        return true
                    }
                    for _ in 0 ..< Constants.maxConcurrentDownloads where addNext() {}
                    while await group.next() != nil {
                        if Task.isCancelled {
                            break
                        }
                        _ = addNext()
                    }
                }
                // Downloads are done (or cancelled): end the stream so the forwarder finishes.
                continuation.finish()
            }
        }
    }

    /// Depth first walk of the pinned roots into a flat list of files. Directories are expanded via
    /// `browse`. A save the user asked for passes `skipsUnreadableFolders: false` and fails instead of
    /// quietly leaving files out.
    static func enumerate(
        roots: [FileItem], serverURL: URL, filesClient: FilesClient, skipsUnreadableFolders: Bool = true
    ) async throws -> [FileItem] {
        try await walk(
            roots: roots, serverURL: serverURL, filesClient: filesClient, skipsUnreadableFolders: skipsUnreadableFolders
        ).files
    }

    /// Same walk as `enumerate`, but reports the folders that could not be listed. A folder that
    /// fails to list is skipped, not fatal, so one unreadable subfolder doesn't sink an otherwise good
    /// run, yet the result is flagged incomplete so callers never treat it as the full server state.
    static func walk(
        roots: [FileItem], serverURL: URL, filesClient: FilesClient, skipsUnreadableFolders: Bool = true
    ) async throws -> OfflineWalkResult {
        var files: [FileItem] = []
        var failedFolders: [String] = []
        var goneFolders: [String] = []
        var forbiddenFolders: [String] = []
        var seen = Set<String>()
        // A global bounded walk rather than one level at a time: up to `maxConcurrentBrowses` folder
        // listings are always in flight regardless of tree shape, so a deep or lopsided tree (a
        // narrow level feeding a wide one) never stalls the pool waiting for the slowest folder in a
        // level before starting the next. Newly found subfolders are queued and pulled in as slots
        // free up.
        var queue: [FileItem] = []
        for item in roots {
            if item.isDirectory {
                queue.append(item)
            } else if seen.insert(item.id).inserted {
                files.append(item)
            }
        }
        guard !queue.isEmpty else { return OfflineWalkResult(files: files) }
        try await withThrowingTaskGroup(of: (folder: String, outcome: FolderOutcome).self) { group in
            var active = 0
            func fill() {
                while active < Constants.maxConcurrentBrowses, let dir = queue.popLast() {
                    group.addTask {
                        guard skipsUnreadableFolders else {
                            return try await (dir.id, .items(filesClient.browse(serverURL, dir.id).items))
                        }
                        do {
                            return try await (dir.id, .items(filesClient.browse(serverURL, dir.id).items))
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            return (dir.id, FolderOutcome(failure: error))
                        }
                    }
                    active += 1
                }
            }
            fill()
            while let (folder, outcome) = try await group.next() {
                active -= 1
                try Task.checkCancellation()
                let items: [FileItem]
                switch outcome {
                case let .items(listed):
                    items = listed
                case .gone:
                    goneFolders.append(folder)
                    fill()
                    continue
                case .forbidden:
                    forbiddenFolders.append(folder)
                    fill()
                    continue
                case .failed:
                    failedFolders.append(folder)
                    fill()
                    continue
                }
                for item in items {
                    if item.isDirectory {
                        queue.append(item)
                    } else if seen.insert(item.id).inserted {
                        files.append(item)
                    }
                }
                fill()
            }
        }
        return OfflineWalkResult(
            files: files, failedFolders: failedFolders, goneFolders: goneFolders, forbiddenFolders: forbiddenFolders
        )
    }

    /// What listing one folder came to. Only offline, a timeout, a server error or an expired session
    /// leave the walk incomplete: a 404 is a folder that no longer exists, a 403 one the account may not
    /// read, and neither gets better by trying again.
    private enum FolderOutcome: Sendable {
        case items([FileItem])
        case gone
        case forbidden
        case failed

        init(failure error: Error) {
            switch error as? FilesClientError {
            case .server(statusCode: Constants.notFoundStatusCode), .serverMessage(statusCode: Constants.notFoundStatusCode, _):
                self = .gone
            case .forbidden:
                self = .forbidden
            default:
                self = .failed
            }
        }
    }
}

/// The outcome of walking pinned roots: the files found plus the folders that could not be listed,
/// split by why (see `FolderOutcome`).
struct OfflineWalkResult: Equatable {
    var files: [FileItem]
    /// Folders that could not be listed for a reason that may pass (offline, timeout, 5xx).
    var failedFolders: [String] = []
    /// Folders the server answered 404 for: deleted there.
    var goneFolders: [String] = []
    /// Folders the server answered 403 for: kept pinned, reported to the user.
    var forbiddenFolders: [String] = []

    var hasIncompleteWalk: Bool {
        !failedFolders.isEmpty
    }

    var hasForbiddenFolders: Bool {
        !forbiddenFolders.isEmpty
    }
}

/// Serialises the running progress across the concurrent download tasks, in units of files rather
/// than bytes so the bar always agrees with the "X of Y files" label. Each finished file contributes
/// a whole unit; each still running file contributes its latest fractional progress (0...1), so the
/// bar climbs smoothly through one large transfer instead of jumping only when a file finishes.
/// `filesDone` counts only successes (for the label); `unitsDone` counts every finished file including
/// failures (so a failed file still advances the bar rather than stalling it).
///
/// `@unchecked Sendable` lock-guarded class rather than an actor so the throttled progress callback
/// (already rate limited in the network delegate) can record with a cheap synchronous lock rather
/// than an `await` hop that would mean spawning a task per callback.
final class DownloadProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var completedUnits = 0
    private var successFiles = 0
    private var inflight: [Int: Double] = [:]
    private var completedKeys: Set<Int> = []

    private var currentUnits: Double {
        Double(completedUnits) + inflight.values.reduce(0, +)
    }

    /// Records a file's latest fractional progress (0...1, capped so a server over report can't push
    /// the bar past 100%). Returns `nil` for a late callback on an already completed file.
    func progress(key: Int, fileFraction: Double) -> (filesDone: Int, unitsDone: Double)? {
        lock.lock()
        defer { lock.unlock() }
        guard !completedKeys.contains(key) else { return nil }
        inflight[key] = min(max(fileFraction, 0), 1)
        return (successFiles, currentUnits)
    }

    /// Marks a file finished: drops its fractional partial and folds a whole unit into the total.
    func complete(key: Int, success: Bool) -> (filesDone: Int, unitsDone: Double) {
        lock.lock()
        defer { lock.unlock() }
        inflight[key] = nil
        completedKeys.insert(key)
        completedUnits += 1
        if success {
            successFiles += 1
        }
        return (successFiles, currentUnits)
    }
}
