@testable import CoreModels
import Foundation
import Testing
import TestUtils

@Suite("APIToken")
struct APITokenTests {
    @Test("decodes a token with every field")
    func decodesFull() throws {
        let token = try CoreModelsFixture.apiTokenFull.decode(APIToken.self)
        #expect(token == APIToken(
            id: "t1", name: "backup script", scope: .write,
            createdAt: "2026-11-10T07:00:00.000Z", expiresAt: "2027-01-01T00:00:00.000Z",
            lastUsedAt: "2026-11-11T08:00:00.000Z", lastUsedIp: "10.0.0.5"
        ))
    }

    @Test("edge case: a token that never expires and was never used has null dates")
    func decodesNeverExpiresNeverUsed() throws {
        let token = try CoreModelsFixture.apiTokenNeverExpiresNeverUsed.decode(APIToken.self)
        #expect(token.scope == .read)
        #expect(token.expiresAt == nil)
        #expect(token.lastUsedAt == nil)
        #expect(token.lastUsedIp == nil)
    }

    @Test("edge case: a scope the app does not know does not decode, rather than becoming read or write")
    func unknownScopeFails() throws {
        let data = try CoreModelsFixture.apiTokenUnknownScope.data()
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(APIToken.self, from: data) }
    }

    @Test("a token reads, or it reads and writes")
    func scopesAreReadAndWrite() {
        #expect(APIToken.Scope.allCases.map(\.rawValue) == ["read", "write"])
    }

    @Test("the issued token carries the secret next to the token")
    func decodesIssued() throws {
        let issued = try CoreModelsFixture.apiTokenIssuedWithSecret.decode(IssuedAPIToken.self)
        #expect(issued.secret == "nxt_abc.def")
        #expect(issued.token.id == "t1")
    }

    @Test("an issued token is identified by its token, so a sheet can be driven by it")
    func issuedIsIdentifiedByItsToken() throws {
        let issued = try CoreModelsFixture.apiTokenIssuedWithShortSecret.decode(IssuedAPIToken.self)
        #expect(issued.id == "t1")
    }
}
