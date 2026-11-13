@testable import AuthClient
import CoreModels
import Foundation
import NetworkClient
import Testing
import TestUtils

@Suite("LocalAuthService")
struct LocalAuthServiceTests {
    private let serverURL = TestHost.serverURL

    private func makeService(
        _ handler: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    ) -> LocalAuthService {
        var networkClient = NetworkClient()
        networkClient.send = handler
        return LocalAuthService(networkClient: networkClient)
    }

    private func answer(_ request: URLRequest, status: Int, body: Data = Data()) throws -> (Data, HTTPURLResponse) {
        let url = try #require(request.url)
        return try (body, #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)))
    }

    // MARK: OIDC exchange

    @Test("the exchange posts the one time code and the verifier to the exchange route and returns the user")
    func exchangeSendsCodeAndVerifier() async throws {
        let captured = LockedBox<URLRequest?>(nil)
        let service = makeService { request in
            captured.set(request)
            return try answer(request, status: 200, body: AuthClientFixture.sessionUserAdmin.data())
        }

        let user = try await service.exchangeOIDC(
            serverURL: serverURL,
            code: Constants.code,
            codeVerifier: Constants.verifier
        )

        #expect(user.username == TestAccount.username)
        let request = try #require(captured.value)
        #expect(request.url?.absoluteString == "https://files.example.com/api/auth/oidc/exchange")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        let body = try #require(request.httpBody)
        let sent = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(sent == ["code": Constants.code, "code_verifier": Constants.verifier])
    }

    private struct FailureCase: Sendable, CustomTestStringConvertible {
        let status: Int
        let fixture: AuthClientFixture?
        let expected: AuthClientError

        var testDescription: String {
            "status \(status)"
        }
    }

    private static let exchangeFailures = [
        FailureCase(status: 401, fixture: nil, expected: .oidcFailed("exchange rejected")),
        FailureCase(status: 429, fixture: nil, expected: .rateLimited),
        FailureCase(status: 500, fixture: nil, expected: .server(statusCode: 500)),
        FailureCase(status: 200, fixture: .sessionUserNull, expected: .oidcFailed("no user in exchange response")),
        FailureCase(status: 200, fixture: .commonEmptyObject, expected: .oidcFailed("no user in exchange response")),
    ]

    @Test(
        "an exchange the server refuses or answers without a user fails with the matching error",
        arguments: exchangeFailures
    )
    private func exchangeFailsWithMatchingError(_ testCase: FailureCase) async throws {
        let body = try testCase.fixture?.data() ?? Data()
        let service = makeService { request in try answer(request, status: testCase.status, body: body) }

        await #expect(throws: testCase.expected) {
            _ = try await service.exchangeOIDC(
                serverURL: serverURL,
                code: Constants.code,
                codeVerifier: Constants.verifier
            )
        }
    }

    @Test("an exchange answer that is not JSON is a decoding failure")
    func exchangeMalformedBody() async throws {
        let body = try AuthClientFixture.commonMalformedJson.data()
        let service = makeService { request in try answer(request, status: 200, body: body) }

        do {
            _ = try await service.exchangeOIDC(
                serverURL: serverURL,
                code: Constants.code,
                codeVerifier: Constants.verifier
            )
            Issue.record("expected the exchange to fail")
        } catch let error as AuthClientError {
            guard case .decoding = error else {
                Issue.record("expected a decoding error, got \(error)")
                return
            }
        } catch {
            Issue.record("expected an AuthClientError, got \(error)")
        }
    }

    // MARK: Transport failures on every route

    private enum Operation: CaseIterable, Sendable {
        case status, login, loginTOTP, exchangeOIDC, me, logout

        func run(_ service: LocalAuthService, serverURL: URL) async throws {
            switch self {
            case .status: _ = try await service.status(serverURL: serverURL)
            case .login: _ = try await service.login(
                    serverURL: serverURL,
                    identifier: TestAccount.username,
                    password: TestAccount.password
                )
            case .loginTOTP: _ = try await service.loginTOTP(serverURL: serverURL, code: TestAccount.totpCode)
            case .exchangeOIDC: _ = try await service.exchangeOIDC(
                    serverURL: serverURL,
                    code: Constants.code,
                    codeVerifier: Constants.verifier
                )
            case .me: _ = try await service.me(serverURL: serverURL)
            case .logout: try await service.logout(serverURL: serverURL)
            }
        }
    }

    private struct TransportCase: Sendable {
        let networkError: NetworkError
        let expected: AuthClientError
    }

    private static let transportCases = [
        TransportCase(networkError: .clientCertificateRequired, expected: .clientCertificateRequired),
        TransportCase(networkError: .clientCertificateRejected, expected: .clientCertificateRejected),
        TransportCase(networkError: .offline, expected: .network("offline")),
        TransportCase(networkError: .timedOut, expected: .network("timedOut")),
        TransportCase(networkError: .transport(TestFailure.offline), expected: .network("transport(\"offline\")")),
    ]

    @Test(
        "a client certificate refusal keeps its own error and every other transport failure becomes a network error, on every route",
        arguments: transportCases
    )
    private func transportFailuresAreMapped(_ testCase: TransportCase) async {
        let service = makeService { _ in throw testCase.networkError }

        for operation in Operation.allCases {
            await #expect(throws: testCase.expected, "\(operation)") {
                try await operation.run(service, serverURL: serverURL)
            }
        }
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    var value: Value {
        lock.withLock { stored }
    }

    func set(_ value: Value) {
        lock.withLock { stored = value }
    }
}

private enum Constants {
    static let code = "one-time-code"
    static let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
}
