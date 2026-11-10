@testable import CoreModels
import Foundation
import Testing

@Suite("APIToken")
struct APITokenTests {
    private let json = #"{"id":"t1","name":"backup script","scope":"write","createdAt":"2026-11-10T07:00:00.000Z","expiresAt":"2027-01-01T00:00:00.000Z","lastUsedAt":"2026-11-11T08:00:00.000Z","lastUsedIp":"10.0.0.5"}"#

    @Test("decodes a token with every field")
    func decodesFull() throws {
        let token = try JSONDecoder().decode(APIToken.self, from: Data(json.utf8))
        #expect(token == APIToken(
            id: "t1", name: "backup script", scope: .write,
            createdAt: "2026-11-10T07:00:00.000Z", expiresAt: "2027-01-01T00:00:00.000Z",
            lastUsedAt: "2026-11-11T08:00:00.000Z", lastUsedIp: "10.0.0.5"
        ))
    }

    @Test("edge case: a token that never expires and was never used has null dates")
    func decodesNeverExpiresNeverUsed() throws {
        let data = Data(#"{"id":"t2","name":"x","scope":"read","createdAt":"2026-11-10T07:00:00.000Z","expiresAt":null,"lastUsedAt":null,"lastUsedIp":null}"#.utf8)
        let token = try JSONDecoder().decode(APIToken.self, from: data)
        #expect(token.scope == .read)
        #expect(token.expiresAt == nil)
        #expect(token.lastUsedAt == nil)
        #expect(token.lastUsedIp == nil)
    }

    @Test("edge case: a scope the app does not know does not decode, rather than becoming read or write")
    func unknownScopeFails() {
        let data = Data(#"{"id":"t3","name":"x","scope":"admin","createdAt":"2026-11-10T07:00:00.000Z"}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(APIToken.self, from: data) }
    }

    @Test("a token reads, or it reads and writes")
    func scopesAreReadAndWrite() {
        #expect(APIToken.Scope.allCases.map(\.rawValue) == ["read", "write"])
    }

    @Test("the issued token carries the secret next to the token")
    func decodesIssued() throws {
        let data = Data(#"{"token":\#(json),"secret":"nxt_abc.def"}"#.utf8)
        let issued = try JSONDecoder().decode(IssuedAPIToken.self, from: data)
        #expect(issued.secret == "nxt_abc.def")
        #expect(issued.token.id == "t1")
    }

    @Test("an issued token is identified by its token, so a sheet can be driven by it")
    func issuedIsIdentifiedByItsToken() throws {
        let data = Data(#"{"token":\#(json),"secret":"s"}"#.utf8)
        let issued = try JSONDecoder().decode(IssuedAPIToken.self, from: data)
        #expect(issued.id == "t1")
    }
}
