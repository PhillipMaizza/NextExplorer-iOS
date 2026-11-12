@testable import CoreModels
import Foundation
import Testing
import TestUtils

@Suite("AuthStatus encoding")
struct AuthStatusEncodingTests {
    private func object(_ status: AuthStatus) throws -> [String: Any] {
        let data = try JSONEncoder().encode(status)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("encodes the nested strategies shape the server uses and nothing else")
    func encodesNestedStrategies() throws {
        let json = try object(AuthStatus(localEnabled: true, oidcEnabled: false, redirectsToHTTPS: true, redirectedPort: 8443))
        #expect(Set(json.keys) == ["strategies"])
        let strategies = try #require(json["strategies"] as? [String: Bool])
        #expect(strategies == ["local": true, "oidc": false])
    }

    @Test("an encoded status decodes back to the same flags and drops the client only redirect fields")
    func roundTripDropsRedirectFields() throws {
        let status = AuthStatus(localEnabled: false, oidcEnabled: true, redirectsToHTTPS: true, redirectedPort: 8443)
        let data = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(AuthStatus.self, from: data)
        #expect(decoded == AuthStatus(localEnabled: false, oidcEnabled: true))
        #expect(!decoded.redirectsToHTTPS)
        #expect(decoded.redirectedPort == nil)
    }

}
