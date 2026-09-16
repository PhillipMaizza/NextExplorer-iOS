@testable import CoreModels
import Foundation
import Testing

@Suite("FileAccess decoding")
struct FileAccessDecodingTests {
    @Test("happy path: decodes a full read/write grant")
    func decodesFullGrant() throws {
        let json = #"{"canRead": true, "canWrite": true, "canUpload": true, "canDelete": true, "canShare": true, "canDownload": true}"#
        let access = try JSONDecoder().decode(FileAccess.self, from: Data(json.utf8))
        #expect(access.canRead == true)
        #expect(access.canDelete == true)
    }

    @Test("edge case: a read-only grant reports every write-capable flag as false")
    func decodesReadOnlyGrant() throws {
        let json = #"{"canRead": true, "canWrite": false, "canUpload": false, "canDelete": false, "canShare": false, "canDownload": true}"#
        let access = try JSONDecoder().decode(FileAccess.self, from: Data(json.utf8))
        #expect(access.canWrite == false)
        #expect(access.canUpload == false)
        #expect(access.canDelete == false)
        #expect(access.canShare == false)
        #expect(access.canDownload == true)
    }

    @Test("error path: missing required field fails to decode")
    func missingRequiredFieldThrows() {
        let json = #"{"canRead": true}"#
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(FileAccess.self, from: Data(json.utf8))
        }
    }
}
