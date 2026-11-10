import CoreModels
import Dependencies
@testable import FilesClient
import Foundation
import NetworkClient
import Testing

/// The second factor routes through `FilesClient.live` against a stubbed `URLSession`. Nested in
/// `FilesClientLiveTests` so it inherits `.serialized`: both share `StubURLProtocol`'s statics.
extension FilesClientLiveTests {
    @Suite("Two factor routes")
    struct TwoFactorRoutes {
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

        private func sentJSON() throws -> [String: String] {
            let body = try #require(StubURLProtocol.capturedRequestBody)
            return try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        }

        @Test
        func statusIsReadFromTheTotpRoute() async throws {
            stub(statusCode: 200, body: #"{"enabled":true,"pending":false,"confirmedAt":"2026-11-10","recoveryCodesLeft":5}"#)

            let status = try await makeClient().fetchTwoFactorStatus(serverURL)

            #expect(status.isEnabled)
            #expect(status.recoveryCodesLeft == 5)
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/api/auth/totp")
        }

        @Test
        func beginningSetupPostsAnEmptyObjectAndDecodesTheSecret() async throws {
            stub(statusCode: 200, body: #"{"secret":"JBSWY3DPEHPK3PXP","uri":"otpauth://totp/x"}"#)

            let setup = try await makeClient().beginTwoFactorSetup(serverURL)

            #expect(setup.secret == "JBSWY3DPEHPK3PXP")
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/auth/totp/start")
            #expect(try sentJSON().isEmpty)
        }

        @Test
        func beginningSetupWithoutAPasswordSessionSurfacesTheMessage() async throws {
            stub(statusCode: 403, body: #"{"success":false,"error":{"message":"Sign in with your password","statusCode":403}}"#)

            await #expect(throws: FilesClientError.serverMessage(statusCode: 403, message: "Sign in with your password")) {
                try await makeClient().beginTwoFactorSetup(serverURL)
            }
        }

        @Test
        func beginningSetupWhenAlreadyOnIsAConflict() async throws {
            stub(statusCode: 409, body: #"{"success":false,"error":{"message":"Already enabled","statusCode":409}}"#)

            await #expect(throws: FilesClientError.serverMessage(statusCode: 409, message: "Already enabled")) {
                try await makeClient().beginTwoFactorSetup(serverURL)
            }
        }

        @Test
        func confirmingPostsTheCodeAndReturnsTheRecoveryCodes() async throws {
            stub(statusCode: 200, body: #"{"recoveryCodes":["AAAAA-BBBBB","CCCCC-DDDDD"]}"#)

            let codes = try await makeClient().confirmTwoFactorSetup(serverURL, "123456")

            #expect(codes == ["AAAAA-BBBBB", "CCCCC-DDDDD"])
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/auth/totp/confirm")
            #expect(try sentJSON() == ["code": "123456"])
        }

        @Test
        func aWrongCodeIsAnErrorWithTheServersMessageNotAnExpiredSession() async throws {
            stub(statusCode: 401, body: #"{"success":false,"error":{"message":"Invalid code","statusCode":401}}"#)

            await #expect(throws: FilesClientError.serverMessage(statusCode: 401, message: "Invalid code")) {
                try await makeClient().confirmTwoFactorSetup(serverURL, "000000")
            }
        }

        @Test
        func anUnreadableConfirmationIsADecodingError() async throws {
            stub(statusCode: 200, body: #"{"unexpected":true}"#)

            await #expect(throws: FilesClientError.self) {
                try await makeClient().confirmTwoFactorSetup(serverURL, "123456")
            }
        }

        @Test
        func replacingRecoveryCodesPostsThePassword() async throws {
            stub(statusCode: 200, body: #"{"recoveryCodes":["EEEEE-FFFFF"]}"#)

            let codes = try await makeClient().replaceRecoveryCodes(serverURL, "hunter2")

            #expect(codes == ["EEEEE-FFFFF"])
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/auth/totp/recovery-codes")
            #expect(try sentJSON() == ["password": "hunter2"])
        }

        @Test
        func disablingSendsADeleteWithThePasswordInTheBody() async throws {
            stub(statusCode: 204)

            try await makeClient().disableTwoFactor(serverURL, "hunter2")

            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == "DELETE")
            #expect(request.url?.path == "/api/auth/totp")
            #expect(try sentJSON() == ["password": "hunter2"])
        }

        @Test
        func aWrongPasswordWhenDisablingSurfacesTheMessage() async throws {
            stub(statusCode: 401, body: #"{"success":false,"error":{"message":"Incorrect password","statusCode":401}}"#)

            await #expect(throws: FilesClientError.serverMessage(statusCode: 401, message: "Incorrect password")) {
                try await makeClient().disableTwoFactor(serverURL, "nope")
            }
        }

        @Test
        func theRoutesAreRateLimited() async throws {
            stub(statusCode: 429)

            await #expect(throws: FilesClientError.rateLimited) {
                try await makeClient().confirmTwoFactorSetup(serverURL, "123456")
            }
        }
    }
}
