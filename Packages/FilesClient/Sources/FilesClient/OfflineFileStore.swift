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
/// Everything is scoped by `CacheAccountScope.current` (or the scope an operation captured when it started), so two
/// accounts on one device never serve or
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
    static let listingsDirectoryName = "listings"
    static let interruptedFileName = ".interrupted"
    static let lastSyncFileName = ".lastsync"
    /// How many syncs in a row the server answered "not found" for a pinned folder, by path.
    private static let pathSeparator = "/"

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
    static func scopeDirectory(create: Bool, scope: String = CacheAccountScope.current) -> URL? {
        guard let rootURL = root() else { return nil }
        let directory = rootURL.appendingPathComponent(hex(scope), isDirectory: true)
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

    private static func slotDirectory(
        forPath path: String,
        create: Bool,
        scope: String = CacheAccountScope.current
    ) -> URL? {
        guard let scopeURL = scopeDirectory(create: create, scope: scope) else { return nil }
        return scopeURL
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
    static func slot(
        for item: FileItem, create: Bool, scope: String = CacheAccountScope.current
    ) -> (directory: URL, fileURL: URL, metaURL: URL)? {
        guard let directory = slotDirectory(forPath: item.id, create: create, scope: scope) else { return nil }
        return (
            directory,
            directory.appendingPathComponent(fileName(forPath: item.id)),
            directory.appendingPathComponent(metaSidecarName)
        )
    }

    /// The pinned copy of `item` if present and still matching the server's `dateModified|size`,
    /// else nil. Pure disk check, no network.
    static func localURL(for item: FileItem, scope: String = CacheAccountScope.current) -> URL? {
        guard let slot = slot(for: item, create: false, scope: scope),
              FileManager.default.fileExists(atPath: slot.fileURL.path),
              let meta = try? String(contentsOf: slot.metaURL, encoding: .utf8),
              meta == metaValue(dateModified: item.dateModified, size: item.size)
        else { return nil }
        return slot.fileURL
    }

    /// The pinned copy for `path` regardless of freshness, for the offline text read path which has
    /// no `FileItem` to check the staleness sidecar against. Only consulted as an offline fallback.
    static func localURL(forPath path: String, scope: String = CacheAccountScope.current) -> URL? {
        guard let directory = slotDirectory(forPath: path, create: false, scope: scope) else { return nil }
        let fileURL = directory.appendingPathComponent(fileName(forPath: path))
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    /// Lands the freshly downloaded bytes at `item`'s slot with a matching staleness sidecar,
    /// replacing any earlier copy. Every file carries the protection class, and a failed write leaves no half slot
    /// behind.
    static func store(downloadedURL: URL, item: FileItem, scope: String = CacheAccountScope.current) throws -> URL {
        guard let slot = slot(for: item, create: true, scope: scope) else {
            throw FilesClientError.decoding("Could not open the offline store.")
        }
        try FileManager.default.createDirectory(at: slot.directory, withIntermediateDirectories: true)
        let pathURL = slot.directory.appendingPathComponent(pathSidecarName)
        do {
            try item.id.write(to: pathURL, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(at: slot.fileURL)
            try FileManager.default.moveItem(at: downloadedURL, to: slot.fileURL)
            try metaValue(dateModified: item.dateModified, size: item.size)
                .write(to: slot.metaURL, atomically: true, encoding: .utf8)
        } catch {
            // A slot without its path sidecar could never be listed, sized or reconciled.
            try? FileManager.default.removeItem(at: slot.directory)
            throw error
        }
        FileProtection.apply(to: [slot.directory, slot.fileURL, slot.metaURL, pathURL])
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
        FileProtection.apply(to: manifestURL)
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
        guard let scope = scopeDirectory(create: false),
              FileManager.default.fileExists(atPath: scope.path) else { return }
        try? FileManager.default.removeItem(at: scope)
    }

    /// Wipes one named account's offline files, for removing an account that is not (or no longer)
    /// the active scope while other accounts stay signed in.
    static func removeScope(_ scope: String) {
        guard let rootURL = root() else { return }
        let directory = rootURL.appendingPathComponent(hex(scope), isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try? FileManager.default.removeItem(at: directory)
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
            guard let path = try? String(contentsOf: slotDir.appendingPathComponent(pathSidecarName), encoding: .utf8)
            else { continue }
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

    private static func listingsDirectory(create: Bool) -> URL? {
        scopeDirectory(create: create)?.appendingPathComponent(listingsDirectoryName, isDirectory: true)
    }

    /// A pinned folder's listing is kept with its files, so it can be browsed offline whether or not
    /// the shared listing cache (which evicts) still holds it.
    static func saveListing(_ directory: CachedDirectory) {
        guard let folder = listingsDirectory(create: true) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(directory) else { return }
        let url = folder.appendingPathComponent(hex(directory.path) + ".json")
        try? data.write(to: url, options: .atomic)
        FileProtection.apply(to: [folder, url])
    }

    static func listing(forPath path: String) -> CachedDirectory? {
        guard let folder = listingsDirectory(create: false),
              let data = try? Data(contentsOf: folder.appendingPathComponent(hex(path) + ".json")),
              let directory = try? JSONDecoder().decode(CachedDirectory.self, from: data),
              directory.schemaVersion == CachedDirectory.currentSchemaVersion
        else { return nil }
        return directory
    }

    /// Drops the listings of folders no pinned root covers any more (an unpinned root's folders).
    private static func pruneListings(rootPaths: [String]) {
        guard let folder = listingsDirectory(create: false),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return }
        for file in files {
            let directory = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(
                CachedDirectory.self,
                from: $0
            ) }
            guard let directory, isCovered(directory.path, byRootPaths: rootPaths) else {
                try? FileManager.default.removeItem(at: file)
                continue
            }
        }
    }

    private static func isCovered(_ path: String, byRootPaths roots: [String]) -> Bool {
        roots.contains { $0 == path || path.hasPrefix($0 + pathSeparator) }
    }

    /// Total offline bytes for each pinned root, for the manage screen.
    static func pinnedRootUsages() -> [OfflinePinnedRootUsage] {
        let roots = pinnedRoots()
        let entries = slotEntries()
        return roots.map { root in
            let size = entries
                .filter { $0.path == root.path || $0.path.hasPrefix(root.path + pathSeparator) }
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

    /// The server size and modified date the pinned copy of `path` was saved with, read from its
    /// staleness key; nil when none is stored or the key is unreadable.
    static func copyMetadata(forPath path: String) -> OfflineCopyMetadata? {
        guard let directory = slotDirectory(forPath: path, create: false),
              let meta = try? String(contentsOf: directory.appendingPathComponent(metaSidecarName), encoding: .utf8)
        else { return nil }
        let parts = meta.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let seconds = TimeInterval(parts[0]), let size = Int64(parts[1]) else { return nil }
        return OfflineCopyMetadata(dateModified: Date(timeIntervalSince1970: seconds), size: size)
    }

    /// Size of the pinned copy for `path` regardless of freshness, or nil when none is stored.
    static func localFileSize(forPath path: String) -> Int64? {
        guard let url = localURL(forPath: path),
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        else { return nil }
        return Int64(size)
    }

    /// Prunes stale slots: any not covered by a pinned root (an orphan from an unpinned root), and,
    /// when `currentPaths` is supplied from a fresh sync, any covered file the server no longer lists
    /// (deleted upstream). `currentPaths` nil does orphan cleanup only.
    static func reconcile(currentPaths: Set<String>?) {
        let rootPaths = pinnedRoots().map(\.path)
        pruneListings(rootPaths: rootPaths)
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
            FileProtection.apply(to: url)
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
        FileProtection.apply(to: url)
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
/// What a pinned copy was saved with: the server's modified date and size at that moment.
public struct OfflineCopyMetadata: Equatable, Sendable {
    public let dateModified: Date
    public let size: Int64

    public init(dateModified: Date, size: Int64) {
        self.dateModified = dateModified
        self.size = size
    }
}

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
    /// One named account's offline files, for removing an account while others stay signed in.
    public var removeAccount: @Sendable (_ scope: String) -> Void
    /// "A download was in progress" marker, for a resuming state after an app kill.
    public var setInterrupted: @Sendable (_ value: Bool) -> Void
    public var wasInterrupted: @Sendable () -> Bool
    /// When the last auto-sync ran, so foreground syncs can be throttled.
    public var lastAutoSyncAt: @Sendable () -> Date?
    public var setLastAutoSyncAt: @Sendable (_ date: Date) -> Void
    /// Size in bytes of the pinned copy for a path, or nil when none is stored. Lets the editor
    /// refuse an offline copy larger than its own cap before reading it.
    public var localFileSize: @Sendable (_ path: String) -> Int64?
    /// The metadata a pinned file was saved with, so an item opened with none (a search hit) can match it.
    public var copyMetadata: @Sendable (_ path: String) -> OfflineCopyMetadata?
    /// Keeps a pinned folder's listing with its files (written by the offline sync).
    public var saveListing: @Sendable (_ directory: CachedDirectory) -> Void
    /// A pinned folder's kept listing, for browsing it with no network.
    public var listing: @Sendable (_ path: String) -> CachedDirectory?

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
        removeAccount: @escaping @Sendable (String) -> Void = { _ in },
        setInterrupted: @escaping @Sendable (Bool) -> Void,
        wasInterrupted: @escaping @Sendable () -> Bool,
        lastAutoSyncAt: @escaping @Sendable () -> Date?,
        setLastAutoSyncAt: @escaping @Sendable (Date) -> Void,
        localFileSize: @escaping @Sendable (String) -> Int64? = { _ in nil },
        copyMetadata: @escaping @Sendable (String) -> OfflineCopyMetadata? = { _ in nil },
        saveListing: @escaping @Sendable (CachedDirectory) -> Void = { _ in },
        listing: @escaping @Sendable (String) -> CachedDirectory? = { _ in nil }
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
        self.removeAccount = removeAccount
        self.setInterrupted = setInterrupted
        self.wasInterrupted = wasInterrupted
        self.lastAutoSyncAt = lastAutoSyncAt
        self.setLastAutoSyncAt = setLastAutoSyncAt
        self.localFileSize = localFileSize
        self.copyMetadata = copyMetadata
        self.saveListing = saveListing
        self.listing = listing
    }
}

public extension OfflineFileStore {
    /// `item` as the pinned copy knows it: a file opened from a search hit has no real size or date, so
    /// it could never match the copy kept offline. With the copy's own size and date it does, and the
    /// copy opens first, online or not. An item with no pinned copy comes back unchanged.
    func matchingPinnedCopy(_ item: FileItem) -> FileItem {
        guard !item.isDirectory, let metadata = copyMetadata(item.id) else { return item }
        return FileItem(
            name: item.name,
            path: item.path,
            dateModified: metadata.dateModified,
            size: metadata.size,
            kind: item.kind,
            supportsThumbnail: item.supportsThumbnail
        )
    }

    /// This store with every call made under `scope`, so work that started for one account keeps
    /// reading and writing that account's offline files after the active account changes.
    func pinned(to scope: String) -> OfflineFileStore {
        let store = self
        return OfflineFileStore(
            localURL: { item in CacheAccountScope.withPinned(scope) { store.localURL(item) } },
            localURLIgnoringStaleness: { item in
                CacheAccountScope.withPinned(scope) { store.localURLIgnoringStaleness(item) }
            },
            pinnedRoots: { CacheAccountScope.withPinned(scope) { store.pinnedRoots() } },
            setPinnedRoots: { roots in CacheAccountScope.withPinned(scope) { store.setPinnedRoots(roots) } },
            totalSizeBytes: { CacheAccountScope.withPinned(scope) { store.totalSizeBytes() } },
            pinnedRootUsages: { CacheAccountScope.withPinned(scope) { store.pinnedRootUsages() } },
            removeRoot: { path in CacheAccountScope.withPinned(scope) { store.removeRoot(path) } },
            reconcile: { paths in CacheAccountScope.withPinned(scope) { store.reconcile(paths) } },
            removeAll: store.removeAll,
            removeCurrentAccount: { CacheAccountScope.withPinned(scope) { store.removeCurrentAccount() } },
            removeAccount: store.removeAccount,
            setInterrupted: { value in CacheAccountScope.withPinned(scope) { store.setInterrupted(value) } },
            wasInterrupted: { CacheAccountScope.withPinned(scope) { store.wasInterrupted() } },
            lastAutoSyncAt: { CacheAccountScope.withPinned(scope) { store.lastAutoSyncAt() } },
            setLastAutoSyncAt: { date in CacheAccountScope.withPinned(scope) { store.setLastAutoSyncAt(date) } },
            localFileSize: { path in CacheAccountScope.withPinned(scope) { store.localFileSize(path) } },
            copyMetadata: { path in CacheAccountScope.withPinned(scope) { store.copyMetadata(path) } },
            saveListing: { directory in CacheAccountScope.withPinned(scope) { store.saveListing(directory) } },
            listing: { path in CacheAccountScope.withPinned(scope) { store.listing(path) } }
        )
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
        removeAccount: { OfflineCache.removeScope($0) },
        setInterrupted: { OfflineCache.setInterrupted($0) },
        wasInterrupted: { OfflineCache.wasInterrupted() },
        lastAutoSyncAt: { OfflineCache.lastAutoSyncAt() },
        setLastAutoSyncAt: { OfflineCache.setLastAutoSyncAt($0) },
        localFileSize: { OfflineCache.localFileSize(forPath: $0) },
        copyMetadata: { OfflineCache.copyMetadata(forPath: $0) },
        saveListing: { OfflineCache.saveListing($0) },
        listing: { OfflineCache.listing(forPath: $0) }
    )

    /// No pinned files, no manifest: tests that exercise the offline read path inject a seeded
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
    public static func inMemory(
        localURLs: [String: URL] = [:], copyMetadata: [String: OfflineCopyMetadata] = [:]
    ) -> OfflineFileStore {
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
            setLastAutoSyncAt: { box.setLastAutoSyncAt($0) },
            copyMetadata: { copyMetadata[$0] },
            saveListing: { box.saveListing($0) },
            listing: { box.listing($0) }
        )
    }

    private final class InMemoryBox: @unchecked Sendable {
        private let lock = NSLock()
        private var roots: [OfflinePinnedRoot] = []
        private var interrupted = false
        private var lastSync: Date?
        private var listings: [String: CachedDirectory] = [:]
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

        func saveListing(_ directory: CachedDirectory) {
            lock.lock(); defer { lock.unlock() }
            listings[directory.path] = directory
        }

        func listing(_ path: String) -> CachedDirectory? {
            lock.lock(); defer { lock.unlock() }
            return listings[path]
        }

        func removeAll() {
            lock.lock(); defer { lock.unlock() }
            roots = []
            listings = [:]
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
