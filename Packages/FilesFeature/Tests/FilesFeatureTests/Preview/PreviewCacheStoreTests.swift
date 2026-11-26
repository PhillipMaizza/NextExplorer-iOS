import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// Exercises `PreviewCacheStore.liveValue` against the real filesystem, same spirit as
/// `LegacyDownloadStoreTests`: the whole point is verifying actual on disk behavior.
/// `.serialized`: every test here shares one real directory (`clear` removes the whole cache
/// root), so running them concurrently races.
/// `SerializedPreviewCacheAccess`: also keeps it from overlapping other suites that touch
/// the same directory (`ThumbnailCacheTests`).
@Suite(.serialized, SerializedPreviewCacheAccess())
struct PreviewCacheStoreTests {
    private let store = PreviewCacheStore.liveValue

    private var cacheDirectory: URL {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return cachesDirectory.appendingPathComponent("PreviewCache", isDirectory: true)
    }

    private func writeFile(named name: String, contents: String, in subdirectory: String) throws -> URL {
        let directory = cacheDirectory.appendingPathComponent(subdirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(name)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    // MARK: Happy path

    @Test
    func sizeCountsOnlyTheAccountsOwnSlots() throws {
        try? FileManager.default.removeItem(at: cacheDirectory)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        func slot(_ namespace: String, _ scope: String) -> String {
            "\(namespace)/\(CacheAccountScope.scopedFileName("slot", scope: scope))"
        }

        _ = try writeFile(
            named: TestFile.aText,
            contents: "12345",
            in: slot(CacheLayout.previewNamespaceName, TestAccountID.alice)
        )
        _ = try writeFile(
            named: TestFile.bText,
            contents: "1234567890",
            in: slot(CacheLayout.rawDownloadNamespaceName, TestAccountID.alice)
        )
        _ = try writeFile(
            named: TestFile.aText,
            contents: "123",
            in: slot(CacheLayout.previewNamespaceName, TestAccountID.bob)
        )

        #expect(store.size(TestAccountID.alice) == 15)
        #expect(store.size(TestAccountID.bob) == 3)
    }

    @Test
    func clearRemovesTheWholeCacheDirectory() throws {
        _ = try writeFile(named: TestFile.aText, contents: "hello", in: "preview/one")

        try store.clear()

        #expect(!FileManager.default.fileExists(atPath: cacheDirectory.path))
        #expect(store.size(TestAccountID.alice) == 0)
    }

    // MARK: Edge cases

    @Test
    func sizeIsZeroWhenTheCacheDirectoryDoesNotExist() {
        try? FileManager.default.removeItem(at: cacheDirectory)

        #expect(store.size(TestAccountID.alice) == 0)
    }

    @Test
    func clearIsANoOpWhenTheCacheDirectoryDoesNotExist() throws {
        try? FileManager.default.removeItem(at: cacheDirectory)

        try store.clear()
        try store.clear()

        #expect(!FileManager.default.fileExists(atPath: cacheDirectory.path))
    }
}
