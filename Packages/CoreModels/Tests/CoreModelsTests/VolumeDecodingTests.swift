@testable import CoreModels
import Foundation
import Testing

@Suite("Volume decoding")
struct VolumeDecodingTests {
    @Test("happy path: decodes name, path and accessMode")
    func decodesFullVolume() throws {
        let json = #"{"name": "Media", "path": "/mnt/media", "accessMode": "readOnly"}"#
        let volume = try JSONDecoder().decode(Volume.self, from: Data(json.utf8))
        #expect(volume.name == "Media")
        #expect(volume.id == "/mnt/media")
        #expect(volume.accessMode == "readOnly")
    }

    @Test("edge case: accessMode absent (not a per-user assignment) decodes to nil")
    func missingAccessModeDecodesNil() throws {
        let json = #"{"name": "Media", "path": "/mnt/media"}"#
        let volume = try JSONDecoder().decode(Volume.self, from: Data(json.utf8))
        #expect(volume.accessMode == nil)
    }

    @Test("error path: missing required field fails to decode")
    func missingRequiredFieldThrows() {
        let json = #"{"name": "Media"}"#
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(Volume.self, from: Data(json.utf8))
        }
    }
}
