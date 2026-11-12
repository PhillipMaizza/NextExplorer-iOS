import CoreModels
@testable import FilesClient
import Foundation
import NetworkClient
import Testing
import TestUtils

/// The admin user management routes through `FilesClient.live` against a stubbed `URLSession`. Nested in
/// `FilesClientLiveTests` so it inherits `.serialized`: every live client suite shares `StubURLProtocol`'s statics.
extension FilesClientLiveTests {
    struct FilesClientAdminUserTests: FilesClientLiveHarness {
        private enum Constants {
            static let volumeID = "v1"
            static let archiveVolumeID = "v2"
            static let volumeLabel = "Projects"
            static let volumePath = "/srv/projects"
            static let serverRoot = "/srv"
            static let userID = "u1"
            static let newEmail = "new@example.com"
            static let newPassword = "s3cret-pass"
            static let displayName = "Alice A"
        }

        // MARK: listUsers

        @Test
        func listUsersGetsTheUsersRouteAndDecodesEachUser() async throws {
            try prepare(statusCode: 200, fixture: .adminUsersListTwo)

            let users = try await makeClient().listUsers(serverURL)

            try expectRequest(.get, "/api/users")
            expectNoBody()
            #expect(users.map(\.id) == ["u1", "2"])
            #expect(users[0].username == TestUser.alice)
            #expect(users[0].email == "alice@example.com")
            #expect(users[0].displayName == Constants.displayName)
            #expect(users[0].isAdmin)
            #expect(users[0].emailVerified)
            #expect(users[0].createdAt != nil)
            #expect(users[0].updatedAt != nil)
        }

        @Test
        func listUsersKeepsARowWithANumericIDAndANullUsername() async throws {
            try prepare(statusCode: 200, fixture: .adminUsersListTwo)

            let users = try await makeClient().listUsers(serverURL)

            #expect(users[1].id == "2")
            #expect(users[1].username.isEmpty)
            #expect(users[1].email == nil)
            #expect(users[1].roles.isEmpty)
            #expect(!users[1].isAdmin)
        }

        @Test
        func listUsersSurfacesTheAdminRequiredReasonOnA403() async throws {
            try prepare(statusCode: 403, fixture: .commonErrorAdminRequired)

            await #expect(throws: FilesClientError.forbidden(message: "Admin access required.")) {
                _ = try await makeClient().listUsers(serverURL)
            }
        }

