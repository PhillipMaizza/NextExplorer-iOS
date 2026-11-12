@testable import CoreModels
import Foundation
import Testing
import TestUtils

@Suite("User encoding")
struct UserEncodingTests {
    private func object(_ user: User) throws -> [String: Any] {
        let data = try JSONEncoder().encode(user)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("an admin with every field survives encode and decode")
    func roundTripKeepsEveryField() throws {
        let user = User(
            id: "7",
            username: TestAccount.username,
            email: "p@example.com",
            displayName: "Phillip",
            roles: [UserRole.admin],
            emailVerified: true,
            createdAt: MockDate.date,
            updatedAt: MockDate.date.addingTimeInterval(60),
            authMethods: [AuthMethod(method: "password"), AuthMethod(method: "oidc", provider: "google")]
        )
        let data = try JSONEncoder().encode(user)
        #expect(try JSONDecoder().decode(User.self, from: data) == user)
    }

    @Test("optional fields that are nil are omitted while roles and flags are always written")
    func omitsNilOptionals() throws {
        let json = try object(User(id: "1", username: TestUser.alice, email: nil))
        #expect(Set(json.keys) == ["id", "username", "roles", "emailVerified", "authMethods"])
        #expect(json["roles"] as? [String] == [])
        #expect(json["emailVerified"] as? Bool == false)
    }
}
