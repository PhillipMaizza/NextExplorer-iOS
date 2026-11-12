@testable import CoreModels
import Foundation
import Testing
import TestUtils

@Suite("FileMetadata decoding")
struct FileMetadataDecodingTests {
    @Test("decodes a plain file with no image/video/directory payload")
    func decodesAPlainFile() throws {
        let metadata = try CoreModelsFixture.fileMetadataPlainFile.decode(FileMetadata.self)
        #expect(metadata.name == TestFile.notes)
        #expect(metadata.isDirectory == false)
        #expect(metadata.directory == nil)
        #expect(metadata.image == nil)
        #expect(metadata.video == nil)
    }

    @Test("decodes a directory's recursive summary")
    func decodesADirectorySummary() throws {
        let metadata = try CoreModelsFixture.fileMetadataDirectorySummary.decode(FileMetadata.self)
        #expect(metadata.isDirectory == true)
        #expect(metadata.directory?.fileCount == 42)
        #expect(metadata.directory?.dirCount == 3)
        #expect(metadata.directory?.truncated == false)
    }

    @Test("decodes full image EXIF data including GPS")
    func decodesImageMetadataWithGPS() throws {
        let metadata = try CoreModelsFixture.fileMetadataImageWithGps.decode(FileMetadata.self)
        #expect(metadata.image?.width == 4032)
        #expect(metadata.image?.cameraMake == "Apple")
        #expect(metadata.image?.lensModel == nil)
        #expect(metadata.image?.gps?.lat == 37.3349)
    }

    @Test("edge case: image metadata with no EXIF fields at all, only dimensions")
    func decodesImageMetadataWithoutEXIF() throws {
        let metadata = try CoreModelsFixture.fileMetadataImageDimensionsOnly.decode(FileMetadata.self)
        #expect(metadata.image?.width == 800)
        #expect(metadata.image?.cameraMake == nil)
        #expect(metadata.image?.gps == nil)
    }

    @Test("decodes video dimensions and duration")
    func decodesVideoMetadata() throws {
        let metadata = try CoreModelsFixture.fileMetadataVideo.decode(FileMetadata.self)
        #expect(metadata.video?.width == 1920)
        #expect(metadata.video?.duration == 42.5)
    }
}
