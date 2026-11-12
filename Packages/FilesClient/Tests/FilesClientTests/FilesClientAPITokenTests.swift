import CoreModels
import Dependencies
@testable import FilesClient
import Foundation
import NetworkClient
import Testing

/// The API token routes through `FilesClient.live` against a stubbed `URLSession`. Nested in
/// `FilesClientLiveTests` so it inherits `.serialized`: both share `StubURLProtocol`'s statics.
extension FilesClientLiveTests {
    @Suite("API token routes")
    struct APITokenRoutes {
        private let serverURL = URL(string: "https://example.com")!

        private func makeClient() -> FilesClient {
            .live(
                networkClient: .live(protocolClasses: [StubURLProtocol.self]),
                directoryCacheStore: .testValue
            )
        }

        private func stub(statusCode: Int, body: String = "") {
            StubURLProtocol.failure = nil
            StubURLProtocol.stub = .init(statusCode: statusCode, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
        }

        private func sentJSON() throws -> [String: Any] {
            let body = try #require(StubURLProtocol.capturedRequestBody)
            return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        }

        @Test
        func listReadsTheTokensEnvelope() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.apiTokenListOne.string())

            let tokens = try await makeClient().fetchAPITokens(serverURL)

            #expect(tokens.map(\.id) == ["t1"])
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/api/auth/tokens")
        }

        @Test
        func listOfNoTokensIsEmpty() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.apiTokenListEmpty.string())
            #expect(try await makeClient().fetchAPITokens(serverURL).isEmpty)
        }

        @Test
        func aTokenCallerOrAnInstallationWithoutAccountsSurfacesTheMessage() async throws {
            stub(statusCode: 403, body: try FilesClientFixture.apiTokenErrorNoAccounts.string())

            await #expect(throws: FilesClientError.self) {
                try await makeClient().fetchAPITokens(serverURL)
            }
        }

        @Test
        func createSendsEveryFieldAndReturnsTheSecret() async throws {
            stub(statusCode: 201, body: try FilesClientFixture.apiTokenIssued.string())

            let issued = try await makeClient().createAPIToken(serverURL, "backup", .write, 30, "hunter2")

            #expect(issued.secret == "nxt_abc.def")
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/auth/tokens")
            let json = try sentJSON()
            #expect(json["name"] as? String == "backup")
            #expect(json["scope"] as? String == "write")
            #expect(json["expiresInDays"] as? Int == 30)
            #expect(json["password"] as? String == "hunter2")
        }

        @Test
        func createOmitsThePasswordAndTheExpiryWhenThereAreNone() async throws {
            stub(statusCode: 201, body: try FilesClientFixture.apiTokenIssued.string())

            _ = try await makeClient().createAPIToken(serverURL, "backup", .read, nil, nil)

            let json = try sentJSON()
            #expect(Set(json.keys) == ["name", "scope"])
        }

        @Test
        func aWrongPasswordIsAMessageNotAnExpiredSession() async throws {
            stub(statusCode: 401, body: try FilesClientFixture.apiTokenErrorWrongPassword.string())

            await #expect(throws: FilesClientError.serverMessage(statusCode: 401, message: "That password is not right.")) {
                try await makeClient().createAPIToken(serverURL, "backup", .read, nil, "nope")
            }
        }

        @Test
        func tooManyTokensSurfacesTheServersMessage() async throws {
            stub(statusCode: 400, body: try FilesClientFixture.apiTokenErrorLimitReached.string())

            await #expect(throws: FilesClientError.serverMessage(statusCode: 400, message: "This account already holds 50 tokens. Revoke one before issuing another.")) {
                try await makeClient().createAPIToken(serverURL, "backup", .read, nil, nil)
            }
        }

        @Test
        func anUnreadableCreateReplyIsADecodingError() async throws {
            stub(statusCode: 201, body: try FilesClientFixture.commonUnexpectedKeyUnexpected.string())

            await #expect(throws: FilesClientError.self) {
                try await makeClient().createAPIToken(serverURL, "backup", .read, nil, nil)
            }
        }

        @Test
        func renamePatchesTheNameOnTheTokensRoute() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.apiTokenSingle.string())

            let token = try await makeClient().renameAPIToken(serverURL, "t1", "nightly")

            #expect(token.id == "t1")
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == "PATCH")
            #expect(request.url?.path == "/api/auth/tokens/t1")
            #expect(try sentJSON() as? [String: String] == ["name": "nightly"])
        }

        @Test
        func renamingATokenThatIsGoneSurfacesNotFound() async throws {
            stub(statusCode: 404, body: try FilesClientFixture.apiTokenErrorNotFound.string())

            await #expect(throws: FilesClientError.self) {
                try await makeClient().renameAPIToken(serverURL, "gone", "x")
            }
        }

        @Test
        func revokeDeletesWithoutABody() async throws {
            stub(statusCode: 204)

            try await makeClient().revokeAPIToken(serverURL, "t1")

            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == "DELETE")
            #expect(request.url?.path == "/api/auth/tokens/t1")
            #expect(StubURLProtocol.capturedRequestBody == nil || StubURLProtocol.capturedRequestBody?.isEmpty == true)
        }

        @Test
        func revokingATokenThatIsGoneSurfacesTheMessage() async throws {
            stub(statusCode: 404, body: try FilesClientFixture.apiTokenErrorNotFound.string())

            await #expect(throws: FilesClientError.self) {
                try await makeClient().revokeAPIToken(serverURL, "gone")
            }
        }

        @Test
        func theRoutesAreRateLimited() async throws {
            stub(statusCode: 429)

            await #expect(throws: FilesClientError.rateLimited) {
                try await makeClient().createAPIToken(serverURL, "backup", .read, nil, "x")
            }
        }
    }
}
