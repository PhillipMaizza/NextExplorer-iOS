import CoreModels
@testable import FilesClient
import Foundation
import NetworkClient
import Testing
import TestUtils

/// Share link and favorites routes through `FilesClient.live` against a stubbed `URLSession`. Nested in
/// `FilesClientLiveTests` so it inherits `.serialized`: every live client suite shares `StubURLProtocol`'s statics.
extension FilesClientLiveTests {
    struct FilesClientShareRouteTests: FilesClientLiveHarness {
        private enum Constants {
            static let firstFavoriteID = "f1"
            static let workLabel = "Work"
            static let redColor = "red"
            static let starIcon = "star"
            static let recipientID = "u2"
            static let expiryText = "2023-11-14T22:13:20Z"
            static let readonlyMode = "readonly"
            static let anyoneTarget = "anyone"
            static let shareID = "s1"
            static let shareLabel = "Quarterly"
            static let sharePassword = "open-sesame"
            static let favoriteID = "f2"
        }

        // MARK: createShareLink

        @Test
        func createShareLinkPostsTheMinimalBodyForAnOpenLink() async throws {
            try prepare(statusCode: 201, fixture: .shareCreated)

            let created = try await makeClient().createShareLink(
                serverURL,
                CreateShareLinkRequest(sourcePath: TestPath.docsNote)
            )

            try expectRequest(.post, "/api/shares")
            try expectJSONBody([
                "sourcePath": TestPath.docsNote,
                "accessMode": Constants.readonlyMode,
                "sharingType": Constants.anyoneTarget,
                "userIds": [String](),
            ])
            #expect(created.share.id == Constants.shareID)
            #expect(created.share.shareToken == "AbC123xyz0")
            #expect(created.shareUrl.absoluteString == "https://example.com/share/AbC123xyz0")
            #expect(created.directFileUrl.absoluteString == "https://example.com/api/share/AbC123xyz0/file")
        }

        @Test
        func createShareLinkSendsLabelPasswordAndAWholeSecondExpiry() async throws {
            try prepare(statusCode: 201, fixture: .shareCreated)

            _ = try await makeClient().createShareLink(serverURL, CreateShareLinkRequest(
                sourcePath: TestPath.docsNote,
                label: Constants.shareLabel,
                accessMode: .readwrite,
                password: Constants.sharePassword,
                expiresAt: MockDate.date.addingTimeInterval(0.75)
            ))

            try expectJSONBody([
                "sourcePath": TestPath.docsNote,
                "label": Constants.shareLabel,
                "accessMode": "readwrite",
                "sharingType": Constants.anyoneTarget,
                "password": Constants.sharePassword,
                "userIds": [String](),
                "expiresAt": Constants.expiryText,
            ])
        }

        @Test
        func createShareLinkSendsTheRecipientsOnlyForAUsersShare() async throws {
            try prepare(statusCode: 201, fixture: .shareCreated)

            _ = try await makeClient().createShareLink(serverURL, CreateShareLinkRequest(
                sourcePath: TestFolder.docs, target: .users, userIds: [Constants.recipientID, "u3"]
            ))

            try expectJSONBody([
                "sourcePath": TestFolder.docs,
                "accessMode": Constants.readonlyMode,
                "sharingType": "users",
                "userIds": [Constants.recipientID, "u3"],
            ])
        }

        @Test
        func createShareLinkDropsRecipientsLeftOverFromAnAnyoneShare() async throws {
            try prepare(statusCode: 201, fixture: .shareCreated)

            _ = try await makeClient().createShareLink(serverURL, CreateShareLinkRequest(
                sourcePath: TestFolder.docs, target: .anyone, userIds: [Constants.recipientID]
            ))

            try expectJSONBody([
                "sourcePath": TestFolder.docs,
                "accessMode": Constants.readonlyMode,
                "sharingType": Constants.anyoneTarget,
                "userIds": [String](),
            ])
        }

