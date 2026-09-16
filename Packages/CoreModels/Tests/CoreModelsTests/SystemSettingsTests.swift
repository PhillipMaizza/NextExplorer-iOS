@testable import CoreModels
import Foundation
import Testing

struct SystemSettingsTests {
    @Test
    func decodesTheFullAdminShape() throws {
        let json = """
        {
            "branding": { "appName": "X" },
            "user": { "showHiddenFiles": true },
            "thumbnails": { "enabled": false, "size": 512, "quality": 90, "concurrency": 4 },
            "access": { "rules": [
                { "id": "r1", "path": "Documents/Reports", "recursive": true, "permissions": "ro" },
                { "id": "r2", "path": "Private", "recursive": false, "permissions": "hidden" }
            ] }
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(SystemSettings.self, from: json)

        #expect(settings.thumbnails?.isEnabled == false)
        #expect(settings.thumbnails?.size == 512)
        #expect(settings.thumbnails?.quality == 90)
        #expect(settings.thumbnails?.concurrency == 4)
        #expect(settings.accessRules.count == 2)
        #expect(settings.accessRules[0].permission == .readOnly)
        #expect(settings.accessRules[0].isRecursive)
        #expect(settings.accessRules[1].permission == .hidden)
        #expect(!settings.accessRules[1].isRecursive)
    }

    @Test
    func aNonAdminShapeHasNoThumbnailsOrRules() throws {
        let json = """
        { "branding": { "appName": "X" }, "user": {} }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(SystemSettings.self, from: json)
        #expect(settings.thumbnails == nil)
        #expect(settings.accessRules.isEmpty)
    }

    @Test
    func thumbnailSettingsFillsMissingKeysFromServerDefaults() throws {
        let settings = try JSONDecoder().decode(ThumbnailSettings.self, from: Data("{}".utf8))
        #expect(settings.isEnabled)
        #expect(settings.size == 200)
        #expect(settings.quality == 70)
        #expect(settings.concurrency == 10)
    }

    @Test
    func accessRulePermissionRawValuesMatchTheServer() {
        #expect(AccessRule.Permission.readWrite.rawValue == "rw")
        #expect(AccessRule.Permission.readOnly.rawValue == "ro")
        #expect(AccessRule.Permission.hidden.rawValue == "hidden")
    }

    @Test
    func accessRuleRoundTripsThroughCodableWithServerKeys() throws {
        let rule = AccessRule(id: "r1", path: "a/b", isRecursive: true, permission: .readOnly)
        let data = try JSONEncoder().encode(rule)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["recursive"] as? Bool == true)
        #expect(object["permissions"] as? String == "ro")

        let decoded = try JSONDecoder().decode(AccessRule.self, from: data)
        #expect(decoded == rule)
    }
}
