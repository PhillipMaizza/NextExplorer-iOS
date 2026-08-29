import Foundation
import Testing

@testable import CoreModels

@Suite
struct ServerFeaturesTests {
    @Test
    func decodesTheOfficeSections() throws {
        let json = """
        {
            "onlyoffice": { "enabled": true, "extensions": ["docx", "xlsx"] },
            "collabora": { "enabled": false, "extensions": [] },
            "userVolumes": { "enabled": true },
            "volumeUsage": { "enabled": false }
        }
        """.data(using: .utf8)!

        let features = try JSONDecoder().decode(ServerFeatures.self, from: json)

        #expect(features.isUserVolumesEnabled)
        #expect(!features.isVolumeUsageEnabled)
        #expect(features.office.isOnlyOfficeEnabled)
        #expect(features.office.onlyOfficeExtensions == ["docx", "xlsx"])
        #expect(!features.office.isCollaboraEnabled)
        #expect(features.office.collaboraExtensions.isEmpty)
    }

    @Test
    func missingSectionsReadAsOff() throws {
        let features = try JSONDecoder().decode(ServerFeatures.self, from: Data("{}".utf8))

        #expect(!features.isUserVolumesEnabled)
        #expect(!features.office.isOnlyOfficeEnabled)
        #expect(!features.office.isCollaboraEnabled)
        #expect(features.office.onlyOfficeExtensions.isEmpty)
    }

    @Test
    func officeSectionWithoutExtensionsKeyDecodes() throws {
        let json = """
        { "collabora": { "enabled": true } }
        """.data(using: .utf8)!

        let features = try JSONDecoder().decode(ServerFeatures.self, from: json)
        #expect(features.office.isCollaboraEnabled)
        #expect(features.office.collaboraExtensions.isEmpty)
    }
}
