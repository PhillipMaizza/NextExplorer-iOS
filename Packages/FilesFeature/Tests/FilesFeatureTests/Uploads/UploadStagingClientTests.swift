@testable import FilesFeature
import Foundation
import Testing
import TestUtils

struct UploadStagingClientTests {
    @Test
    func discardDeletesStagedFilesAndIgnoresMissingOnes() async throws {
        let directory = UploadStagingLocation.directory
        let present = directory.appendingPathComponent("\(TestID.name())-present.txt")
        let missing = directory.appendingPathComponent("\(TestID.name())-missing.txt")
        try Data("x".utf8).write(to: present)

        await UploadStagingClient.liveValue.discard([present, missing])

        #expect(FileManager.default.fileExists(atPath: present.path) == false)
    }

    @Test
    func sweepStaleDeletesOldStagedFilesButKeepsRecentOnes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(TestID.name())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = directory.appendingPathComponent(TestFile.notes)
        let fresh = directory.appendingPathComponent(TestFile.report)
        try Data("x".utf8).write(to: old)
        try Data("x".utf8).write(to: fresh)
        try FileManager.default.setAttributes(
            [.modificationDate: MockDate.date.addingTimeInterval(-1)],
            ofItemAtPath: old.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: MockDate.date.addingTimeInterval(1)],
            ofItemAtPath: fresh.path
        )

        UploadStagingLocation.sweepStale(in: [directory], olderThan: MockDate.date)

        #expect(FileManager.default.fileExists(atPath: old.path) == false)
        #expect(FileManager.default.fileExists(atPath: fresh.path) == true)
    }

    @Test
    func stageCameraCaptureWrapsAnAlreadyWrittenFileWithItsSize() async throws {
        let directory = UploadStagingLocation.directory
        let url = directory.appendingPathComponent("\(TestID.name())-Photo.jpg")
        try Data(count: 128).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let picked = await UploadStagingClient.liveValue.stageCameraCapture(url)

        #expect(picked?.fileName == url.lastPathComponent)
        #expect(picked?.size == 128)
    }
}
