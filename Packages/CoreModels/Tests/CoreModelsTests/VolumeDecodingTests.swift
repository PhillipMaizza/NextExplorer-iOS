@testable import CoreModels
import Foundation
import Testing

@Suite("Volume decoding")
struct VolumeDecodingTests {
    @Test("happy path: decodes name, path and accessMode")
    func decodesFullVolume() throws {
        let volume = try CoreModelsFixture.volumeWithAccessMode.decode(Volume.self)
        #expect(volume.name == "Media")
        #expect(volume.id == "/mnt/media")
        #expect(volume.accessMode == "readOnly")
    }

    @Test("edge case: accessMode absent (not a per-user assignment) decodes to nil")
    func missingAccessModeDecodesNil() throws {
        let volume = try CoreModelsFixture.volumeWithoutAccessMode.decode(Volume.self)
        #expect(volume.accessMode == nil)
    }
}
