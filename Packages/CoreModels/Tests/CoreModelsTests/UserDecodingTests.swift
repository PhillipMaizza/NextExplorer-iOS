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
}
