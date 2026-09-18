import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Localization

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

        public init(serverURL: URL = URL(fileURLWithPath: "/")) {
            self.serverURL = serverURL
        }
    }

    public enum Action: Sendable {
        /// Start (or add to) an offline download for the chosen roots. Folders are walked
        /// recursively; files are downloaded directly.
        case startDownload([FileItem])
        case prepared(fileCount: Int, totalBytes: Int64)
        case willDownload(name: String)
        case didDownload(bytesDone: Int64, filesDone: Int)
        case completed
        case failed(String)
        case cancelTapped
        case removeAllOfflineTapped
        /// Manual "Update Offline Files": re-walk the pinned roots and download only the new/changed
        /// files. Shows progress and a completion even when nothing needed downloading.
        case resyncTapped
        /// Automatic sync on app open / foreground / reconnect: same as `resyncTapped` but silent —
        /// it only surfaces progress if there is actually something new to download, so a launch with
        /// nothing changed shows nothing. `force` bypasses the foreground throttle (used on reconnect).
        case autoSync(force: Bool)
        /// A background sync failed; clear any progress it was showing without an error banner.
        case autoSyncFailed
    }

    @Dependency(\.filesClient) var filesClient
    @Dependency(\.offlineFileStore) var offlineFileStore
    @Dependency(\.date) var date

    private enum Constants {
        /// How many files download at once. Enough to saturate a typical connection without opening
        /// so many sockets that each transfer crawls or the server rate limits.
        static let maxConcurrentDownloads = 4
        static let downloadTaskName = "OfflineDownload"
        static let syncTaskName = "OfflineSync"
        /// Minimum gap between automatic foreground syncs, so re-walking every pinned folder doesn't
        /// run on every quick app switch. A reconnect or a manual update bypasses it.
        static let autoSyncMinInterval: TimeInterval = 300
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
                let newRoots = roots.map { OfflinePinnedRoot(path: $0.id, isDirectory: $0.isDirectory) }
                return .run { send in
                    // Record the pins up front, so an interrupted run (app killed mid download) keeps
                    // its roots and a later sync resumes the missing files instead of losing them.
                    offlineFileStore.setPinnedRoots(Self.mergedRoots(existing: existingRoots, adding: newRoots))

                    let files = try await Self.enumerate(roots: roots, serverURL: serverURL, filesClient: filesClient)
                    let totalBytes = files.reduce(Int64(0)) { $0 + $1.size }
                    await send(.prepared(fileCount: files.count, totalBytes: totalBytes))
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
                state.$progress.withLock {
                    $0 = OfflineDownloadProgress()
                    $0.phase = .preparing
                }
                return syncPinnedRoots(state: &state, announceWhenNothingPending: true)

            case let .autoSync(force):
                // Never stomp a run already in progress (a manual download, or an earlier auto-sync).
                guard !state.progress.isActive else { return .none }
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

            case let .prepared(fileCount, totalBytes):
                state.$progress.withLock {
                    $0.phase = .downloading
                    $0.filesTotal = fileCount
                    $0.bytesTotal = totalBytes
                }
                return .none

            case let .willDownload(name):
                state.$progress.withLock { $0.currentName = name }
                return .none

            case let .didDownload(bytesDone, filesDone):
                state.$progress.withLock {
                    $0.bytesDone = bytesDone
                    $0.filesDone = filesDone
                }
                return .none

            case .completed:
                offlineFileStore.setInterrupted(false)
                state.$progress.withLock {
                    $0.phase = .completed
                    $0.currentName = ""
                    $0.bytesDone = $0.bytesTotal
                    $0.filesDone = $0.filesTotal
                }
                return .none

            case let .failed(message):
                offlineFileStore.setInterrupted(false)
                state.$progress.withLock { $0.phase = .failed(message) }
                return .none

            case .cancelTapped:
                offlineFileStore.setInterrupted(false)
                state.$progress.withLock { $0 = OfflineDownloadProgress() }
                return .cancel(id: CancelID.download)

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
            let files = try await Self.enumerate(roots: rootItems, serverURL: serverURL, filesClient: filesClient)
            // A complete walk of every pinned root: prune slots the server no longer lists (deleted
            // upstream) and any orphans left by an unpinned root.
            offlineFileStore.reconcile(Set(files.map(\.id)))
            let pending = files.filter { offlineFileStore.localURL($0) == nil }
            guard !pending.isEmpty else {
                if announceWhenNothingPending {
                    await send(.prepared(fileCount: 0, totalBytes: 0))
                    await send(.completed)
                }
                return
            }
            if Task.isCancelled {
                return
            }
            let totalBytes = pending.reduce(Int64(0)) { $0 + $1.size }
            await send(.prepared(fileCount: pending.count, totalBytes: totalBytes))
            offlineFileStore.setInterrupted(true)
            await BackgroundActivity.run(name: Constants.syncTaskName) {
                await Self.runDownloads(pending, serverURL: serverURL, filesClient: filesClient, send: send)
            }
            if Task.isCancelled {
                return
            }
            await send(.completed)
        } catch: { error, send in
            guard !(error is CancellationError) else { return }
            // A background sync failure stays quiet (no error banner); clear any partial progress.
            await send(.autoSyncFailed)
        }
        .cancellable(id: CancelID.download, cancelInFlight: true)
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
        let counter = DownloadProgressCounter()
        await withTaskGroup(of: Void.self) { group in
            var iterator = files.makeIterator()
            func addNext() -> Bool {
                guard let file = iterator.next() else { return false }
                group.addTask {
                    if Task.isCancelled {
                        return
                    }
                    await send(.willDownload(name: file.name))
                    _ = try? await filesClient.offlineDownloadFile(serverURL, file)
                    let snapshot = await counter.record(bytes: file.size)
                    await send(.didDownload(bytesDone: snapshot.bytes, filesDone: snapshot.files))
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
    }

    /// Depth first walk of the pinned roots into a flat list of files. Directories are expanded via
    /// `browse`; a folder that fails to list is skipped rather than aborting the whole run, so one
    /// unreadable subfolder doesn't sink an otherwise good sync.
    private static func enumerate(
        roots: [FileItem], serverURL: URL, filesClient: FilesClient
    ) async throws -> [FileItem] {
        var files: [FileItem] = []
        var stack = roots
        while let item = stack.popLast() {
            try Task.checkCancellation()
            if item.isDirectory {
                if let result = try? await filesClient.browse(serverURL, item.id) {
                    stack.append(contentsOf: result.items)
                }
            } else {
                files.append(item)
            }
        }
        return files
    }
}

/// Serialises the running byte/file totals across the concurrent download tasks so each completion
/// reports a consistent cumulative snapshot.
private actor DownloadProgressCounter {
    private var bytes: Int64 = 0
    private var files = 0

    func record(bytes newBytes: Int64) -> (bytes: Int64, files: Int) {
        bytes += newBytes
        files += 1
        return (bytes, files)
    }
}
