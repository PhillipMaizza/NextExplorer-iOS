import CoreModels
import CryptoKit
import Dependencies
import Foundation

/// Filesystem layout for the durable offline store, shared by `OfflineFileStore` (the feature
/// facing dependency) and `FilesService` (the offline first read path + the download writer). Unlike
/// the ephemeral `PreviewCache` under `Caches`, offline pins live under Application Support so the OS
/// never purges them under storage pressure, and the app's own LRU evictor never touches them: a
/// pinned file must still be there when the user is offline.
///
/// Everything is scoped by `CacheAccountScope.current`, so two accounts on one device never serve or
/// count each other's pinned files. `removeAll` drops every scope at once, for the session boundary
/// clears (rule #11).
enum OfflineCache {
    static let rootDirectoryName = "OfflineFiles"
    static let slotsDirectoryName = "slots"
    static let manifestFileName = "manifest.json"
    static let metaSidecarName = ".meta"
    /// Records the original item path in each slot so the store can map an opaque hashed slot back to
    /// its file, for per-root sizing, per-root removal and orphan reconciliation without a network walk.
    static let pathSidecarName = ".path"
    static let interruptedFileName = ".interrupted"
    static let lastSyncFileName = ".lastsync"

    private static func applicationSupport() -> URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
    }

    static func root() -> URL? {
        applicationSupport()?.appendingPathComponent(rootDirectoryName, isDirectory: true)
    }

    private static func hex(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The current account's offline area. Created (and hardened: encrypted at rest, excluded from
    /// backup, since a pinned file is the user's data) on first use.
    static func scopeDirectory(create: Bool) -> URL? {
        guard let rootURL = root() else { return nil }
        let directory = rootURL.appendingPathComponent(hex(CacheAccountScope.current), isDirectory: true)
        guard create else { return directory }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        var mutable = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutable.setResourceValues(values)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: directory.path
        )
        return directory
    }

    private static func slotDirectory(forPath path: String, create: Bool) -> URL? {
        guard let scope = scopeDirectory(create: create) else { return nil }
        return scope
            .appendingPathComponent(slotsDirectoryName, isDirectory: true)
            .appendingPathComponent(hex(path), isDirectory: true)
    }

    private static func fileName(forPath path: String) -> String {
        SafeFileName.component((path as NSString).lastPathComponent)
    }

    static func metaValue(dateModified: Date, size: Int64) -> String {
        "\(dateModified.timeIntervalSince1970)|\(size)"
    }

    /// Slot (directory, the raw file, its staleness sidecar) for `item`. RAW images keep the
    /// original extension here (unlike the preview cache): offline pins download the verbatim file
    /// via `POST /api/download`, and `CGImageSource` decodes RAW natively.
    static func slot(for item: FileItem, create: Bool) -> (directory: URL, fileURL: URL, metaURL: URL)? {
        guard let directory = slotDirectory(forPath: item.id, create: create) else { return nil }
        return (
            directory,
            directory.appendingPathComponent(fileName(forPath: item.id)),
            directory.appendingPathComponent(metaSidecarName)
        )
    }

    /// The pinned copy of `item` if present and still matching the server's `dateModified|size`,
    /// else nil. Pure disk check, no network.
    static func localURL(for item: FileItem) -> URL? {
        guard let slot = slot(for: item, create: false),
              FileManager.default.fileExists(atPath: slot.fileURL.path),
              let meta = try? String(contentsOf: slot.metaURL, encoding: .utf8),
              meta == metaValue(dateModified: item.dateModified, size: item.size)
        else { return nil }
        return slot.fileURL
    }

    /// The pinned copy for `path` regardless of freshness, for the offline text read path which has
    /// no `FileItem` to check the staleness sidecar against. Only consulted as an offline fallback.
    static func localURL(forPath path: String) -> URL? {
        guard let directory = slotDirectory(forPath: path, create: false) else { return nil }
        let fileURL = directory.appendingPathComponent(fileName(forPath: path))
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    /// Lands the freshly downloaded bytes at `item`'s slot with a matching staleness sidecar,
    /// replacing any earlier copy. Both files inherit the encrypted at rest protection class.
    static func store(downloadedURL: URL, item: FileItem) throws -> URL {
        guard let slot = slot(for: item, create: true) else {
            throw FilesClientError.decoding("Could not open the offline store.")
        }
        try FileManager.default.createDirectory(at: slot.directory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: slot.fileURL)
        try FileManager.default.moveItem(at: downloadedURL, to: slot.fileURL)
        try metaValue(dateModified: item.dateModified, size: item.size)
            .write(to: slot.metaURL, atomically: true, encoding: .utf8)
        let pathURL = slot.directory.appendingPathComponent(pathSidecarName)
        try? item.id.write(to: pathURL, atomically: true, encoding: .utf8)
        for url in [slot.fileURL, slot.metaURL, pathURL] {
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path
            )
        }
        return slot.fileURL
    }

    /// Total bytes of the actual downloaded files, from the slot data files only. Deliberately not a
    /// walk of the whole scope directory, which would also count the manifest, the per-slot `.meta` /
    /// `.path` sidecars and the `.lastsync` / `.interrupted` markers, so removing everything would
    /// still report a few stray metadata bytes.
    static func totalSizeBytes() -> Int64 {
        slotEntries().reduce(Int64(0)) { $0 + $1.size }
    }

    private static func slotExists(forPath path: String) -> Bool {
        guard let directory = slotDirectory(forPath: path, create: false) else { return false }
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName(forPath: path)).path)
    }

    static func pinnedRoots() -> [OfflinePinnedRoot] {
        guard let scope = scopeDirectory(create: false) else { return [] }
        let manifestURL = scope.appendingPathComponent(manifestFileName)
        guard let data = try? Data(contentsOf: manifestURL) else { return [] }
        if let roots = try? JSONDecoder().decode([OfflinePinnedRoot].self, from: data) {
            return roots
        }
        // Legacy manifest stored a flat `[String]` of paths; migrate by inferring directory from the
        // absence of a file slot (only files get their own slot; a folder pin has none).
        if let paths = try? JSONDecoder().decode([String].self, from: data) {
            return paths.map { OfflinePinnedRoot(path: $0, isDirectory: !slotExists(forPath: $0)) }
        }
        return []
    }

    static func setPinnedRoots(_ roots: [OfflinePinnedRoot]) {
        guard let scope = scopeDirectory(create: true) else { return }
        let manifestURL = scope.appendingPathComponent(manifestFileName)
        guard let data = try? JSONEncoder().encode(roots) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    /// Wipes every account's offline files. Called only at genuine session boundaries (logout, full
    /// teardown, fresh sign in) where no other account stays active, mirroring the other cache
    /// stores' `clearAll` (rule #11).
    static func removeAll() {
        guard let rootURL = root(), FileManager.default.fileExists(atPath: rootURL.path) else { return }
        try? FileManager.default.removeItem(at: rootURL)
    }

    /// Wipes only the active account's offline files (its slots and manifest), for the Settings
    /// "Remove Offline Files" action, so removing on one account never touches another account's
    /// pinned files on a shared device.
    static func removeCurrentScope() {
        guard let scope = scopeDirectory(create: false), FileManager.default.fileExists(atPath: scope.path) else { return }
        try? FileManager.default.removeItem(at: scope)
    }

    private static func slotsRoot(create: Bool) -> URL? {
        scopeDirectory(create: create)?.appendingPathComponent(slotsDirectoryName, isDirectory: true)
    }

    /// Every stored slot as `(originalPath, sizeBytes)`, read from the `.path` sidecar and the slot's
    /// data file. Backs per-root sizing, per-root removal and orphan reconciliation.
    static func slotEntries() -> [(path: String, size: Int64)] {
        guard let slotsRoot = slotsRoot(create: false),
              let slotDirs = try? FileManager.default.contentsOfDirectory(
                  at: slotsRoot, includingPropertiesForKeys: nil
              )
        else { return [] }
        var entries: [(String, Int64)] = []
        for slotDir in slotDirs {
            guard let path = try? String(contentsOf: slotDir.appendingPathComponent(pathSidecarName), encoding: .utf8) else { continue }
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: slotDir, includingPropertiesForKeys: [.fileSizeKey]
            )) ?? []
            let size = contents
                .filter { $0.lastPathComponent != metaSidecarName && $0.lastPathComponent != pathSidecarName }
                .reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
            entries.append((path, size))
        }
        return entries
    }

    private static func isCovered(_ path: String, byRootPaths roots: [String]) -> Bool {
        roots.contains { $0 == path || path.hasPrefix($0 + "/") }
    }

    /// Total offline bytes for each pinned root, for the manage screen.
    static func pinnedRootUsages() -> [OfflinePinnedRootUsage] {
        let roots = pinnedRoots()
        let entries = slotEntries()
        return roots.map { root in
            let size = entries
                .filter { $0.path == root.path || $0.path.hasPrefix(root.path + "/") }
                .reduce(Int64(0)) { $0 + $1.size }
            return OfflinePinnedRootUsage(root: root, sizeBytes: size)
        }
    }

    private static func removeSlot(forPath path: String) {
        guard let directory = slotDirectory(forPath: path, create: false) else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    /// Unpins one root: drops it from the manifest, then deletes any slots no longer covered by a
    /// remaining root (freeing that root's disk unless another pin still covers those files).
    static func removeRoot(path rootPath: String) {
        setPinnedRoots(pinnedRoots().filter { $0.path != rootPath })
        reconcile(currentPaths: nil)
    }

    /// Prunes stale slots: any not covered by a pinned root (an orphan from an unpinned root), and,
    /// when `currentPaths` is supplied from a fresh sync, any covered file the server no longer lists
    /// (deleted upstream). `currentPaths` nil does orphan cleanup only.
    static func reconcile(currentPaths: Set<String>?) {
        let rootPaths = pinnedRoots().map(\.path)
        for entry in slotEntries() {
            let covered = isCovered(entry.path, byRootPaths: rootPaths)
            if !covered {
                removeSlot(forPath: entry.path)
            } else if let currentPaths, !currentPaths.contains(entry.path) {
                removeSlot(forPath: entry.path)
            }
        }
    }

    private static func flagURL(_ name: String) -> URL? {
        scopeDirectory(create: true)?.appendingPathComponent(name)
    }

    /// A run in progress marker, set when a download starts and cleared on completion, so the next
    /// launch can show a "resuming" state (and auto-sync) after an app kill mid download.
    static func setInterrupted(_ value: Bool) {
        guard let url = flagURL(interruptedFileName) else { return }
        if value {
            try? Data().write(to: url)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func wasInterrupted() -> Bool {
        guard let url = flagURL(interruptedFileName) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func lastAutoSyncAt() -> Date? {
        guard let url = flagURL(lastSyncFileName),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let seconds = Double(text)
        else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    static func setLastAutoSyncAt(_ date: Date) {
        guard let url = flagURL(lastSyncFileName) else { return }
        try? String(date.timeIntervalSince1970).write(to: url, atomically: true, encoding: .utf8)
    }
}

/// One pinned root plus how much of the offline store it accounts for, for the manage screen.
public struct OfflinePinnedRootUsage: Equatable, Sendable, Identifiable {
    public let root: OfflinePinnedRoot
    public let sizeBytes: Int64

    public var id: String {
        root.path
    }

    public init(root: OfflinePinnedRoot, sizeBytes: Int64) {
        self.root = root
        self.sizeBytes = sizeBytes
    }
}

/// A folder or file the user pinned for offline use, as recorded in the manifest. `isDirectory` lets
/// a re-sync know whether to walk it (`browse`) or download it directly, without a network probe.
public struct OfflinePinnedRoot: Codable, Equatable, Sendable {
    public let path: String
    public let isDirectory: Bool

    public init(path: String, isDirectory: Bool) {
        self.path = path
        self.isDirectory = isDirectory
    }
}

/// Feature facing handle to the durable offline store. Reads (`localURL`) are also done inside
/// `FilesService` so `previewFile` / `downloadRawFile` / streaming serve a pinned copy transparently;
/// this dependency covers what a feature drives directly: the pinned manifest, the total size for the
/// Settings display, and the session boundary wipe.
public struct OfflineFileStore: Sendable {
    public var localURL: @Sendable (_ item: FileItem) -> URL?
    /// A pinned copy for `item`'s path regardless of the `dateModified|size` staleness check. For
    /// callers that open a file from a placeholder `FileItem` with no real metadata (a search or a
    /// Favorites direct open), where the strict `localURL` check can't match: the pinned copy is the
    /// user's intended offline file, so it's served over streaming rather than failing offline.
    public var localURLIgnoringStaleness: @Sendable (_ item: FileItem) -> URL?
    public var pinnedRoots: @Sendable () -> [OfflinePinnedRoot]
    public var setPinnedRoots: @Sendable (_ roots: [OfflinePinnedRoot]) -> Void
    public var totalSizeBytes: @Sendable () -> Int64
    /// Per-root offline usage, for the manage screen.
    public var pinnedRootUsages: @Sendable () -> [OfflinePinnedRootUsage]
    /// Unpin one root (manifest + its slots), for per-root removal.
    public var removeRoot: @Sendable (_ path: String) -> Void
    /// Prune stale slots: orphans, and (with a fresh listing) server-deleted files.
    public var reconcile: @Sendable (_ currentPaths: Set<String>?) -> Void
    /// Every account's offline files. Session boundaries only (rule #11).
    public var removeAll: @Sendable () -> Void
    /// Only the active account's offline files, for the Settings "Remove Offline Files" action.
    public var removeCurrentAccount: @Sendable () -> Void
    /// "A download was in progress" marker, for a resuming state after an app kill.
    public var setInterrupted: @Sendable (_ value: Bool) -> Void
    public var wasInterrupted: @Sendable () -> Bool
    /// When the last auto-sync ran, so foreground syncs can be throttled.
    public var lastAutoSyncAt: @Sendable () -> Date?
    public var setLastAutoSyncAt: @Sendable (_ date: Date) -> Void

    public init(
        localURL: @escaping @Sendable (FileItem) -> URL?,
        localURLIgnoringStaleness: @escaping @Sendable (FileItem) -> URL?,
        pinnedRoots: @escaping @Sendable () -> [OfflinePinnedRoot],
        setPinnedRoots: @escaping @Sendable ([OfflinePinnedRoot]) -> Void,
        totalSizeBytes: @escaping @Sendable () -> Int64,
        pinnedRootUsages: @escaping @Sendable () -> [OfflinePinnedRootUsage],
        removeRoot: @escaping @Sendable (String) -> Void,
        reconcile: @escaping @Sendable (Set<String>?) -> Void,
        removeAll: @escaping @Sendable () -> Void,
        removeCurrentAccount: @escaping @Sendable () -> Void,
        setInterrupted: @escaping @Sendable (Bool) -> Void,
        wasInterrupted: @escaping @Sendable () -> Bool,
        lastAutoSyncAt: @escaping @Sendable () -> Date?,
        setLastAutoSyncAt: @escaping @Sendable (Date) -> Void
    ) {
        self.localURL = localURL
        self.localURLIgnoringStaleness = localURLIgnoringStaleness
        self.pinnedRoots = pinnedRoots
        self.setPinnedRoots = setPinnedRoots
        self.totalSizeBytes = totalSizeBytes
        self.pinnedRootUsages = pinnedRootUsages
        self.removeRoot = removeRoot
        self.reconcile = reconcile
        self.removeAll = removeAll
        self.removeCurrentAccount = removeCurrentAccount
        self.setInterrupted = setInterrupted
        self.wasInterrupted = wasInterrupted
        self.lastAutoSyncAt = lastAutoSyncAt
        self.setLastAutoSyncAt = setLastAutoSyncAt
    }
}

extension OfflineFileStore: DependencyKey {
    public static let liveValue = OfflineFileStore(
        localURL: { OfflineCache.localURL(for: $0) },
        localURLIgnoringStaleness: { OfflineCache.localURL(forPath: $0.id) },
        pinnedRoots: { OfflineCache.pinnedRoots() },
        setPinnedRoots: { OfflineCache.setPinnedRoots($0) },
        totalSizeBytes: { OfflineCache.totalSizeBytes() },
        pinnedRootUsages: { OfflineCache.pinnedRootUsages() },
        removeRoot: { OfflineCache.removeRoot(path: $0) },
        reconcile: { OfflineCache.reconcile(currentPaths: $0) },
        removeAll: { OfflineCache.removeAll() },
        removeCurrentAccount: { OfflineCache.removeCurrentScope() },
        setInterrupted: { OfflineCache.setInterrupted($0) },
        wasInterrupted: { OfflineCache.wasInterrupted() },
        lastAutoSyncAt: { OfflineCache.lastAutoSyncAt() },
        setLastAutoSyncAt: { OfflineCache.setLastAutoSyncAt($0) }
    )

    /// No pinned files, no manifest — tests that exercise the offline read path inject a seeded
    /// variant instead (see `.inMemory`).
    public static let testValue = OfflineFileStore(
        localURL: { _ in nil },
        localURLIgnoringStaleness: { _ in nil },
        pinnedRoots: { [] },
        setPinnedRoots: { _ in },
        totalSizeBytes: { 0 },
        pinnedRootUsages: { [] },
        removeRoot: { _ in },
        reconcile: { _ in },
        removeAll: {},
        removeCurrentAccount: {},
        setInterrupted: { _ in },
        wasInterrupted: { false },
        lastAutoSyncAt: { nil },
        setLastAutoSyncAt: { _ in }
    )

    public static let previewValue = OfflineFileStore.testValue

    /// An in-memory store for tests: `setPinnedRoots` is readable back through `pinnedRoots`, and a
    /// caller can seed `localURL` hits by path.
    public static func inMemory(localURLs: [String: URL] = [:]) -> OfflineFileStore {
        let box = InMemoryBox(localURLs: localURLs)
        return OfflineFileStore(
            localURL: { box.localURL(for: $0.id) },
            localURLIgnoringStaleness: { box.localURL(for: $0.id) },
            pinnedRoots: { box.pinnedRoots() },
            setPinnedRoots: { box.setPinnedRoots($0) },
            totalSizeBytes: { 0 },
            pinnedRootUsages: { box.pinnedRoots().map { OfflinePinnedRootUsage(root: $0, sizeBytes: 0) } },
            removeRoot: { box.removeRoot(path: $0) },
            reconcile: { _ in },
            removeAll: { box.removeAll() },
            removeCurrentAccount: { box.removeAll() },
            setInterrupted: { box.setInterrupted($0) },
            wasInterrupted: { box.wasInterrupted() },
            lastAutoSyncAt: { box.lastAutoSyncAt() },
            setLastAutoSyncAt: { box.setLastAutoSyncAt($0) }
        )
    }

    private final class InMemoryBox: @unchecked Sendable {
        private let lock = NSLock()
        private var roots: [OfflinePinnedRoot] = []
        private var interrupted = false
        private var lastSync: Date?
        private let localURLs: [String: URL]

        init(localURLs: [String: URL]) {
            self.localURLs = localURLs
        }

        func localURL(for path: String) -> URL? {
            lock.lock(); defer { lock.unlock() }
            return localURLs[path]
        }

        func pinnedRoots() -> [OfflinePinnedRoot] {
            lock.lock(); defer { lock.unlock() }
            return roots
        }

        func setPinnedRoots(_ newRoots: [OfflinePinnedRoot]) {
            lock.lock(); defer { lock.unlock() }
            roots = newRoots
        }

        func removeRoot(path: String) {
            lock.lock(); defer { lock.unlock() }
            roots.removeAll { $0.path == path }
        }

        func removeAll() {
            lock.lock(); defer { lock.unlock() }
            roots = []
        }

        func setInterrupted(_ value: Bool) {
            lock.lock(); defer { lock.unlock() }
            interrupted = value
        }

        func wasInterrupted() -> Bool {
            lock.lock(); defer { lock.unlock() }
            return interrupted
        }

        func lastAutoSyncAt() -> Date? {
            lock.lock(); defer { lock.unlock() }
            return lastSync
        }

        func setLastAutoSyncAt(_ date: Date) {
            lock.lock(); defer { lock.unlock() }
            lastSync = date
        }
    }
}

public extension DependencyValues {
    var offlineFileStore: OfflineFileStore {
        get { self[OfflineFileStore.self] }
        set { self[OfflineFileStore.self] = newValue }
    }
}
