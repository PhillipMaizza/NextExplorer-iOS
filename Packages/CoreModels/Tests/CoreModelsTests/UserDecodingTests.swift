@testable import CoreModels
import Foundation
import Testing

@Suite("User decoding")
struct UserDecodingTests {
    @Test("decodes with email and admin role")
    func decodesFullUser() throws {
        let user = try CoreModelsFixture.userAdminWithEmail.decode(User.self)
        #expect(user.id == "1")
        #expect(user.username == "phillip")
        #expect(user.email == "p@example.com")
        #expect(user.isAdmin == true)
    }

    @Test("edge case: nil email and missing roles default to non-admin")
    func decodesMissingEmailAndRoles() throws {
        let user = try CoreModelsFixture.userGuestMissingEmailAndRoles.decode(User.self)
        #expect(user.email == nil)
        #expect(user.isAdmin == false)
        #expect(user.roles == [])
    }

    @Test("edge case: a non-admin role list does not grant admin")
    func nonAdminRoleIsNotAdmin() throws {
        let user = try CoreModelsFixture.userNonAdminRole.decode(User.self)
        #expect(user.isAdmin == false)
    }

    @Test("edge case: an integer id decodes as a string")
    func integerIDDecodesAsString() throws {
        let user = try CoreModelsFixture.userIntegerId.decode(User.self)
        #expect(user.id == "42")
    }

    @Test("regression: ISO-string createdAt/updatedAt decode through a plain decoder (login response)")
    func isoTimestampsDoNotBreakAPlainDecode() throws {
        let user = try CoreModelsFixture.userLoginResponseIsoTimestamps.decode(User.self)
        #expect(user.username == "phillip")
        #expect(user.emailVerified == true)
        #expect(user.createdAt != nil)
        #expect(user.updatedAt != nil)
    }

    @Test("edge case: an unparseable timestamp degrades to nil rather than throwing")
    func garbageTimestampDegradesToNil() throws {
        let user = try CoreModelsFixture.userGarbageTimestamp.decode(User.self)
        #expect(user.createdAt == nil)
    }

    @Test("edge case: a null or missing username degrades to empty, never throws")
    func nullUsernameDoesNotBreakTheDecode() throws {
        let nullUsername = try CoreModelsFixture.userNullUsername.decode(User.self)
        #expect(nullUsername.username == "")
        let missingUsername = try CoreModelsFixture.userMissingUsername.decode(User.self)
        #expect(missingUsername.username == "")
    }

    @Test("decodes the admin list shape with authMethods")
    func decodesAuthMethods() throws {
        let user = try CoreModelsFixture.userAdminWithAuthMethods.decode(User.self)
        #expect(user.hasLocalPassword)
        #expect(user.oidcMethods.first?.provider == "Authentik")
    }
}
