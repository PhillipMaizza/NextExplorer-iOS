import FilesClient
import Foundation
import Testing
import TestUtils

/// The disk hygiene every cache store shares: a protected folder evicted oldest first.
@Suite("Protected cache directory")
struct ProtectedCacheDirectoryTests {
    private enum Constants {
        static let name = "Cache"
        static let fileExtension = "json"
        static let entryBytes = 100
        static let accountPrefix = "account-a-"
        static let otherPrefix = "account-b-"
        static let otherExtension = "tmp"
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ProtectedCache-\(TestID.uuid().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes `name.json` of `Constants.entryBytes`, last modified `age` seconds after `MockDate.date`.
    private func write(_ name: String, in directory: ProtectedCacheDirectory, age: TimeInterval, extension fileExtension: String = Constants.fileExtension) throws {
        let url = directory.url.appendingPathComponent(name).appendingPathExtension(fileExtension)
        try Data(count: Constants.entryBytes).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: MockDate.date.addingTimeInterval(age)], ofItemAtPath: url.path)
    }

    private func names(in directory: ProtectedCacheDirectory) -> [String] {
        directory.entriesByAge().map { $0.url.deletingPathExtension().lastPathComponent }
    }

    @Test("The folder is created, excluded from backup")
    func theFolderIsCreatedAndExcludedFromBackup() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = try #require(ProtectedCacheDirectory(name: Constants.name, base: root, fileExtension: Constants.fileExtension))

        let values = try directory.url.resourceValues(forKeys: [.isDirectoryKey, .isExcludedFromBackupKey])
        #expect(values.isDirectory == true)
        #expect(values.isExcludedFromBackup == true)
    }

    @Test("Entries list oldest first and count only the store's own extension")
    func entriesAreOldestFirstAndOnlyTheStores() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = try #require(ProtectedCacheDirectory(name: Constants.name, base: root, fileExtension: Constants.fileExtension))
        try write("new", in: directory, age: 20)
        try write("old", in: directory, age: 10)
        try write("other", in: directory, age: 0, extension: Constants.otherExtension)

        #expect(names(in: directory) == ["old", "new"])
        #expect(directory.totalSizeBytes() == 200)
    }

    @Test("Past the entry cap the oldest entries go first")
    func evictionByCountDropsTheOldest() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = try #require(ProtectedCacheDirectory(name: Constants.name, base: root, fileExtension: Constants.fileExtension))
        for (age, name) in ["a", "b", "c"].enumerated() {
            try write(name, in: directory, age: TimeInterval(age))
        }

        directory.evict(maxEntries: 2, maxTotalBytes: .max)

        #expect(names(in: directory) == ["b", "c"])
    }

    @Test("Past the byte cap the oldest entries go until the rest fit")
    func evictionByBytesDropsTheOldest() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = try #require(ProtectedCacheDirectory(name: Constants.name, base: root, fileExtension: Constants.fileExtension))
        for (age, name) in ["a", "b", "c"].enumerated() {
            try write(name, in: directory, age: TimeInterval(age))
        }

        directory.evict(maxEntries: .max, maxTotalBytes: 150)

        #expect(names(in: directory) == ["c"])
    }

    @Test("One account's entries can be removed, keeping the other's")
    func removingOneAccountKeepsTheOther() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = try #require(ProtectedCacheDirectory(name: Constants.name, base: root, fileExtension: Constants.fileExtension))
        try write(Constants.accountPrefix + "1", in: directory, age: 0)
        try write(Constants.otherPrefix + "1", in: directory, age: 1)

        directory.removeEntries(withPrefix: Constants.accountPrefix)

        #expect(names(in: directory) == [Constants.otherPrefix + "1"])
    }

    @Test("Removing everything empties the folder, other files included")
    func removeAllEmptiesTheFolder() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = try #require(ProtectedCacheDirectory(name: Constants.name, base: root, fileExtension: Constants.fileExtension))
        try write("a", in: directory, age: 0)
        try write("other", in: directory, age: 0, extension: Constants.otherExtension)

        directory.removeAll()

        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.url.path).isEmpty)
    }
}
