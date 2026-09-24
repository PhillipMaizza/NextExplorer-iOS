@testable import FilesFeature
import Foundation
import Testing

struct UploadStagingFolderTests {
    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test
    func aDroppedFolderExpandsIntoItsFilesWithRelativeNames() throws {
        let source = try temporaryFolder().appendingPathComponent("Trip", isDirectory: true)
        try write("a", to: source.appendingPathComponent("a.txt"))
        try write("b", to: source.appendingPathComponent("Day 1/b.txt"))
        try write("hidden", to: source.appendingPathComponent(".DS_Store"))
        let staging = try temporaryFolder()

        let files = UploadStagingLocation.stage(source, into: staging)

        #expect(Set(files.map(\.fileName)) == ["Trip/a.txt", "Trip/Day 1/b.txt"])
        for file in files {
            #expect(file.fileURL.deletingLastPathComponent().standardizedFileURL == staging.standardizedFileURL)
            #expect(file.size == 1)
        }
    }

    @Test
    func aSingleFileKeepsItsPlainName() throws {
        let folder = try temporaryFolder()
        let file = folder.appendingPathComponent("report.pdf")
        try write("pdf", to: file)

        let files = try UploadStagingLocation.stage(file, into: temporaryFolder())

        #expect(files.map(\.fileName) == ["report.pdf"])
    }
}