        @Test
        func createShareLinkSurfacesTheServersMessage() async throws {
            try prepare(statusCode: 400, fixture: .shareErrorExpiryInPast)

            await #expect(throws: FilesClientError.serverMessage(
                statusCode: 400,
                message: "Expiry must be in the future."
            )) {
                _ = try await makeClient().createShareLink(
                    serverURL,
                    CreateShareLinkRequest(sourcePath: TestFolder.docs)
                )
            }
        }

        @Test
        func shareExpiryIsFormattedInUTCWithoutFractionalSeconds() {
            #expect(FilesService.formatShareExpiry(MockDate.date) == Constants.expiryText)
            #expect(FilesService.formatShareExpiry(MockDate.date.addingTimeInterval(0.999)) == Constants.expiryText)
            #expect(FilesService.formatShareExpiry(MockDate.date.addingTimeInterval(86_400)) == "2023-11-15T22:13:20Z")
        }

        // MARK: listing

        @Test
        func mySharedLinksReadsTheOwnersRouteAndKeepsTheOrder() async throws {
            try prepare(statusCode: 200, fixture: .shareListTwo)

            let shares = try await makeClient().mySharedLinks(serverURL)

            try expectRequest(.get, "/api/shares")
            #expect(shares.map(\.id) == ["s1", "s2"])
            #expect(shares[0].sourcePath == "Docs/Report")
            #expect(shares[0].sharingType == .anyone)
        }

        @Test
        func sharedWithMeLinksReadsTheRecipientRouteAndDecodesTheRecipientShape() async throws {
            try prepare(statusCode: 200, fixture: .shareListTwo)

            let shares = try await makeClient().sharedWithMeLinks(serverURL)

            try expectRequest(.get, "/api/shares/shared-with-me")
            #expect(shares[1].sourceName == "Holiday")
            #expect(shares[1].sourcePath == nil)
            #expect(shares[1].ownerId == "7")
            #expect(shares[1].hasPassword)
            #expect(shares[1].downloadCount == 4)
            #expect(shares[1].permittedUserIds == ["u1"])
            #expect(shares[1].sharingType == .users)
            #expect(shares[1].accessMode == .readonly)
        }

        @Test
        func mySharedLinksFailsToDecodeAnEnvelopeWithoutShares() async throws {
            try prepare(statusCode: 200, fixture: .commonEmptyObject)

            await #expect {
                _ = try await makeClient().mySharedLinks(serverURL)
            } throws: { error in
                guard case .decoding = error as? FilesClientError else { return false }
                return true
            }
        }

        @Test
        func shareableUsersReadsTheShareableRoute() async throws {
            try prepare(statusCode: 200, fixture: .shareShareableUsers)

            let users = try await makeClient().shareableUsers(serverURL)

            try expectRequest(.get, "/api/users/shareable")
            #expect(users.map(\.id) == [Constants.recipientID])
            #expect(users[0].username == TestUser.bob)
            #expect(users[0].displayName == "Bob B")
            #expect(users[0].roles.isEmpty)
        }

        // MARK: deleteShareLink

        @Test
        func deleteShareLinkDeletesThatShareWithoutABody() async throws {
            prepareEmpty(statusCode: 204)

            try await makeClient().deleteShareLink(serverURL, Constants.shareID)

            try expectRequest(.delete, "/api/shares/s1")
            expectNoBody()
        }

        @Test
        func deleteShareLinkMaps401ToSessionExpired() async throws {
            prepareEmpty(statusCode: 401)

            await #expect(throws: FilesClientError.sessionExpired) {
                try await makeClient().deleteShareLink(serverURL, Constants.shareID)
            }
        }

        @Test
        func deleteShareLinkReportsABareStatusEvenWhenTheServerExplainsIt() async throws {
            try prepare(statusCode: 404, fixture: .shareErrorNotFound)

            await #expect(throws: FilesClientError.server(statusCode: 404)) {
                try await makeClient().deleteShareLink(serverURL, Constants.shareID)
            }
        }

        // MARK: favorites

        @Test
        func favoritesReadsTheListInServerOrder() async throws {
            try prepare(statusCode: 200, fixture: .favoriteListTwo)

            let favorites = try await makeClient().favorites(serverURL)

            try expectRequest(.get, "/api/favorites")
            expectNoBody()
            #expect(favorites.map(\.id) == [Constants.firstFavoriteID, Constants.favoriteID])
            #expect(favorites.map(\.path) == [TestFolder.photos, TestFolder.docs])
            #expect(favorites.map(\.label) == [nil, Constants.workLabel])
            #expect(favorites.map(\.position) == [0, 1])
        }

        @Test
        func favoritesMaps401ToSessionExpired() async throws {
            prepareEmpty(statusCode: 401)

            await #expect(throws: FilesClientError.sessionExpired) {
                _ = try await makeClient().favorites(serverURL)
            }
        }

        @Test
        func updateFavoritePatchesLabelIconAndColor() async throws {
            try prepare(statusCode: 200, fixture: .favoriteUpdated)

            let favorite = try await makeClient().updateFavorite(
                serverURL,
                Constants.favoriteID,
                Constants.workLabel,
                "folder",
                Constants.redColor
            )

            try expectRequest(.patch, "/api/favorites/f2")
            try expectJSONBody(["label": Constants.workLabel, "icon": "folder", "color": Constants.redColor])
            #expect(favorite.id == Constants.favoriteID)
            #expect(favorite.color == Constants.redColor)
        }

        @Test
        func updateFavoriteWritesExplicitNullsSoTheServerClearsTheLabelAndColor() async throws {
            try prepare(statusCode: 200, fixture: .favoriteUpdated)

            _ = try await makeClient().updateFavorite(serverURL, Constants.favoriteID, nil, Constants.starIcon, nil)

            try expectJSONBody(["label": NSNull(), "icon": Constants.starIcon, "color": NSNull()])
        }

        @Test
        func updateFavoriteSurfacesTheForbiddenReason() async throws {
            try prepare(statusCode: 403, fixture: .permissionsErrorDenied)

            await #expect(throws: FilesClientError.forbidden(message: "Access denied by rule.")) {
                _ = try await makeClient().updateFavorite(serverURL, Constants.favoriteID, nil, Constants.starIcon, nil)
            }
        }

        @Test
        func reorderFavoritesPatchesTheFullOrderAndDecodesTheNewList() async throws {
            try prepare(statusCode: 200, fixture: .favoriteListTwo)

            let favorites = try await makeClient().reorderFavorites(
                serverURL,
                [Constants.favoriteID, Constants.firstFavoriteID]
            )

            try expectRequest(.patch, "/api/favorites/reorder")
            try expectJSONBody(["order": [Constants.favoriteID, Constants.firstFavoriteID]])
            #expect(favorites.map(\.id) == [Constants.firstFavoriteID, Constants.favoriteID])
        }

        @Test
        func reorderFavoritesSendsAnEmptyOrderAsIs() async throws {
            try prepare(statusCode: 200, fixture: .commonEmptyArray)

            let favorites = try await makeClient().reorderFavorites(serverURL, [])

            try expectJSONBody(["order": [String]()])
            #expect(favorites.isEmpty)
        }

        @Test
        func reorderFavoritesSurfacesTheMismatchMessage() async throws {
            try prepare(statusCode: 400, fixture: .favoriteErrorOrderMismatch)

            await #expect(throws: FilesClientError.serverMessage(
                statusCode: 400,
                message: "Order must list every favorite once."
            )) {
                _ = try await makeClient().reorderFavorites(serverURL, [Constants.firstFavoriteID])
            }
        }
    }
}
