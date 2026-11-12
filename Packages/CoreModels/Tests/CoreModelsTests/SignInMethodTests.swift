@testable import CoreModels
import Foundation
import Testing

@Suite("SignInMethod")
struct SignInMethodTests {
    @Test("decodes the methods the server lists, with dates that may be null")
    func decodes() throws {
        let methods = try CoreModelsFixture.signInMethodPasswordAndOidcList.decode([SignInMethod].self)
        #expect(methods.map(\.id) == ["m1", "m2"])
        #expect(methods[1].provider == "PocketID")
        #expect(methods[1].lastUsedAt == nil)
    }

    @Test("an account with a password method has a password")
    func hasPassword() throws {
        let methods = try CoreModelsFixture.signInMethodPasswordAndOidcList.decode([SignInMethod].self)
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
        let methods = try CoreModelsFixture.signInMethodListWithoutDates.decode([SignInMethod].self)
        #expect(methods.first?.lastUsedAt == nil)
        #expect(methods.hasPassword)
    }
}
