import Foundation
import Testing

@testable import CoreModels

@Suite
struct ShareInfoTests {
    @Test
    func decodesTheInfoEndpointShape() throws {
        let json = """
        {
            "shareToken": "AbC123xyz0",
            "label": "Q3 Report",
            "isDirectory": true,
            "hasPassword": false,
            "sharingType": "anyone",
            "expiresAt": "2027-01-15T10:00:00.000Z",
            "isExpired": false
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: s)!
        }
        let info = try decoder.decode(ShareInfo.self, from: json)

        #expect(info.shareToken == "AbC123xyz0")
        #expect(info.label == "Q3 Report")
        #expect(info.isDirectory)
        #expect(info.sharingType == .anyone)
        #expect(info.expiresAt != nil)
        #expect(!info.isExpired)
        #expect(!info.isRestrictedToUsers)
    }

    @Test
    func decodesAMinimalExpiredUsersShare() throws {
        let json = """
        { "shareToken": "x1y2z3", "isDirectory": false, "hasPassword": true, "sharingType": "users", "isExpired": true }
        """.data(using: .utf8)!

        let info = try JSONDecoder().decode(ShareInfo.self, from: json)
        #expect(info.label == nil)
        #expect(info.expiresAt == nil)
        #expect(info.hasPassword)
        #expect(info.isExpired)
        #expect(info.isRestrictedToUsers)
    }
}
