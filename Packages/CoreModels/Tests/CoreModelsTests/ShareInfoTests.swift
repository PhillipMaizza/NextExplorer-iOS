@testable import CoreModels
import Foundation
import Testing
import TestUtils

struct ShareInfoTests {
    @Test
    func decodesTheInfoEndpointShape() throws {
        let json = try CoreModelsFixture.shareInfoInfoEndpointShape.data()

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
        let json = try CoreModelsFixture.shareInfoMinimalExpiredUsersShare.data()

        let info = try JSONDecoder().decode(ShareInfo.self, from: json)
        #expect(info.label == nil)
        #expect(info.expiresAt == nil)
        #expect(info.hasPassword)
        #expect(info.isExpired)
        #expect(info.isRestrictedToUsers)
    }
}
