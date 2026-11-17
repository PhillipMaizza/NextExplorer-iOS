@testable import FilesFeature
import Foundation
import Testing
import TestUtils

@Suite(.serialized)
struct AudioArtworkTests {
    private enum Constants {
        static let sampleRate: UInt32 = 8000
        static let samples = 800
        static let maxPixel: CGFloat = 64
    }

    /// A valid, silent WAV file: audio AVFoundation reads, with no tags and so no cover art.
    private func silentWAV() -> Data {
        func le32(_ value: UInt32) -> Data {
            withUnsafeBytes(of: value.littleEndian) { Data($0) }
        }
        func le16(_ value: UInt16) -> Data {
            withUnsafeBytes(of: value.littleEndian) { Data($0) }
        }
        let payload = Data(count: Constants.samples * 2)
        var data = Data("RIFF".utf8)
        data += le32(UInt32(36 + payload.count))
        data += Data("WAVEfmt ".utf8)
        data += le32(16) + le16(1) + le16(1)
        data += le32(Constants.sampleRate) + le32(Constants.sampleRate * 2) + le16(2) + le16(16)
        data += Data("data".utf8) + le32(UInt32(payload.count)) + payload
        return data
    }

    @Test("An audio file with no tags has no cover art")
    func aFileWithoutTagsHasNoArtwork() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioArtworkTests-\(TestID.name()).wav")
        try silentWAV().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let image = await AudioArtwork.image(url: url, fileExtension: "wav", maxPixel: Constants.maxPixel)

        #expect(image == nil)
    }

    @Test("A file that is not audio at all has no cover art and does not fail")
    func aFileThatIsNotAudioHasNoArtwork() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioArtworkTests-\(TestID.name()).mp3")
        try Data("not audio".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let image = await AudioArtwork.image(url: url, fileExtension: "mp3", maxPixel: Constants.maxPixel)

        #expect(image == nil)
    }
}
