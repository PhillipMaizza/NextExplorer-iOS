import CoreModels
import Dependencies
@testable import FilesClient
import Foundation
import NetworkClient
import Testing
import TestUtils

/// The API token routes through `FilesClient.live` against a stubbed `URLSession`. Nested in
/// `FilesClientLiveTests` so it inherits `.serialized`: both share `StubURLProtocol`'s statics.
extension FilesClientLiveTests {
    @Suite("API token routes")
    struct APITokenRoutes {
        private let serverURL = URL(string: TestHost.exampleURLString)!

        private func makeClient() -> FilesClient {
            .live(
                networkClient: .live(protocolClasses: [StubURLProtocol.self]),
                directoryCacheStore: .testValue
            )
        }

        private func stub(statusCode: Int, body: String = "") {
            StubURLProtocol.failure = nil
            StubURLProtocol.stub = .init(
                statusCode: statusCode,
                headers: [HTTPHeaderField.contentType: MIMEType.json],
                body: Data(body.utf8)
            )
        }

        private func sentJSON() throws -> [String: Any] {
            let body = try #require(StubURLProtocol.capturedRequestBody)
            return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        }

        @Test
        func listReadsTheTokensEnvelope() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.apiTokenListOne.string())

            let tokens = try await makeClient().fetchAPITokens(serverURL)

            #expect(tokens.map(\.id) == [TestAPIToken.id])
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == HTTPMethod.get.rawValue)
            #expect(request.url?.path == "/api/auth/tokens")
        }

        @Test
        func listOfNoTokensIsEmpty() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.apiTokenListEmpty.string())
            #expect(try await makeClient().fetchAPITokens(serverURL).isEmpty)
        }

        @Test
        func aTokenCallerOrAnInstallationWithoutAccountsSurfacesTheMessage() async throws {
            try stub(statusCode: 403, body: FilesClientFixture.apiTokenErrorNoAccounts.string())

            await #expect(throws: FilesClientError.self) {
                try await makeClient().fetchAPITokens(serverURL)
            }
        }

        @Test
        func createSendsEveryFieldAndReturnsTheSecret() async throws {
            try stub(statusCode: 201, body: FilesClientFixture.apiTokenIssued.string())

            let issued = try await makeClient().createAPIToken(
                serverURL,
                Constants.tokenName,
                .write,
                30,
                TestAccount.password
            )

            #expect(issued.secret == TestAPIToken.secret)
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == HTTPMethod.post.rawValue)
            #expect(request.url?.path == "/api/auth/tokens")
            let json = try sentJSON()
            #expect(json["name"] as? String == Constants.tokenName)
            #expect(json["scope"] as? String == "write")
            #expect(json["expiresInDays"] as? Int == 30)
            #expect(json["password"] as? String == TestAccount.password)
        }

        @Test
        func createOmitsThePasswordAndTheExpiryWhenThereAreNone() async throws {
            try stub(statusCode: 201, body: FilesClientFixture.apiTokenIssued.string())

            _ = try await makeClient().createAPIToken(serverURL, Constants.tokenName, .read, nil, nil)

            let json = try sentJSON()
            #expect(Set(json.keys) == ["name", "scope"])
        }

        @Test
        func aWrongPasswordIsAMessageNotAnExpiredSession() async throws {
            try stub(statusCode: 401, body: FilesClientFixture.apiTokenErrorWrongPassword.string())

            await #expect(throws: FilesClientError.serverMessage(
                statusCode: 401,
                message: "That password is not right."
            )) {
                try await makeClient().createAPIToken(
                    serverURL,
                    Constants.tokenName,
                    .read,
                    nil,
                    TestAccount.rejectedPassword
                )
            }
        }

        @Test
        func tooManyTokensSurfacesTheServersMessage() async throws {
            try stub(statusCode: 400, body: FilesClientFixture.apiTokenErrorLimitReached.string())

            await #expect(throws: FilesClientError.serverMessage(
                statusCode: 400,
                message: "This account already holds 50 tokens. Revoke one before issuing another."
            )) {
                try await makeClient().createAPIToken(serverURL, Constants.tokenName, .read, nil, nil)
            }
        }

        @Test
        func anUnreadableCreateReplyIsADecodingError() async throws {
            try stub(statusCode: 201, body: FilesClientFixture.commonUnexpectedKeyUnexpected.string())

            await #expect(throws: FilesClientError.self) {
                try await makeClient().createAPIToken(serverURL, Constants.tokenName, .read, nil, nil)
            }
        }

        @Test
        func renamePatchesTheNameOnTheTokensRoute() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.apiTokenSingle.string())

            let token = try await makeClient().renameAPIToken(serverURL, TestAPIToken.id, Constants.nightlyTokenName)

            #expect(token.id == TestAPIToken.id)
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == HTTPMethod.patch.rawValue)
            #expect(request.url?.path == "/api/auth/tokens/t1")
            #expect(try sentJSON() as? [String: String] == ["name": Constants.nightlyTokenName])
        }

        @Test
        func renamingATokenThatIsGoneSurfacesNotFound() async throws {
            try stub(statusCode: 404, body: FilesClientFixture.apiTokenErrorNotFound.string())

            await #expect(throws: FilesClientError.self) {
                try await makeClient().renameAPIToken(serverURL, "gone", "x")
            }
        }

        @Test
        func revokeDeletesWithoutABody() async throws {
            stub(statusCode: 204)

            try await makeClient().revokeAPIToken(serverURL, TestAPIToken.id)

            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == HTTPMethod.delete.rawValue)
            #expect(request.url?.path == "/api/auth/tokens/t1")
            #expect(StubURLProtocol.capturedRequestBody == nil || StubURLProtocol.capturedRequestBody?.isEmpty == true)
        }

        @Test
        func revokingATokenThatIsGoneSurfacesTheMessage() async throws {
            try stub(statusCode: 404, body: FilesClientFixture.apiTokenErrorNotFound.string())

            await #expect(throws: FilesClientError.self) {
                try await makeClient().revokeAPIToken(serverURL, "gone")
            }
        }

        @Test
        func theRoutesAreRateLimited() async throws {
            stub(statusCode: 429)

            await #expect(throws: FilesClientError.rateLimited) {
                try await makeClient().createAPIToken(serverURL, Constants.tokenName, .read, nil, "x")
            }
        }
    }
}

private enum Constants {
    static let nightlyTokenName = "nightly"
    static let tokenName = "backup"
}
