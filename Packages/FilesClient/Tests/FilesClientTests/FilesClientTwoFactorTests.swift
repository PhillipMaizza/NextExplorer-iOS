import CoreModels
import Dependencies
@testable import FilesClient
import Foundation
import NetworkClient
import Testing
import TestUtils

/// The second factor routes through `FilesClient.live` against a stubbed `URLSession`. Nested in
/// `FilesClientLiveTests` so it inherits `.serialized`: both share `StubURLProtocol`'s statics.
extension FilesClientLiveTests {
    @Suite("Two factor routes")
    struct TwoFactorRoutes {
        private let serverURL = URL(string: TestHost.exampleURLString)!

        private func makeClient() -> FilesClient {
            .live(
                networkClient: .live(protocolClasses: [StubURLProtocol.self]),
                directoryCacheStore: .testValue
            )
        }

        private func stub(statusCode: Int, body: String = "") {
            StubURLProtocol.failure = nil
            StubURLProtocol.stub = .init(statusCode: statusCode, headers: [HTTPHeaderField.contentType: MIMEType.json], body: Data(body.utf8))
        }

        private func sentJSON() throws -> [String: String] {
            let body = try #require(StubURLProtocol.capturedRequestBody)
            return try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        }

        @Test
        func statusIsReadFromTheTotpRoute() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.twoFactorStatusEnabled.string())

            let status = try await makeClient().fetchTwoFactorStatus(serverURL)

            #expect(status.isEnabled)
            #expect(status.recoveryCodesLeft == 5)
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == HTTPMethod.get.rawValue)
            #expect(request.url?.path == "/api/auth/totp")
        }

        @Test
        func beginningSetupPostsAnEmptyObjectAndDecodesTheSecret() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.twoFactorSetupSecret.string())

            let setup = try await makeClient().beginTwoFactorSetup(serverURL)

            #expect(setup.secret == TestAccount.totpSecret)
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == HTTPMethod.post.rawValue)
            #expect(request.url?.path == "/api/auth/totp/start")
            #expect(try sentJSON().isEmpty)
        }

        @Test
        func beginningSetupWithoutAPasswordSessionSurfacesTheMessage() async throws {
            try stub(statusCode: 403, body: FilesClientFixture.twoFactorErrorPasswordRequired.string())

            await #expect(throws: FilesClientError.serverMessage(statusCode: 403, message: "Sign in with your password")) {
                try await makeClient().beginTwoFactorSetup(serverURL)
            }
        }

        @Test
        func beginningSetupWhenAlreadyOnIsAConflict() async throws {
            try stub(statusCode: 409, body: FilesClientFixture.twoFactorErrorAlreadyEnabled.string())

            await #expect(throws: FilesClientError.serverMessage(statusCode: 409, message: "Already enabled")) {
                try await makeClient().beginTwoFactorSetup(serverURL)
            }
        }

        @Test
        func confirmingPostsTheCodeAndReturnsTheRecoveryCodes() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.twoFactorRecoveryCodesTwo.string())

            let codes = try await makeClient().confirmTwoFactorSetup(serverURL, TestAccount.totpCode)

            #expect(codes == ["AAAAA-BBBBB", "CCCCC-DDDDD"])
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == HTTPMethod.post.rawValue)
            #expect(request.url?.path == "/api/auth/totp/confirm")
            #expect(try sentJSON() == ["code": TestAccount.totpCode])
        }

        @Test
        func aWrongCodeIsAnErrorWithTheServersMessageNotAnExpiredSession() async throws {
            try stub(statusCode: 401, body: FilesClientFixture.twoFactorErrorInvalidCode.string())

            await #expect(throws: FilesClientError.serverMessage(statusCode: 401, message: "Invalid code")) {
                try await makeClient().confirmTwoFactorSetup(serverURL, TestAccount.invalidTotpCode)
            }
        }

        @Test
        func anUnreadableConfirmationIsADecodingError() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.commonUnexpectedKeyUnexpected.string())

            await #expect(throws: FilesClientError.self) {
                try await makeClient().confirmTwoFactorSetup(serverURL, TestAccount.totpCode)
            }
        }

        @Test
        func replacingRecoveryCodesPostsThePassword() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.twoFactorRecoveryCodesOne.string())

            let codes = try await makeClient().replaceRecoveryCodes(serverURL, TestAccount.password)

            #expect(codes == ["EEEEE-FFFFF"])
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == HTTPMethod.post.rawValue)
            #expect(request.url?.path == "/api/auth/totp/recovery-codes")
            #expect(try sentJSON() == ["password": TestAccount.password])
        }

        @Test
        func disablingSendsADeleteWithThePasswordInTheBody() async throws {
            stub(statusCode: 204)

            try await makeClient().disableTwoFactor(serverURL, TestAccount.password)

            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == HTTPMethod.delete.rawValue)
            #expect(request.url?.path == "/api/auth/totp")
            #expect(try sentJSON() == ["password": TestAccount.password])
        }

        @Test
        func aWrongPasswordWhenDisablingSurfacesTheMessage() async throws {
            try stub(statusCode: 401, body: FilesClientFixture.twoFactorErrorIncorrectPassword.string())

            await #expect(throws: FilesClientError.serverMessage(statusCode: 401, message: "Incorrect password")) {
                try await makeClient().disableTwoFactor(serverURL, TestAccount.rejectedPassword)
            }
        }

        @Test
        func theRoutesAreRateLimited() async throws {
            stub(statusCode: 429)

            await #expect(throws: FilesClientError.rateLimited) {
                try await makeClient().confirmTwoFactorSetup(serverURL, TestAccount.totpCode)
            }
        }
    }
}
