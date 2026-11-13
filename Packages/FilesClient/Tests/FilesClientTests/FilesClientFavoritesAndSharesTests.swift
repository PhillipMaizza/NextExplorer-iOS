import CoreModels
import Dependencies
@testable import FilesClient
import Foundation
import NetworkClient
import Testing
import TestUtils

/// Favorites and share links through `FilesClient.live` against a stubbed `URLSession`. Nested in
/// `FilesClientLiveTests` so it inherits `.serialized`: every live client suite shares
/// `StubURLProtocol`'s statics.
extension FilesClientLiveTests {
    struct FilesClientFavoritesAndSharesTests: FilesClientLiveHarness {
        func updateBody(_ request: UpdateShareRequest) async throws -> [String: Any] {
            try stub(statusCode: 200, body: FilesClientFixture.shareFull.data())
            StubURLProtocol.capturedRequest = nil
            _ = try await makeClient().updateShareLink(serverURL, "s1", request)
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == HTTPMethod.put.rawValue)
            #expect(request.url?.absoluteString == "https://example.com/api/shares/s1")
            let data = try #require(StubURLProtocol.capturedRequestBody)
            return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        }

        @Test
        func addFavoriteSendsThePathInThePOSTBodyAndDecodesTheCreatedFavorite() async throws {
            let favoriteJSON = try FilesClientFixture.favoriteStar.data()
            stub(statusCode: 200, body: favoriteJSON)
            StubURLProtocol.capturedRequest = nil
            let favorite = try await makeClient().addFavorite(serverURL, TestFolder.photos)
            #expect(favorite.path == TestFolder.photos)
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == HTTPMethod.post.rawValue)
            let body = try #require(StubURLProtocol.capturedRequestBody)
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(json["path"] == TestFolder.photos)
        }

        @Test
        func addFavoriteMaps401ToSessionExpired() async throws {
            stub(statusCode: 401, body: Data())
            await #expect(throws: FilesClientError.sessionExpired) {
                _ = try await makeClient().addFavorite(serverURL, TestFolder.photos)
            }
        }

        @Test
        func removeFavoriteSendsThePathInTheDELETEBody() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.commonEmptyArray.data())
            StubURLProtocol.capturedRequest = nil
            try await makeClient().removeFavorite(serverURL, TestFolder.photos)
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == HTTPMethod.delete.rawValue)
            let body = try #require(StubURLProtocol.capturedRequestBody)
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(json["path"] == TestFolder.photos)
        }

        @Test
        func removeFavoriteMaps500ToServerErrorWithStatusCode() async throws {
            stub(statusCode: 500, body: Data())
            await #expect(throws: FilesClientError.server(statusCode: 500)) {
                try await makeClient().removeFavorite(serverURL, TestFolder.photos)
            }
        }

        @Test
        func updateShareLinkOmitsThePasswordKeyWhenKeeping() async throws {
            let body = try await updateBody(UpdateShareRequest(
                label: "New",
                accessMode: .readonly,
                target: .anyone,
                password: .keep
            ))
            #expect(body["password"] == nil)
            #expect(body["label"] as? String == "New")
            #expect(body["accessMode"] as? String == "readonly")
            #expect(body["userIds"] == nil) // not a users share
        }

        @Test
        func updateShareLinkSendsNullToRemoveThePassword() async throws {
            let body = try await updateBody(UpdateShareRequest(password: .remove))
            #expect(body["password"] is NSNull)
        }

        @Test
        func updateShareLinkSendsTheStringToChangeThePassword() async throws {
            let body = try await updateBody(UpdateShareRequest(password: .set(TestAccount.password)))
            #expect(body["password"] as? String == TestAccount.password)
        }

        @Test
        func updateShareLinkIncludesUserIdsOnlyForAUsersShare() async throws {
            let body = try await updateBody(UpdateShareRequest(target: .users, userIds: ["u2", "u3"], password: .keep))
            #expect(body["userIds"] as? [String] == ["u2", "u3"])
            #expect(body["sharingType"] as? String == "users")
        }

        @Test
        func updateShareLinkMapsAForbiddenResponseToAServerError() async throws {
            stub(statusCode: 403, body: Data())
            await #expect(throws: FilesClientError.forbidden(message: nil)) {
                _ = try await makeClient().updateShareLink(serverURL, "s1", UpdateShareRequest())
            }
        }

        @Test
        func resolveShareLinkHitsTheInfoEndpointAndDecodes() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.shareInfoQ3Report.data())
            StubURLProtocol.capturedRequest = nil

            let info = try await makeClient().resolveShareLink(serverURL, "AbC123xyz0")

            #expect(info.label == "Q3 Report")
            #expect(info.isDirectory)
            #expect(info.sharingType == .anyone)
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.url?.path == "/api/share/AbC123xyz0/info")
            #expect(request.httpMethod == HTTPMethod.get.rawValue)
        }

        @Test
        func resolveShareLinkMapsA404ToAServerError() async throws {
            stub(statusCode: 404, body: Data())
            await #expect(throws: FilesClientError.server(statusCode: 404)) {
                _ = try await makeClient().resolveShareLink(serverURL, "nope00")
            }
        }
    }
}
