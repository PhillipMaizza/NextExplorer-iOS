import CoreModels
@testable import FilesClient
import Foundation
import NetworkClient
import Testing
import TestUtils

/// Ties the names the real stores write to `CacheAccountScope.hasAccountPrefix`, the check the one
/// time cleanup of unscoped entries relies on. If the prefix length or separator changes in one place
/// only, these fail instead of the cleanup deleting live data.
@Suite("Cache file names")
struct CacheFileNameTests {
    private enum Fixture {
        static let account = "https://example.com|alice"
        static let server = URL(fileURLWithPath: "/")
        static let path = TestPath.docsLowercase
        static let fetchedAt = MockDate.date.addingTimeInterval(1000)
        static let rootPrefix = "cache-file-names-"
        static let pinnedScopePrefix = "pinned-scope-"
        static let payload = Data("x".utf8)
    }

    private func makeRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(Fixture.rootPrefix)\(TestID.name())")
    }

    private func names(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).map(\.lastPathComponent)
    }

    @Test("directory cache files carry the account prefix and live where the cleanup looks")
    func directoryCacheNames() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = BrowseResult(
            items: [],
            access: FileAccess(canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true),
            path: Fixture.path
        )
        DirectoryCacheStore.onDisk(rootDirectory: root).bound(to: Fixture.account)
            .write(serverURL: Fixture.server, path: Fixture.path, result: result, etag: nil, fetchedAt: Fixture.fetchedAt)

        let written = try names(in: root.appendingPathComponent(CacheLayout.directoryCacheName, isDirectory: true))

        #expect(written.count == 1)
        #expect(written.allSatisfy(CacheAccountScope.hasAccountPrefix))
        #expect(written.allSatisfy { $0.hasPrefix(CacheAccountScope.namePrefix(for: Fixture.account)) })
    }

    @Test("list cache files carry the account prefix and live where the cleanup looks")
    func listCacheNames() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        JSONCacheStore.onDisk(rootDirectory: root).bound(to: Fixture.account).write(key: TestCacheKey.favorites, data: Fixture.payload)

        let written = try names(in: root.appendingPathComponent(CacheLayout.listCacheName, isDirectory: true))

        #expect(written.count == 1)
        #expect(written.allSatisfy(CacheAccountScope.hasAccountPrefix))
        #expect(written.allSatisfy { $0.hasPrefix(CacheAccountScope.namePrefix(for: Fixture.account)) })
    }

    @Test("preview and raw download slot directories carry the account prefix", arguments: CacheLayout.previewSlotNamespaces)
    func previewSlotNames(namespace: String) {
        let item = FileItem(name: TestFile.aText, path: Fixture.path, dateModified: Fixture.fetchedAt, size: 1, kind: TestKind.text)

        let slot = FilesService.previewCacheDirectory(for: item, namespace: namespace, scope: Fixture.account)

        #expect(CacheAccountScope.hasAccountPrefix(slot.lastPathComponent))
        #expect(slot.lastPathComponent.hasPrefix(CacheAccountScope.namePrefix(for: Fixture.account)))
        #expect(slot.deletingLastPathComponent().lastPathComponent == namespace)
    }

    @Test("a name without the prefix, like an older release wrote, is not recognized")
    func unprefixedNamesAreNotRecognized() {
        let fullDigest = String(repeating: "a", count: 64)

        #expect(!CacheAccountScope.hasAccountPrefix(fullDigest))
        #expect(!CacheAccountScope.hasAccountPrefix("\(fullDigest).json"))
    }

    @Test("a pinned scope applies to child tasks and leaves the process wide scope alone")
    func pinnedScopeReachesChildTasksOnly() async {
        let before = CacheAccountScope.current

        let inside = await CacheAccountScope.withPinned("\(Fixture.pinnedScopePrefix)a") {
            async let child = Task { CacheAccountScope.current }.value
            return await (CacheAccountScope.current, child)
        }

        #expect(inside.0 == "\(Fixture.pinnedScopePrefix)a")
        #expect(inside.1 == "\(Fixture.pinnedScopePrefix)a")
        #expect(CacheAccountScope.current == before)
    }

    @Test("an offline store pinned to one account never reads or writes another's manifest")
    func pinnedOfflineStoreStaysInItsAccount() {
        let scopeA = "\(Fixture.pinnedScopePrefix)\(TestID.name())"
        let scopeB = "\(Fixture.pinnedScopePrefix)\(TestID.name())"
        let store = OfflineFileStore.liveValue
        defer {
            store.removeAccount(scopeA)
            store.removeAccount(scopeB)
        }
        let root = OfflinePinnedRoot(path: Fixture.path, isDirectory: true)

        store.pinned(to: scopeA).setPinnedRoots([root])

        #expect(store.pinned(to: scopeA).pinnedRoots() == [root])
        #expect(store.pinned(to: scopeB).pinnedRoots().isEmpty)
    }

    @Test("missing root strikes count per root and per account, and reset when the root is unpinned")
    func missingRootStrikes() {
        let scopeA = "\(Fixture.pinnedScopePrefix)\(TestID.name())"
        let scopeB = "\(Fixture.pinnedScopePrefix)\(TestID.name())"
        let store = OfflineFileStore.liveValue
        defer {
            store.removeAccount(scopeA)
            store.removeAccount(scopeB)
        }
        let a = store.pinned(to: scopeA)
        let b = store.pinned(to: scopeB)

        #expect(a.recordMissingRoot(Constants.firstRoot) == 1)
        #expect(a.recordMissingRoot(Constants.firstRoot) == 2)
        #expect(a.recordMissingRoot(Constants.secondRoot) == 1)
        #expect(b.recordMissingRoot(Constants.firstRoot) == 1)

        a.clearMissingRoot(Constants.firstRoot)
        #expect(a.recordMissingRoot(Constants.firstRoot) == 1)

        a.setPinnedRoots([OfflinePinnedRoot(path: Constants.secondRoot, isDirectory: true)])
        a.removeRoot(Constants.secondRoot)
        #expect(a.recordMissingRoot(Constants.secondRoot) == 1)
    }

    @Test("local file size reports the pinned copy's bytes and nil for a path that is not pinned")
    func localFileSize() throws {
        let scope = "\(Fixture.pinnedScopePrefix)\(TestID.name())"
        let store = OfflineFileStore.liveValue
        defer { store.removeAccount(scope) }
        let item = FileItem(name: TestFile.aText, path: Fixture.path, dateModified: Fixture.fetchedAt, size: 3, kind: TestKind.text)
        let downloaded = FileManager.default.temporaryDirectory.appendingPathComponent("\(Fixture.rootPrefix)\(TestID.name())")
        try Data("abc".utf8).write(to: downloaded)
        _ = try OfflineCache.store(downloadedURL: downloaded, item: item, scope: scope)
        let pinned = store.pinned(to: scope)

        #expect(pinned.localFileSize(item.id) == 3)
        #expect(pinned.localFileSize("\(Fixture.path)/other.txt") == nil)
        #expect(store.pinned(to: "\(scope)-other").localFileSize(item.id) == nil)
    }

    @Test("a live client serves the pinned copy of the account its task is pinned to, whatever the process wide scope is")
    func liveClientHonorsThePinnedScope() async throws {
        let scope = "\(Fixture.pinnedScopePrefix)\(TestID.name())"
        defer { OfflineCache.removeScope(scope) }
        let item = FileItem(name: "a.bin", path: Fixture.path, dateModified: Fixture.fetchedAt, size: 1, kind: "bin")
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("\(Fixture.rootPrefix)\(TestID.name())")
        try Fixture.payload.write(to: source)
        let stored = try OfflineCache.store(downloadedURL: source, item: item, scope: scope)
        let client = FilesClient.live(networkClient: .live(protocolClasses: [StubURLProtocol.self]), directoryCacheStore: .testValue)

        let url = try await CacheAccountScope.withPinned(scope) {
            try await client.downloadRawFile(URL(fileURLWithPath: "/"), item)
        }

        #expect(url == stored)
    }
}

private enum Constants {
    static let firstRoot = "one"
    static let secondRoot = "two"
}
