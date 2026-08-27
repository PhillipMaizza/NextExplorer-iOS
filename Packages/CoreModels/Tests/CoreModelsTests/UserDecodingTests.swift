import Foundation
import Testing
@testable import CoreModels

@Suite("User decoding")
struct UserDecodingTests {
    @Test("decodes with email and admin role")
    func decodesFullUser() throws {
        let json = #"""
        {"id": "1", "username": "phillip", "email": "p@example.com", "displayName": "Phillip", "roles": ["admin", "user"]}
        """#
        let user = try JSONDecoder().decode(User.self, from: Data(json.utf8))
        #expect(user.id == "1")
        #expect(user.username == "phillip")
        #expect(user.email == "p@example.com")
        #expect(user.isAdmin == true)
    }

    @Test("edge case: nil email and missing roles default to non-admin")
    func decodesMissingEmailAndRoles() throws {
        let json = #"{"id": "2", "username": "guest"}"#
        let user = try JSONDecoder().decode(User.self, from: Data(json.utf8))
        #expect(user.email == nil)
        #expect(user.isAdmin == false)
        #expect(user.roles == [])
    }

    @Test("edge case: a non-admin role list does not grant admin")
    func nonAdminRoleIsNotAdmin() throws {
        let json = #"{"id": "3", "username": "bob", "roles": ["user"]}"#
        let user = try JSONDecoder().decode(User.self, from: Data(json.utf8))
        #expect(user.isAdmin == false)
    }

    @Test("edge case: an integer id decodes as a string")
    func integerIDDecodesAsString() throws {
        let json = #"{"id": 42, "username": "bob"}"#
        let user = try JSONDecoder().decode(User.self, from: Data(json.utf8))
        #expect(user.id == "42")
    }

    @Test("regression: ISO-string createdAt/updatedAt decode through a plain decoder (login response)")
    func isoTimestampsDoNotBreakAPlainDecode() throws {
        let json = #"""
        {"id": "1", "username": "phillip", "email": "p@example.com", "roles": ["user"],
         "emailVerified": true, "createdAt": "2024-01-15T10:30:00.000Z", "updatedAt": "2024-02-20T08:00:00.000Z"}
        """#
        let user = try JSONDecoder().decode(User.self, from: Data(json.utf8))
        #expect(user.username == "phillip")
        #expect(user.emailVerified == true)
        #expect(user.createdAt != nil)
        #expect(user.updatedAt != nil)
    }

    @Test("edge case: an unparseable timestamp degrades to nil rather than throwing")
    func garbageTimestampDegradesToNil() throws {
        let json = #"{"id": "1", "username": "x", "createdAt": "not-a-date", "updatedAt": 0}"#
        let user = try JSONDecoder().decode(User.self, from: Data(json.utf8))
        #expect(user.createdAt == nil)
    }

    @Test("edge case: a null or missing username degrades to empty, never throws")
    func nullUsernameDoesNotBreakTheDecode() throws {
        let nullUsername = try JSONDecoder().decode(
            User.self, from: Data(#"{"id": "1", "username": null, "email": "p@example.com"}"#.utf8)
        )
        #expect(nullUsername.username == "")
        let missingUsername = try JSONDecoder().decode(
            User.self, from: Data(#"{"id": "2", "email": "q@example.com"}"#.utf8)
        )
        #expect(missingUsername.username == "")
    }

    @Test("decodes the admin list shape with authMethods")
    func decodesAuthMethods() throws {
        let json = #"""
        {"id": "1", "username": "phillip", "roles": ["admin"],
         "authMethods": [{"method": "local_password"}, {"method": "oidc", "provider": "Authentik"}]}
        """#
        let user = try JSONDecoder().decode(User.self, from: Data(json.utf8))
        #expect(user.hasLocalPassword)
        #expect(user.oidcMethods.first?.provider == "Authentik")
    }
}
