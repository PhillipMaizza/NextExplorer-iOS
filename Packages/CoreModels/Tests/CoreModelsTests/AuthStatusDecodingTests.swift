@testable import CoreModels
import Foundation
import Testing

@Suite("AuthStatus decoding")
struct AuthStatusDecodingTests {
    @Test("decodes nested strategies.local / strategies.oidc flags")
    func decodesBothEnabled() throws {
        let json = #"""
        {"requiresSetup": false, "strategies": {"local": true, "oidc": false}, "authEnabled": true}
        """#
        let status = try JSONDecoder().decode(AuthStatus.self, from: Data(json.utf8))
        #expect(status.isLocalEnabled == true)
        #expect(status.isOIDCEnabled == false)
    }
}
