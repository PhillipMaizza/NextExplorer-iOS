import Foundation
import Testing

@testable import FilesFeature

/// Exercises `PreviewCacheStore.liveValue` against the real filesystem, same spirit as
/// `LocalDownloadStoreTests` — the whole point is verifying actual on-disk behavior.
/// `.serialized`: every test here shares one real directory (`size`/`clear` operate on the
/// whole cache root, not a per-test-unique file), so running them concurrently races.
@Suite(.serialized)
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
    func sizeReflectsTheTotalBytesOfEveryFileInTheCache() throws {
        try? FileManager.default.removeItem(at: cacheDirectory)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        _ = try writeFile(named: "a.txt", contents: "12345", in: "preview/one")
        _ = try writeFile(named: "b.txt", contents: "1234567890", in: "download/two")

        #expect(try store.size() == 15)
    }

    @Test
    func clearRemovesTheWholeCacheDirectory() throws {
        _ = try writeFile(named: "a.txt", contents: "hello", in: "preview/one")

        try store.clear()

        #expect(!FileManager.default.fileExists(atPath: cacheDirectory.path))
        #expect(try store.size() == 0)
    }

    // MARK: Edge cases

    @Test
    func sizeIsZeroWhenTheCacheDirectoryDoesNotExist() throws {
        try? FileManager.default.removeItem(at: cacheDirectory)

        #expect(try store.size() == 0)
    }

    @Test
    func clearIsANoOpWhenTheCacheDirectoryDoesNotExist() throws {
        try? FileManager.default.removeItem(at: cacheDirectory)

        // Should not throw even though there's nothing to remove.
        try store.clear()
    }
}
