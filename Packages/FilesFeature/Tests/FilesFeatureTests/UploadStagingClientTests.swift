import Foundation
import Testing

@testable import FilesFeature

@Suite
struct UploadStagingClientTests {
    @Test
    func discardDeletesStagedFilesAndIgnoresMissingOnes() async throws {
        let directory = UploadStagingLocation.directory
        let present = directory.appendingPathComponent("\(UUID().uuidString)-present.txt")
        let missing = directory.appendingPathComponent("\(UUID().uuidString)-missing.txt")
        try Data("x".utf8).write(to: present)

        await UploadStagingClient.liveValue.discard([present, missing])

        #expect(FileManager.default.fileExists(atPath: present.path) == false)
    }

    @Test
    func stageCameraCaptureWrapsAnAlreadyWrittenFileWithItsSize() async throws {
        let directory = UploadStagingLocation.directory
        let url = directory.appendingPathComponent("\(UUID().uuidString)-Photo.jpg")
        try Data(count: 128).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let picked = await UploadStagingClient.liveValue.stageCameraCapture(url)

        #expect(picked?.fileName == url.lastPathComponent)
        #expect(picked?.size == 128)
    }
}
