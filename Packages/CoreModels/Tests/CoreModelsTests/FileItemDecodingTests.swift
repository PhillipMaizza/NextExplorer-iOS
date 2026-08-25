import Foundation
import Testing
@testable import CoreModels

@Suite("FileItem decoding")
struct FileItemDecodingTests {
    @Test("decodes a full directory listing entry")
    func decodesFullEntry() throws {
        let json = #"""
        {"name": "Photos", "path": "Home", "dateModified": 1800000000, "size": 4096, "kind": "directory", "supportsThumbnail": true}
        """#
        let item = try JSONDecoder().decode(FileItem.self, from: Data(json.utf8))
        #expect(item.name == "Photos")
        #expect(item.isDirectory == true)
        #expect(item.supportsThumbnail == true)
    }

    @Test("edge case: missing supportsThumbnail defaults to false")
    func missingSupportsThumbnailDefaultsFalse() throws {
        let json = #"""
        {"name": "notes.txt", "path": "Home", "dateModified": 1800000000, "size": 12, "kind": "txt"}
        """#
        let item = try JSONDecoder().decode(FileItem.self, from: Data(json.utf8))
        #expect(item.supportsThumbnail == false)
        #expect(item.isDirectory == false)
    }

    @Test("edge case: id joins path and name when path is non-empty")
    func idJoinsPathAndName() {
        let item = FileItem(name: "file.txt", path: "Home/Docs", dateModified: Date(), size: 0, kind: "txt")
        #expect(item.id == "Home/Docs/file.txt")
    }

    @Test("edge case: id is just the name when path is empty (root level)")
    func idIsNameAtRoot() {
        let item = FileItem(name: "Volume", path: "", dateModified: Date(), size: 0, kind: "directory")
        #expect(item.id == "Volume")
    }

    @Test("error path: missing required field fails to decode")
    func missingRequiredFieldThrows() {
        let json = #"{"name": "file.txt", "path": "Home"}"#
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(FileItem.self, from: Data(json.utf8))
        }
    }

    @Test("round-trips through Codable")
    func codableRoundTrip() throws {
        let original = FileItem(
            name: "report.pdf",
            path: "Home/Docs",
            dateModified: Date(timeIntervalSince1970: 1800000000),
            size: 2048,
            kind: "pdf",
            supportsThumbnail: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FileItem.self, from: data)
        #expect(decoded == original)
    }
}
