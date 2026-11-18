@testable import CoreModels
import Foundation
import Testing

@Suite("AuthStatus decoding")
struct AuthStatusDecodingTests {
    @Test("decodes nested strategies.local / strategies.oidc flags")
    func decodesBothEnabled() throws {
        let status = try CoreModelsFixture.authStatusLocalEnabledOidcDisabled.decode(AuthStatus.self)
        #expect(status.isLocalEnabled == true)
        #expect(status.isOIDCEnabled == false)
    }
}
