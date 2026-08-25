import Foundation
import Testing
@testable import CoreModels

@Suite("BrowseResult decoding")
struct BrowseResultDecodingTests {
    @Test("decodes items alongside the access object")
    func decodesItemsAndAccess() throws {
        let json = #"""
        {
          "items": [
            {"name": "Docs", "path": "Home", "dateModified": 1800000000, "size": 0, "kind": "directory"}
          ],
          "access": {"canRead": true, "canWrite": false, "canUpload": false, "canDelete": false, "canShare": true, "canDownload": true},
          "path": "Home"
        }
        """#
        let result = try JSONDecoder().decode(BrowseResult.self, from: Data(json.utf8))
        #expect(result.items.count == 1)
        #expect(result.access.canRead == true)
        #expect(result.access.canWrite == false)
        #expect(result.path == "Home")
    }

    @Test("edge case: an empty directory decodes with an empty items array")
    func decodesEmptyDirectory() throws {
        let json = #"""
        {"items": [], "access": {"canRead": true, "canWrite": true, "canUpload": true, "canDelete": true, "canShare": true, "canDownload": true}, "path": ""}
        """#
        let result = try JSONDecoder().decode(BrowseResult.self, from: Data(json.utf8))
        #expect(result.items.isEmpty)
    }

    @Test("error path: missing access object fails to decode")
    func missingAccessThrows() {
        let json = #"{"items": [], "path": "Home"}"#
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(BrowseResult.self, from: Data(json.utf8))
        }
    }
}
