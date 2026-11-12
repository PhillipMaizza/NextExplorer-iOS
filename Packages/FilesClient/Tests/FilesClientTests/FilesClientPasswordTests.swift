import CoreModels
import Dependencies
@testable import FilesClient
import Foundation
import NetworkClient
import Testing

/// The password routes through `FilesClient.live` against a stubbed `URLSession`. Nested in
/// `FilesClientLiveTests` so it inherits `.serialized`: both share `StubURLProtocol`'s statics.
extension FilesClientLiveTests {
    @Suite("Password routes")
    struct PasswordRoutes {
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

        // MARK: addOwnPassword

        @Test
        func addOwnPasswordPostsOnlyThePasswordToTheAddRoute() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.passwordAddedMessage.string())

            try await makeClient().addOwnPassword(serverURL, "brand-new")

            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/auth/password/add")
            let body = try #require(StubURLProtocol.capturedRequestBody)
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(json == ["password": "brand-new"])
        }

        @Test
        func anAccountThatAlreadyHasAPasswordSurfacesTheServersMessage() async throws {
            stub(statusCode: 409, body: try FilesClientFixture.passwordErrorAlreadyExists.string())

            await #expect(throws: FilesClientError.serverMessage(statusCode: 409, message: "You already have password authentication.")) {
                try await makeClient().addOwnPassword(serverURL, "brand-new")
            }
        }

        @Test
        func aTooShortPasswordSurfacesTheServersMessage() async throws {
            stub(statusCode: 400, body: try FilesClientFixture.passwordErrorTooShort.string())

            await #expect(throws: FilesClientError.serverMessage(statusCode: 400, message: "Password must be at least 6 characters long.")) {
                try await makeClient().addOwnPassword(serverURL, "abc")
            }
        }

        @Test
        func addOwnPasswordIsRateLimited() async throws {
            stub(statusCode: 429)

            await #expect(throws: FilesClientError.rateLimited) {
                try await makeClient().addOwnPassword(serverURL, "brand-new")
            }
        }

        @Test
        func addOwnPasswordOnAnUnreadableErrorBodyIsAServerError() async throws {
            stub(statusCode: 502, body: "<html>bad gateway</html>")

            await #expect(throws: FilesClientError.server(statusCode: 502)) {
                try await makeClient().addOwnPassword(serverURL, "brand-new")
            }
        }

        // MARK: changeOwnPassword still behaves

        @Test
        func aWrongCurrentPasswordIsItsMessageNotASessionExpiry() async throws {
            stub(statusCode: 401, body: try FilesClientFixture.passwordErrorCurrentIncorrect.string())

            await #expect(throws: FilesClientError.serverMessage(statusCode: 401, message: "Current password is incorrect.")) {
                try await makeClient().changeOwnPassword(serverURL, "wrong", "brand-new")
            }
        }

        // MARK: authMethods

        @Test
        func authMethodsDecodesTheEnvelope() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.signInMethodLocalPassword.string())

            let methods = try await makeClient().fetchAuthMethods(serverURL)

            #expect(methods.hasPassword)
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/api/auth/methods")
        }

        @Test
        func authMethodsOfASingleSignOnAccountHaveNoPassword() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.signInMethodOidcPocketId.string())

            let methods = try await makeClient().fetchAuthMethods(serverURL)

            #expect(!methods.hasPassword)
        }

        @Test
        func authMethodsWithAnEmptyListIsNoPassword() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.signInMethodEmpty.string())

            #expect(try await makeClient().fetchAuthMethods(serverURL).isEmpty)
        }

        // MARK: authStatus

        @Test
        func authStatusReadsWhetherPasswordSignInIsOn() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.authStatusOidcOnly.string())

            let status = try await makeClient().fetchAuthStatus(serverURL)

            #expect(!status.isLocalEnabled)
            #expect(status.isOIDCEnabled)
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/api/auth/status")
        }

        @Test
        func authStatusWithPasswordSignInOnIsLocalEnabled() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.authStatusLocalAndOidc.string())

            #expect(try await makeClient().fetchAuthStatus(serverURL).isLocalEnabled)
        }

        @Test
        func authStatusWithAMalformedBodyIsADecodingError() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.commonUnexpectedKeyNope.string())

            await #expect(throws: FilesClientError.self) {
                _ = try await makeClient().fetchAuthStatus(serverURL)
            }
        }

        @Test
        func authMethodsOfADeadSessionIsSessionExpired() async throws {
            stub(statusCode: 401)

            await #expect(throws: FilesClientError.sessionExpired) {
                _ = try await makeClient().fetchAuthMethods(serverURL)
            }
        }

        @Test
        func authMethodsWithAMalformedBodyIsADecodingError() async throws {
            stub(statusCode: 200, body: "not json")

            await #expect(throws: FilesClientError.self) {
                _ = try await makeClient().fetchAuthMethods(serverURL)
            }
        }
    }
}
