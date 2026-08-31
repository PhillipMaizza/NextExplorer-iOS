import CoreModels
import Foundation
import Testing

@testable import FilesClient

@Suite(.serialized)
struct DirectoryCacheStoreTests {
    private let serverURL = URL(string: "https://example.com")!

    private func makeStore() -> (DirectoryCacheStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dircache-test-\(UUID().uuidString)")
        return (DirectoryCacheStore.onDisk(rootDirectory: root), root)
    }

    private func cleanUp(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }

    private func result(path: String, itemNames: [String]) -> BrowseResult {
        BrowseResult(
            items: itemNames.map {
                FileItem(name: $0, path: path, dateModified: Date(timeIntervalSince1970: 0), size: 1, kind: "txt")
            },
            access: FileAccess(
                canRead: true, canWrite: false, canUpload: false,
                canDelete: false, canShare: false, canDownload: true
            ),
            path: path
        )
    }

    @Test
    func writeThenReadRoundTrips() {
        let (store, root) = makeStore()
        defer { cleanUp(root) }
        let fetchedAt = Date(timeIntervalSince1970: 1_000)

        store.write(serverURL: serverURL, path: "docs", result: result(path: "docs", itemNames: ["a.txt", "b.txt"]), etag: nil, fetchedAt: fetchedAt)

        let cached = store.read(serverURL: serverURL, path: "docs")
        #expect(cached?.items.map(\.name) == ["a.txt", "b.txt"])
        #expect(cached?.access.canDownload == true)
        #expect(cached?.fetchedAt == fetchedAt)
    }

    @Test
    func etagAndWriteTimeRoundTrip() {
        let (store, root) = makeStore()
        defer { cleanUp(root) }
        let before = Date()

        store.write(
            serverURL: serverURL, path: "docs",
            result: result(path: "docs", itemNames: ["x"]), etag: "\"abc123\"", fetchedAt: Date(timeIntervalSince1970: 5)
        )

        #expect(store.read(serverURL: serverURL, path: "docs")?.etag == "\"abc123\"")
        let writtenAt = store.lastWrittenAt(serverURL: serverURL, path: "docs")
        #expect(writtenAt != nil)
        #expect(writtenAt! >= before.addingTimeInterval(-1))
        #expect(store.lastWrittenAt(serverURL: serverURL, path: "missing") == nil)
    }

    @Test
    func readMissesForUnknownPath() {
        let (store, root) = makeStore()
        defer { cleanUp(root) }
        #expect(store.read(serverURL: serverURL, path: "nope") == nil)
    }

    @Test
    func siblingPathsDoNotCollide() {
        let (store, root) = makeStore()
        defer { cleanUp(root) }
        store.write(serverURL: serverURL, path: "a", result: result(path: "a", itemNames: ["one"]), etag: nil, fetchedAt: Date())
        store.write(serverURL: serverURL, path: "b", result: result(path: "b", itemNames: ["two"]), etag: nil, fetchedAt: Date())

        #expect(store.read(serverURL: serverURL, path: "a")?.items.map(\.name) == ["one"])
        #expect(store.read(serverURL: serverURL, path: "b")?.items.map(\.name) == ["two"])
    }

    @Test
    func leadingAndTrailingSlashesNormalizeToSameEntry() {
        let (store, root) = makeStore()
        defer { cleanUp(root) }
        store.write(serverURL: serverURL, path: "docs", result: result(path: "docs", itemNames: ["x"]), etag: nil, fetchedAt: Date())
        #expect(store.read(serverURL: serverURL, path: "/docs/")?.items.map(\.name) == ["x"])
    }

    @Test
    func removeDropsEntry() {
        let (store, root) = makeStore()
        defer { cleanUp(root) }
        store.write(serverURL: serverURL, path: "docs", result: result(path: "docs", itemNames: ["x"]), etag: nil, fetchedAt: Date())
        store.remove(serverURL: serverURL, path: "docs")
        #expect(store.read(serverURL: serverURL, path: "docs") == nil)
    }

    @Test
    func clearAllDropsEverything() {
        let (store, root) = makeStore()
        defer { cleanUp(root) }
        store.write(serverURL: serverURL, path: "a", result: result(path: "a", itemNames: ["one"]), etag: nil, fetchedAt: Date())
        store.write(serverURL: serverURL, path: "b", result: result(path: "b", itemNames: ["two"]), etag: nil, fetchedAt: Date())
        store.clearAll()
        #expect(store.read(serverURL: serverURL, path: "a") == nil)
        #expect(store.read(serverURL: serverURL, path: "b") == nil)
        #expect(store.totalSizeBytes() == 0)
    }

    @Test
    func anOversizedFolderIsNotCachedAndReplacesNoPriorEntry() {
        let (store, root) = makeStore()
        defer { cleanUp(root) }

        store.write(serverURL: serverURL, path: "docs", result: result(path: "docs", itemNames: ["small"]), etag: nil, fetchedAt: Date())

        let hugeNames = (0..<60_000).map { "file-with-a-fairly-long-name-number-\($0).txt" }
        store.write(serverURL: serverURL, path: "docs", result: result(path: "docs", itemNames: hugeNames), etag: nil, fetchedAt: Date())

        #expect(store.read(serverURL: serverURL, path: "docs") == nil)
    }

    @Test
    func evictionDropsTheOldestEntriesOnceOverTheCount() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dircache-test-\(UUID().uuidString)")
        defer { cleanUp(root) }
        let store = DirectoryCacheStore.onDisk(rootDirectory: root, maxEntries: 3)

        for index in 0..<6 {
            store.write(
                serverURL: serverURL,
                path: "dir\(index)",
                result: result(path: "dir\(index)", itemNames: ["item"]),
                etag: nil,
                fetchedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        let survivors = (0..<6).filter { store.read(serverURL: serverURL, path: "dir\($0)") != nil }
        #expect(survivors == [3, 4, 5])
    }

    @Test
    func schemaVersionMismatchDiscardsEntry() throws {
        let (store, root) = makeStore()
        defer { cleanUp(root) }
        store.write(serverURL: serverURL, path: "docs", result: result(path: "docs", itemNames: ["x"]), etag: nil, fetchedAt: Date())

        let cacheDirectory = root.appendingPathComponent("DirectoryCache")
        let file = try #require(
            try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
                .first { $0.pathExtension == "json" }
        )
        let stale = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        var mutated = stale
        mutated["schemaVersion"] = CachedDirectory.currentSchemaVersion + 1
        try JSONSerialization.data(withJSONObject: mutated).write(to: file)

        #expect(store.read(serverURL: serverURL, path: "docs") == nil)
    }
}
