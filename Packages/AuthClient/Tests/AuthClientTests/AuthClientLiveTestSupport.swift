@testable import AuthClient
import CoreModels
import Foundation
import Keychain
import NetworkClient
import Testing

func makeUniqueServerURL() -> URL {
    URL(string: "http://test-\(UUID().uuidString.lowercased()).invalid:3000") ?? URL(fileURLWithPath: "/")
}

/// Fixtures shared by the AuthClient live suites. Each suite owns a unique `serverURL` so cookies
/// written to the shared cookie storage never collide between tests.
protocol AuthClientLiveHarness {
    var serverURL: URL { get }
}

extension AuthClientLiveHarness {
    func makeCookieStorage() -> HTTPCookieStorage {
        .shared
    }

    func makeClient(
        cookieStorage: HTTPCookieStorage,
        keychainClient: KeychainClient = .inMemory(),
        handler: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    ) -> AuthClient {
        var networkClient = NetworkClient()
        networkClient.send = handler
        return .live(
            networkClient: networkClient,
            keychainClient: keychainClient,
            cookieStorage: cookieStorage
        )
    }

    func response(statusCode: Int, url: URL) throws -> HTTPURLResponse {
        try #require(HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil))
    }

    func credentials() throws -> SessionCredentials {
        try SessionCredentials(
            serverBaseURL: serverURL,
            authMode: .local,
            cookieName: AuthClientConfiguration.CookieName.local,
            cookieValue: "abc123",
            cookieDomain: #require(serverURL.host),
            cookiePath: "/",
            cookieIsSecure: false,
            expiresAt: nil,
            username: "phillip"
        )
    }

    func okHandler() -> @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse) {
        { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (Data(), response)
        }
    }
}
