import CoreModels
import CryptoKit
@testable import FilesClient
import Foundation
import Testing

@Suite("Account scoped cache clearing")
struct AccountScopedCacheTests {
    private let serverURL = URL(string: "https://example.com") ?? URL(fileURLWithPath: "/")
    private let accountA = "https://example.com|alice"
    private let accountB = "https://example.com|bob"
    private let fetchedAt = Date(timeIntervalSince1970: 1_000)

    private func makeRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("scoped-cache-\(UUID().uuidString)")
    }

    private func listing(_ name: String) -> BrowseResult {
        BrowseResult(
            items: [FileItem(name: name, path: "docs", dateModified: fetchedAt, size: 1, kind: "txt")],
            access: FileAccess(
                canRead: true, canWrite: false, canUpload: false,
                canDelete: false, canShare: false, canDownload: true
            ),
            path: "docs"
        )
    }

    @Test("DirectoryCacheStore on disk: clear(scope:) removes only that account's listings")
    func directoryClearScope() {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DirectoryCacheStore.onDisk(rootDirectory: root)
        store.bound(to: accountA).write(serverURL: serverURL, path: "docs", result: listing("a"), etag: nil, fetchedAt: fetchedAt)
        store.bound(to: accountB).write(serverURL: serverURL, path: "docs", result: listing("b"), etag: nil, fetchedAt: fetchedAt)

        store.clear(scope: accountA)

        #expect(store.bound(to: accountA).read(serverURL: serverURL, path: "docs") == nil)
        #expect(store.bound(to: accountB).read(serverURL: serverURL, path: "docs")?.items.map(\.name) == ["b"])
    }

    @Test("DirectoryCacheStore on disk: clearing a scope with no entries is a no op")
    func directoryClearUnknownScope() {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DirectoryCacheStore.onDisk(rootDirectory: root)
        store.bound(to: accountB).write(serverURL: serverURL, path: "docs", result: listing("b"), etag: nil, fetchedAt: fetchedAt)

        store.clear(scope: "unknown")
        store.clear(scope: "")

        #expect(store.bound(to: accountB).read(serverURL: serverURL, path: "docs") != nil)
    }

    @Test("DirectoryCacheStore on disk: a bound store writes its own scope regardless of the global scope")
    func directoryBoundWritesPinnedScope() {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DirectoryCacheStore.onDisk(rootDirectory: root)
        let pinned = store.bound(to: accountA)

        pinned.write(serverURL: serverURL, path: "docs", result: listing("a"), etag: "\"v1\"", fetchedAt: fetchedAt)

        #expect(store.bound(to: accountA).read(serverURL: serverURL, path: "docs")?.etag == "\"v1\"")
        #expect(store.bound(to: accountB).read(serverURL: serverURL, path: "docs") == nil)
    }

    @Test("DirectoryCacheStore in memory: clear(scope:) keeps other accounts")
    func directoryInMemoryClearScope() {
        let store = DirectoryCacheStore.inMemory()
        store.bound(to: accountA).write(serverURL: serverURL, path: "docs", result: listing("a"), etag: nil, fetchedAt: fetchedAt)
        store.bound(to: accountB).write(serverURL: serverURL, path: "docs", result: listing("b"), etag: nil, fetchedAt: fetchedAt)

        store.clear(scope: accountA)

        #expect(store.bound(to: accountA).read(serverURL: serverURL, path: "docs") == nil)
        #expect(store.bound(to: accountB).read(serverURL: serverURL, path: "docs") != nil)
    }

    @Test("JSONCacheStore on disk: clear(scope:) removes only that account's payloads")
    func jsonClearScope() {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = JSONCacheStore.onDisk(rootDirectory: root)
        store.bound(to: accountA).write(key: "favorites", data: Data("a".utf8))
        store.bound(to: accountA).write(key: "shares.byMe", data: Data("a2".utf8))
        store.bound(to: accountB).write(key: "favorites", data: Data("b".utf8))

        store.clear(scope: accountA)

        #expect(store.bound(to: accountA).read(key: "favorites") == nil)
        #expect(store.bound(to: accountA).read(key: "shares.byMe") == nil)
        #expect(store.bound(to: accountB).read(key: "favorites")?.data == Data("b".utf8))
    }

    @Test("JSONCacheStore on disk: a bound store writes its own scope, not the one active at write time")
    func jsonBoundWritesPinnedScope() {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = JSONCacheStore.onDisk(rootDirectory: root)

        store.bound(to: accountA).write(key: "favorites", data: Data("a".utf8))

        #expect(store.bound(to: accountA).read(key: "favorites") != nil)
        #expect(store.bound(to: accountB).read(key: "favorites") == nil)
    }

    @Test("JSONCacheStore in memory: clear(scope:) keeps other accounts")
    func jsonInMemoryClearScope() {
        let store = JSONCacheStore.inMemory()
        store.bound(to: accountA).write(key: "favorites", data: Data("a".utf8))
        store.bound(to: accountB).write(key: "favorites", data: Data("b".utf8))

        store.clear(scope: accountA)

        #expect(store.bound(to: accountA).read(key: "favorites") == nil)
        #expect(store.bound(to: accountB).read(key: "favorites") != nil)
    }

    @Test("clearAll still removes every scope")
    func clearAllRemovesEveryScope() {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = JSONCacheStore.onDisk(rootDirectory: root)
        store.bound(to: accountA).write(key: "favorites", data: Data("a".utf8))
        store.bound(to: accountB).write(key: "favorites", data: Data("b".utf8))

        store.clearAll()

        #expect(store.bound(to: accountA).read(key: "favorites") == nil)
        #expect(store.bound(to: accountB).read(key: "favorites") == nil)
    }

    @Test("Preview cache: clearPreviewCache(scope:) removes only that account's slots in both namespaces")
    func previewClearScope() throws {
        let caches = makeRoot()
        defer { try? FileManager.default.removeItem(at: caches) }
        let item = FileItem(name: "a.txt", path: "docs", dateModified: fetchedAt, size: 1, kind: "txt")
        var slotsByScope: [String: [URL]] = [:]
        for namespace in [FilesService.previewCacheNamespace, FilesService.rawDownloadCacheNamespace] {
            for scope in [accountA, accountB] {
                let slot = FilesService.previewCacheDirectory(for: item, namespace: namespace, scope: scope, in: caches)
                try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
                try Data("x".utf8).write(to: slot.appendingPathComponent("file.bin"))
                slotsByScope[scope, default: []].append(slot)
            }
        }

        FilesService.clearPreviewCache(scope: accountA, in: caches)

        for slot in slotsByScope[accountA] ?? [] {
            #expect(!FileManager.default.fileExists(atPath: slot.path))
        }
        for slot in slotsByScope[accountB] ?? [] {
            #expect(FileManager.default.fileExists(atPath: slot.path))
        }
        #expect(slotsByScope[accountA]?.count == 2)
    }

    @Test("Preview cache: an explicit scope decides the slot, not the process wide scope")
    func previewSlotFollowsTheCapturedScope() {
        let item = FileItem(name: "a.txt", path: "docs", dateModified: fetchedAt, size: 1, kind: "txt")
        let slotA = FilesService.previewCacheDirectory(for: item, namespace: FilesService.previewCacheNamespace, scope: accountA)
        let slotB = FilesService.previewCacheDirectory(for: item, namespace: FilesService.previewCacheNamespace, scope: accountB)

        #expect(slotA != slotB)
        #expect(slotA.lastPathComponent.hasPrefix(CacheAccountScope.filePrefix(for: accountA) + "-"))
    }

    @Test("Offline cache: a slot is stored under the scope captured at start, not the current one")
    func offlineStoreUsesTheCapturedScope() throws {
        let scope = "offline-captured-\(UUID().uuidString)"
        let item = FileItem(name: "a.txt", path: "docs", dateModified: fetchedAt, size: 1, kind: "txt")
        defer { OfflineCache.removeScope(scope) }
        let downloaded = FileManager.default.temporaryDirectory.appendingPathComponent("offline-src-\(UUID().uuidString)")
        try Data("x".utf8).write(to: downloaded)

        _ = try OfflineCache.store(downloadedURL: downloaded, item: item, scope: scope)

        #expect(OfflineCache.localURL(for: item, scope: scope) != nil)
        #expect(OfflineCache.localURL(for: item, scope: "\(scope)-other") == nil)
        #expect(OfflineCache.localURL(forPath: item.id, scope: scope) != nil)
    }

    @Test("Thumbnail caches: clearPreviewCache(scope:) removes only that account's thumbnail files")
    func thumbnailClearScope() throws {
        let caches = makeRoot()
        defer { try? FileManager.default.removeItem(at: caches) }
        let root = caches.appendingPathComponent(FilesService.previewCacheRootDirectory, isDirectory: true)
        var files: [URL] = []
        for directoryName in FilesService.flatScopedCacheSubdirectories {
            let directory = root.appendingPathComponent(directoryName, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for scope in [accountA, accountB] {
                let file = directory.appendingPathComponent(CacheAccountScope.scopedFileName("digest", scope: scope))
                try Data("x".utf8).write(to: file)
                files.append(file)
            }
        }

        FilesService.clearPreviewCache(scope: accountA, in: caches)

        let prefixA = CacheAccountScope.filePrefix(for: accountA)
        for file in files {
            #expect(FileManager.default.fileExists(atPath: file.path) == !file.lastPathComponent.hasPrefix(prefixA))
        }
    }

    @Test("Thumbnail file names differ per account for the same digest")
    func scopedFileNameDiffersPerAccount() {
        #expect(CacheAccountScope.scopedFileName("d", scope: accountA) != CacheAccountScope.scopedFileName("d", scope: accountB))
        #expect(CacheAccountScope.scopedFileName("d", scope: accountA).hasSuffix("-d"))
    }

    @Test("Preview cache: slot directories carry the active scope's prefix")
    func previewSlotUsesScopePrefix() {
        let item = FileItem(name: "a.txt", path: "docs", dateModified: fetchedAt, size: 1, kind: "txt")
        let directory = FilesService.previewCacheDirectory(for: item, namespace: FilesService.previewCacheNamespace)
        #expect(directory.lastPathComponent.hasPrefix(CacheAccountScope.filePrefix(for: CacheAccountScope.current) + "-"))
    }

    @Test("Offline files: removeScope deletes the named account's directory and keeps another's")
    func offlineRemoveScope() throws {
        let unique = UUID().uuidString
        let removed = "offline-test-removed-\(unique)"
        let kept = "offline-test-kept-\(unique)"
        func directory(for scope: String) throws -> URL {
            let rootURL = try #require(OfflineCache.root())
            let hex = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
            return rootURL.appendingPathComponent(hex, isDirectory: true)
        }
        let removedDirectory = try directory(for: removed)
        let keptDirectory = try directory(for: kept)
        defer {
            try? FileManager.default.removeItem(at: removedDirectory)
            try? FileManager.default.removeItem(at: keptDirectory)
        }
        for url in [removedDirectory, keptDirectory] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url.appendingPathComponent("manifest.json"))
        }

        OfflineCache.removeScope(removed)

        #expect(!FileManager.default.fileExists(atPath: removedDirectory.path))
        #expect(FileManager.default.fileExists(atPath: keptDirectory.path))
    }
}
