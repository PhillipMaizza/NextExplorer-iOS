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
        #expect(status.localEnabled == true)
        #expect(status.oidcEnabled == false)
    }

    @Test("edge case: extra unrelated top-level fields are ignored")
    func ignoresExtraFields() throws {
        let json = #"""
        {"strategies": {"local": false, "oidc": true}, "authMode": "both", "authenticated": false, "user": null}
        """#
        let status = try JSONDecoder().decode(AuthStatus.self, from: Data(json.utf8))
        #expect(status.localEnabled == false)
        #expect(status.oidcEnabled == true)
    }
}
