@testable import CoreModels
import Foundation
import Testing

@Suite("FileMetadata decoding")
struct FileMetadataDecodingTests {
    @Test("decodes a plain file with no image/video/directory payload")
    func decodesAPlainFile() throws {
        let json = #"""
        {"path": "Home/notes.txt", "name": "notes.txt", "kind": "txt", "size": 128, "dateModified": 1800000000, "dateCreated": 1700000000}
        """#
        let metadata = try JSONDecoder().decode(FileMetadata.self, from: Data(json.utf8))
        #expect(metadata.name == "notes.txt")
        #expect(metadata.isDirectory == false)
        #expect(metadata.directory == nil)
        #expect(metadata.image == nil)
        #expect(metadata.video == nil)
    }

    @Test("decodes a directory's recursive summary")
    func decodesADirectorySummary() throws {
        let json = #"""
        {"path": "Home/Photos", "name": "Photos", "kind": "directory", "size": 4096, "dateModified": 1800000000, "dateCreated": 1700000000,
         "directory": {"totalSize": 10485760, "fileCount": 42, "dirCount": 3, "truncated": false}}
        """#
        let metadata = try JSONDecoder().decode(FileMetadata.self, from: Data(json.utf8))
        #expect(metadata.isDirectory == true)
        #expect(metadata.directory?.fileCount == 42)
        #expect(metadata.directory?.dirCount == 3)
        #expect(metadata.directory?.truncated == false)
    }

    @Test("decodes full image EXIF data including GPS")
    func decodesImageMetadataWithGPS() throws {
        let json = #"""
        {"path": "Home/vacation.jpg", "name": "vacation.jpg", "kind": "jpg", "size": 2400000, "dateModified": 1800000000, "dateCreated": 1700000000,
         "image": {"width": 4032, "height": 3024, "orientation": 1, "cameraMake": "Apple", "cameraModel": "iPhone 15 Pro",
                   "lensModel": null, "software": "17.0", "dateTaken": 1750000000, "gps": {"lat": 37.3349, "lon": -122.0090}}}
        """#
        let metadata = try JSONDecoder().decode(FileMetadata.self, from: Data(json.utf8))
        #expect(metadata.image?.width == 4032)
        #expect(metadata.image?.cameraMake == "Apple")
        #expect(metadata.image?.lensModel == nil)
        #expect(metadata.image?.gps?.lat == 37.3349)
    }

    @Test("edge case: image metadata with no EXIF fields at all, only dimensions")
    func decodesImageMetadataWithoutEXIF() throws {
        let json = #"""
        {"path": "Home/scan.png", "name": "scan.png", "kind": "png", "size": 512, "dateModified": 1800000000, "dateCreated": 1700000000,
         "image": {"width": 800, "height": 600, "orientation": null}}
        """#
        let metadata = try JSONDecoder().decode(FileMetadata.self, from: Data(json.utf8))
        #expect(metadata.image?.width == 800)
        #expect(metadata.image?.cameraMake == nil)
        #expect(metadata.image?.gps == nil)
    }

    @Test("decodes video dimensions and duration")
    func decodesVideoMetadata() throws {
        let json = #"""
        {"path": "Home/clip.mp4", "name": "clip.mp4", "kind": "mp4", "size": 9000000, "dateModified": 1800000000, "dateCreated": 1700000000,
         "video": {"width": 1920, "height": 1080, "duration": 42.5}}
        """#
        let metadata = try JSONDecoder().decode(FileMetadata.self, from: Data(json.utf8))
        #expect(metadata.video?.width == 1920)
        #expect(metadata.video?.duration == 42.5)
    }

    @Test("error path: missing required field fails to decode")
    func missingRequiredFieldThrows() {
        let json = #"{"name": "notes.txt", "kind": "txt"}"#
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(FileMetadata.self, from: Data(json.utf8))
        }
    }

    @Test("round-trips through Codable")
    func codableRoundTrip() throws {
        let original = FileMetadata(
            path: "Home/vacation.jpg",
            name: "vacation.jpg",
            kind: "jpg",
            size: 2_400_000,
            dateModified: Date(timeIntervalSince1970: 1_800_000_000),
            dateCreated: Date(timeIntervalSince1970: 1_700_000_000),
            image: FileMetadata.ImageMetadata(width: 4032, height: 3024, cameraMake: "Apple")
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FileMetadata.self, from: data)
        #expect(decoded == original)
    }
}
