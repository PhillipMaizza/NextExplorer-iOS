@testable import FilesFeature
import Foundation
import Testing
import TestUtils
import ZIPFoundation

struct ArchiveReaderTests {
    private enum Constants {
        static let folderEntry = "docs/"
        static let nestedEntry = "docs/readme.txt"
        static let rootEntry = "top.bin"
        static let nestedBytes = Data("hello archive".utf8)
        static let rootBytes = Data(repeating: 0x7A, count: 4_096)
        static let directoryPrefix = "archive-reader-"
        static let zipKind = "zip"
        static let rarKind = "rar"
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Constants.directoryPrefix)\(TestID.name())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeZip(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(FilesFeatureTestValue.bundleName)
        let archive = try Archive(url: url, accessMode: .create)
        try archive.addEntry(with: Constants.folderEntry, type: .directory, uncompressedSize: Int64(0)) { (
            _: Int64,
            _: Int
        ) -> Data in Data() }
        for (path, bytes) in [
            (Constants.nestedEntry, Constants.nestedBytes),
            (Constants.rootEntry, Constants.rootBytes),
        ] {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(bytes.count)) { (
                position: Int64,
                size: Int
            ) -> Data in
                bytes.subdata(in: Int(position) ..< Int(position) + size)
            }
        }
        return url
    }

    @Test
    func aZipListsEveryEntryWithItsKindAndUncompressedSize() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try ArchiveReader.open(fileURL: makeZip(in: directory), kind: Constants.zipKind)

        let entries = try ArchiveReader.entries(from: source)

        #expect(entries.map(\.path) == [Constants.folderEntry, Constants.nestedEntry, Constants.rootEntry])
        #expect(entries.map(\.isDirectory) == [true, false, false])
        #expect(entries.map(\.size) == [0, UInt64(Constants.nestedBytes.count), UInt64(Constants.rootBytes.count)])
    }

    @Test(arguments: [Constants.zipKind, "ZIP", "Zip"])
    func theFormatIsMatchedWithoutRegardToCase(_ kind: String) throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try ArchiveReader.open(fileURL: makeZip(in: directory), kind: kind)

        #expect(try ArchiveReader.entries(from: source).count == 3)
    }

    @Test(arguments: ["7z", "tar", "", "rarr"])
    func anUnsupportedFormatIsRefusedBeforeTheFileIsTouched(_ kind: String) throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(TestID.name())

        #expect(throws: ArchiveReaderError.unsupportedFormat) {
            _ = try ArchiveReader.open(fileURL: missing, kind: kind)
        }
    }

    @Test(arguments: [Constants.zipKind, Constants.rarKind])
    func aMissingArchiveFileFailsToOpen(_ kind: String) {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(TestID.name())

        #expect(throws: (any Error).self) {
            _ = try ArchiveReader.open(fileURL: missing, kind: kind)
        }
    }

    @Test
    func anEntryIsExtractedByteForByteByItsFullPath() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try ArchiveReader.open(fileURL: makeZip(in: directory), kind: Constants.zipKind)
        let nested = directory.appendingPathComponent("nested.out")
        let root = directory.appendingPathComponent("root.out")

        try ArchiveReader.extract(Constants.nestedEntry, from: source, to: nested)
        try ArchiveReader.extract(Constants.rootEntry, from: source, to: root)

        #expect(try Data(contentsOf: nested) == Constants.nestedBytes)
        #expect(try Data(contentsOf: root) == Constants.rootBytes)
    }

    @Test
    func extractingAgainOverwritesTheEarlierFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try ArchiveReader.open(fileURL: makeZip(in: directory), kind: Constants.zipKind)
        let destination = directory.appendingPathComponent("out.bin")
        try Data(repeating: 0x01, count: 10_000).write(to: destination)

        try ArchiveReader.extract(Constants.nestedEntry, from: source, to: destination)

        #expect(try Data(contentsOf: destination) == Constants.nestedBytes)
    }

    @Test
    func anEntryThatIsNotInTheArchiveIsNotFoundAndLeavesNoFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try ArchiveReader.open(fileURL: makeZip(in: directory), kind: Constants.zipKind)
        let destination = directory.appendingPathComponent("missing.out")

        #expect(throws: ArchiveReaderError.entryNotFound) {
            try ArchiveReader.extract("docs/other.txt", from: source, to: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test
    func theEntryPathMustMatchExactlyNotByItsFileName() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try ArchiveReader.open(fileURL: makeZip(in: directory), kind: Constants.zipKind)

        #expect(throws: ArchiveReaderError.entryNotFound) {
            try ArchiveReader.extract("readme.txt", from: source, to: directory.appendingPathComponent("x.out"))
        }
    }

    @Test(arguments: [ArchiveReader.maxEntrySize + 1, UInt64.max])
    func aDeclaredSizeOverTheCeilingIsRefusedBeforeExtracting(_ size: UInt64) {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(TestID.name())

        #expect(throws: ArchiveReaderError.entryTooLarge) {
            try ArchiveReader.guardExtraction(uncompressedSize: size, destination: destination)
        }
    }

    @Test
    func anEmptyEntryIsAlwaysAllowed() throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(TestID.name())

        #expect(throws: Never.self) {
            try ArchiveReader.guardExtraction(uncompressedSize: 0, destination: destination)
        }
    }
}
