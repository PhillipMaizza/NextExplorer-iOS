@testable import CoreModels
import Foundation
import Testing

@Suite("SignInMethod")
struct SignInMethodTests {
    private let json = Data(#"""
    [
      {"id":"m1","type":"local_password","provider":"Password","lastUsedAt":"2026-11-10T07:00:00.000Z","createdAt":"2026-11-01T10:00:00.000Z"},
      {"id":"m2","type":"oidc","provider":"PocketID","lastUsedAt":null,"createdAt":"2026-11-02T10:00:00.000Z"}
    ]
    """#.utf8)

    @Test("decodes the methods the server lists, with dates that may be null")
    func decodes() throws {
        let methods = try JSONDecoder().decode([SignInMethod].self, from: json)
        #expect(methods.map(\.id) == ["m1", "m2"])
        #expect(methods[1].provider == "PocketID")
        #expect(methods[1].lastUsedAt == nil)
    }

    @Test("an account with a password method has a password")
    func hasPassword() throws {
        let methods = try JSONDecoder().decode([SignInMethod].self, from: json)
        #expect(methods.hasPassword)
    }

    @Test("a single sign on account has no password")
    func ssoOnlyHasNoPassword() {
        let methods = [SignInMethod(id: "m2", type: "oidc", provider: "PocketID")]
        #expect(!methods.hasPassword)
    }

    @Test("edge case: no methods at all means no password")
    func emptyHasNoPassword() {
        #expect(![SignInMethod]().hasPassword)
    }

    @Test("edge case: a provider named like the password type does not count, only the type does")
    func onlyTheTypeCounts() {
        let methods = [SignInMethod(id: "m3", type: "oidc", provider: SignInMethod.localPasswordType)]
        #expect(!methods.hasPassword)
    }

    @Test("edge case: a server that omits the dates still decodes")
    func decodesWithoutDates() throws {
        let data = Data(#"[{"id":"m4","type":"local_password","provider":"Password"}]"#.utf8)
        let methods = try JSONDecoder().decode([SignInMethod].self, from: data)
        #expect(methods.first?.lastUsedAt == nil)
        #expect(methods.hasPassword)
    }
}