        @Test
        func listUsersFailsToDecodeAnEnvelopeWithoutUsers() async throws {
            try prepare(statusCode: 200, fixture: .commonEmptyObject)

            await #expect {
                _ = try await makeClient().listUsers(serverURL)
            } throws: { error in
                guard case .decoding = error as? FilesClientError else { return false }
                return true
            }
        }

        // MARK: createUser

        @Test
        func createUserPostsOnlyTheFieldsItWasGiven() async throws {
            try prepare(statusCode: 201, fixture: .adminUsersSingle)

            let user = try await makeClient().createUser(
                serverURL, CreateUserRequest(email: Constants.newEmail, password: Constants.newPassword)
            )

            try expectRequest(.post, "/api/users")
            try expectJSONBody(["email": Constants.newEmail, "password": Constants.newPassword, "roles": [String]()])
            #expect(user.id == Constants.userID)
            #expect(user.username == TestUser.alice)
        }

        @Test
        func createUserSendsTheAdminRoleUsernameAndDisplayName() async throws {
            try prepare(statusCode: 201, fixture: .adminUsersSingle)

            _ = try await makeClient().createUser(serverURL, CreateUserRequest(
                email: Constants.newEmail,
                username: TestUser.bob,
                password: Constants.newPassword,
                displayName: Constants.displayName,
                isAdmin: true
            ))

            try expectJSONBody([
                "email": Constants.newEmail,
                "username": TestUser.bob,
                "password": Constants.newPassword,
                "displayName": Constants.displayName,
                "roles": [UserRole.admin],
            ])
        }

        @Test
        func createUserSurfacesTheServersValidationMessageOnA409() async throws {
            try prepare(statusCode: 409, fixture: .adminUsersErrorEmailInUse)

            await #expect(throws: FilesClientError.serverMessage(statusCode: 409, message: "Email already in use.")) {
                _ = try await makeClient().createUser(
                    serverURL, CreateUserRequest(email: Constants.newEmail, password: Constants.newPassword)
                )
            }
        }

        // MARK: updateUser

        @Test
        func updateUserPatchesOnlyTheNonNilFields() async throws {
            try prepare(statusCode: 200, fixture: .adminUsersSingle)

            let user = try await makeClient().updateUser(
                serverURL, Constants.userID, UpdateUserRequest(displayName: Constants.displayName)
            )

            try expectRequest(.patch, "/api/users/u1")
            try expectJSONBody(["displayName": Constants.displayName])
            #expect(user.id == Constants.userID)
        }

        @Test
        func updateUserSendsAnEmptyRolesArrayToDemoteAnAdmin() async throws {
            try prepare(statusCode: 200, fixture: .adminUsersSingle)

            _ = try await makeClient().updateUser(serverURL, Constants.userID, UpdateUserRequest(roles: []))

            try expectJSONBody(["roles": [String]()])
        }

        @Test
        func updateUserWithNoFieldsSendsAnEmptyObject() async throws {
            try prepare(statusCode: 200, fixture: .adminUsersSingle)

            _ = try await makeClient().updateUser(serverURL, Constants.userID, UpdateUserRequest())

            try expectJSONBody([:])
        }

        @Test
        func updateUserSurfacesTheServersMessageOnA409() async throws {
            try prepare(statusCode: 409, fixture: .adminUsersErrorEmailInUse)

            await #expect(throws: FilesClientError.serverMessage(statusCode: 409, message: "Email already in use.")) {
                _ = try await makeClient().updateUser(serverURL, Constants.userID, UpdateUserRequest(email: Constants.newEmail))
            }
        }

        // MARK: setUserPassword

        @Test
        func setUserPasswordPostsTheNewPasswordToThePasswordRoute() async throws {
            prepareEmpty(statusCode: 204)

            try await makeClient().setUserPassword(serverURL, Constants.userID, Constants.newPassword)

            try expectRequest(.post, "/api/users/u1/password")
            try expectJSONBody(["newPassword": Constants.newPassword])
        }

        @Test
        func setUserPasswordSurfacesTheTooShortMessage() async throws {
            try prepare(statusCode: 400, fixture: .passwordErrorTooShort)

            await #expect(throws: FilesClientError.serverMessage(statusCode: 400, message: "Password must be at least 6 characters long.")) {
                try await makeClient().setUserPassword(serverURL, Constants.userID, TestValue.outdated)
            }
        }

        // MARK: deleteUser

        @Test
        func deleteUserSendsADeleteWithoutABody() async throws {
            prepareEmpty(statusCode: 204)

            try await makeClient().deleteUser(serverURL, Constants.userID)

            try expectRequest(.delete, "/api/users/u1")
            expectNoBody()
        }

        @Test
        func deleteUserSurfacesTheLegacyMessageShapeOnA400() async throws {
            try prepare(statusCode: 400, fixture: .adminUsersErrorLastAdmin)

            await #expect(throws: FilesClientError.serverMessage(statusCode: 400, message: "Cannot delete the last admin.")) {
                try await makeClient().deleteUser(serverURL, Constants.userID)
            }
        }

        @Test
        func deleteUserWithoutAMessageFallsBackToTheBareStatus() async throws {
            prepareEmpty(statusCode: 500)

            await #expect(throws: FilesClientError.server(statusCode: 500)) {
                try await makeClient().deleteUser(serverURL, Constants.userID)
            }
        }

        // MARK: volumes

        @Test
        func userVolumesGetsTheVolumesOfThatUser() async throws {
            try prepare(statusCode: 200, fixture: .adminUsersVolumesTwo)

            let volumes = try await makeClient().userVolumes(serverURL, Constants.userID)

            try expectRequest(.get, "/api/users/u1/volumes")
            #expect(volumes.map(\.id) == [Constants.volumeID, Constants.archiveVolumeID])
            #expect(volumes.map(\.label) == [Constants.volumeLabel, "Archive"])
            #expect(volumes.map(\.path) == [Constants.volumePath, "/srv/archive"])
            #expect(volumes.map(\.accessMode) == [.readwrite, .readonly])
            #expect(volumes[0].createdAt != nil)
            #expect(volumes[1].createdAt == nil)
        }

        @Test
        func addUserVolumePostsLabelPathAndAccessMode() async throws {
            try prepare(statusCode: 201, fixture: .adminUsersVolumeSingle)

            let volume = try await makeClient().addUserVolume(
                serverURL, Constants.userID, AddUserVolumeRequest(label: Constants.volumeLabel, path: Constants.volumePath, accessMode: .readonly)
            )

            try expectRequest(.post, "/api/users/u1/volumes")
            try expectJSONBody(["label": Constants.volumeLabel, "path": Constants.volumePath, "accessMode": "readonly"])
            #expect(volume.id == Constants.volumeID)
        }

        @Test
        func updateUserVolumePatchesTheLabelAndAccessModeButNeverThePath() async throws {
            try prepare(statusCode: 200, fixture: .adminUsersVolumeSingle)

            _ = try await makeClient().updateUserVolume(serverURL, Constants.userID, Constants.volumeID, "Renamed", .readonly)

            try expectRequest(.patch, "/api/users/u1/volumes/v1")
            try expectJSONBody(["label": "Renamed", "accessMode": "readonly"])
        }

        @Test
        func updateUserVolumeOmitsTheLabelKeyWhenItIsNil() async throws {
            try prepare(statusCode: 200, fixture: .adminUsersVolumeSingle)

            _ = try await makeClient().updateUserVolume(serverURL, Constants.userID, Constants.volumeID, nil, .readwrite)

            try expectJSONBody(["accessMode": "readwrite"])
        }

        @Test
        func removeUserVolumeDeletesThatVolume() async throws {
            prepareEmpty(statusCode: 204)

            try await makeClient().removeUserVolume(serverURL, Constants.userID, Constants.archiveVolumeID)

            try expectRequest(.delete, "/api/users/u1/volumes/v2")
            expectNoBody()
        }

        @Test
        func removeUserVolumeSurfacesTheAdminRequiredReasonOnA403() async throws {
            try prepare(statusCode: 403, fixture: .commonErrorAdminRequired)

            await #expect(throws: FilesClientError.forbidden(message: "Admin access required.")) {
                try await makeClient().removeUserVolume(serverURL, Constants.userID, Constants.archiveVolumeID)
            }
        }

        // MARK: browseAdminDirectories

        struct DirectoryQuery: Sendable {
            let path: String?
            let expectedQuery: String?
        }

        nonisolated static let directoryQueries = [
            DirectoryQuery(path: nil, expectedQuery: nil),
            DirectoryQuery(path: "", expectedQuery: nil),
            DirectoryQuery(path: Constants.serverRoot, expectedQuery: "path=/srv"),
            DirectoryQuery(path: "/srv/my folder", expectedQuery: "path=/srv/my%20folder"),
        ]

        @Test(arguments: directoryQueries)
        func browseAdminDirectoriesOnlySendsAPathQueryWhenThereIsAPath(_ query: DirectoryQuery) async throws {
            try prepare(statusCode: 200, fixture: .adminUsersDirectoryListing)

            _ = try await makeClient().browseAdminDirectories(serverURL, query.path)

            try expectRequest(.get, "/api/admin/browse-directories")
            #expect(StubURLProtocol.capturedRequest?.url?.query == query.expectedQuery)
        }

        @Test
        func browseAdminDirectoriesDecodesTheListing() async throws {
            try prepare(statusCode: 200, fixture: .adminUsersDirectoryListing)

            let listing = try await makeClient().browseAdminDirectories(serverURL, Constants.serverRoot)

            #expect(listing.current == Constants.serverRoot)
            #expect(listing.parent == "/")
            #expect(listing.directories == [
                AdminDirectory(name: "projects", path: Constants.volumePath),
                AdminDirectory(name: "archive", path: "/srv/archive"),
            ])
        }

        @Test
        func browseAdminDirectoriesDecodesTheRootWithNoParent() async throws {
            try prepare(statusCode: 200, fixture: .adminUsersDirectoryRoot)

            let listing = try await makeClient().browseAdminDirectories(serverURL, nil)

            #expect(listing == AdminDirectoryListing(current: "/", parent: nil, directories: []))
        }

        // MARK: serverFeatures

        @Test
        func serverFeaturesReadsTheFlagsTheAppActsOn() async throws {
            try prepare(statusCode: 200, fixture: .featuresUserVolumesEnabled)

            let features = try await makeClient().serverFeatures(serverURL)

            try expectRequest(.get, "/api/features")
            #expect(features.isUserVolumesEnabled)
            #expect(!features.isVolumeUsageEnabled)
            #expect(features.isPersonalEnabled)
            #expect(features.editorExtensions == ["txt", "md"])
            #expect(features.maxUploadChunkSizeBytes == 5_242_880)
        }
    }
}
