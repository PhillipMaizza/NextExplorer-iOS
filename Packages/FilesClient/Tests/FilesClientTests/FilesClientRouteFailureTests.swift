import CoreModels
@testable import FilesClient
import Foundation
import NetworkClient
import Testing
import TestUtils

/// Every admin, share, favorite, permission and branding route maps the same three transport level failures the same way:
/// a dead session, a rate limit and no connection. Nested in `FilesClientLiveTests` so it inherits `.serialized`:
/// every live client suite shares `StubURLProtocol`'s statics.
extension FilesClientLiveTests {
    @Suite
    struct FilesClientRouteFailureTests: FilesClientLiveHarness {
        enum Route: CaseIterable, Sendable {
            private static let userID = "u1"
            private static let volumeID = "v1"
            private static let password = "pw"

            case listUsers, createUser, updateUser, setUserPassword, deleteUser
            case userVolumes, addUserVolume, updateUserVolume, removeUserVolume
            case browseAdminDirectories, serverFeatures
            case fetchPermissions, changePermissions, changeOwnership
            case createShareLink, mySharedLinks, sharedWithMeLinks, shareableUsers, deleteShareLink
            case favorites, updateFavorite, reorderFavorites
            case fetchBranding, updateBranding, uploadServerLogo

            func call(_ client: FilesClient, _ serverURL: URL) async throws {
                switch self {
                case .listUsers: _ = try await client.listUsers(serverURL)
                case .createUser: _ = try await client.createUser(serverURL, CreateUserRequest(email: "a@example.com", password: Self.password))
                case .updateUser: _ = try await client.updateUser(serverURL, Self.userID, UpdateUserRequest())
                case .setUserPassword: try await client.setUserPassword(serverURL, Self.userID, Self.password)
                case .deleteUser: try await client.deleteUser(serverURL, Self.userID)
                case .userVolumes: _ = try await client.userVolumes(serverURL, Self.userID)
                case .addUserVolume: _ = try await client.addUserVolume(serverURL, Self.userID, AddUserVolumeRequest(label: "L", path: "/p"))
                case .updateUserVolume: _ = try await client.updateUserVolume(serverURL, Self.userID, Self.volumeID, nil, .readonly)
                case .removeUserVolume: try await client.removeUserVolume(serverURL, Self.userID, Self.volumeID)
                case .browseAdminDirectories: _ = try await client.browseAdminDirectories(serverURL, nil)
                case .serverFeatures: _ = try await client.serverFeatures(serverURL)
                case .fetchPermissions: _ = try await client.fetchPermissions(serverURL, TestFolder.docs)
                case .changePermissions: try await client.changePermissions(serverURL, TestFolder.docs, "644", false)
                case .changeOwnership: try await client.changeOwnership(serverURL, TestFolder.docs, nil, nil)
                case .createShareLink: _ = try await client.createShareLink(serverURL, CreateShareLinkRequest(sourcePath: TestFolder.docs))
                case .mySharedLinks: _ = try await client.mySharedLinks(serverURL)
                case .sharedWithMeLinks: _ = try await client.sharedWithMeLinks(serverURL)
                case .shareableUsers: _ = try await client.shareableUsers(serverURL)
                case .deleteShareLink: try await client.deleteShareLink(serverURL, "s1")
                case .favorites: _ = try await client.favorites(serverURL)
                case .updateFavorite: _ = try await client.updateFavorite(serverURL, "f1", nil, "star", nil)
                case .reorderFavorites: _ = try await client.reorderFavorites(serverURL, [])
                case .fetchBranding: _ = try await client.fetchBranding(serverURL)
                case .updateBranding: _ = try await client.updateBranding(serverURL, "App", "/logo.svg")
                case .uploadServerLogo: _ = try await client.uploadServerLogo(serverURL, Data())
                }
            }
        }

        enum Outcome: CaseIterable, Sendable {
            case unauthorized, rateLimited, offline

            var expected: FilesClientError {
                switch self {
                case .unauthorized: .sessionExpired
                case .rateLimited: .rateLimited
                case .offline: .offline
                }
            }

            func install() {
                switch self {
                case .unauthorized:
                    StubURLProtocol.stub = .init(statusCode: 401, headers: [:], body: Data())
                case .rateLimited:
                    StubURLProtocol.stub = .init(statusCode: 429, headers: [:], body: Data())
                case .offline:
                    StubURLProtocol.failure = URLError(.notConnectedToInternet)
                }
            }
        }

        @Test(arguments: Route.allCases, Outcome.allCases)
        func everyRouteMapsTheTransportFailureToTheMatchingClientError(_ route: Route, _ outcome: Outcome) async {
            resetStubs()
            outcome.install()

            await #expect(throws: outcome.expected) {
                try await route.call(makeClient(), serverURL)
            }
        }
    }
}
