@testable import AuthClient
import CoreModels
import Foundation
import Keychain
import NetworkClient
import Testing
import TestUtils

@Suite("AuthClient fetchStatus")
struct AuthClientStatusTests: AuthClientLiveHarness {
    let serverURL = makeUniqueServerURL()

    @Test("fetchStatus happy path decodes both flags")
    func fetchStatusHappyPath() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage()) { request in
            let url = try #require(request.url)
            let body = try AuthClientFixture.statusLocalOnly.data()
            return try (body, response(statusCode: 200, url: url))
        }
        let status = try await client.fetchStatus(serverURL)
        #expect(status.isLocalEnabled == true)
        #expect(status.isOIDCEnabled == false)
    }

    @Test("fetchStatus edge case: malformed body throws decoding error")
    func fetchStatusMalformedBody() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage()) { request in
            let url = try #require(request.url)
            return try (Data("not json".utf8), response(statusCode: 200, url: url))
        }
        await #expect(throws: AuthClientError.self) {
            _ = try await client.fetchStatus(serverURL)
        }
    }

    @Test("fetchStatus unexpected error: server 500 maps to AuthClientError.server")
    func fetchStatusServerError() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage()) { request in
            let url = try #require(request.url)
            return try (Data(), response(statusCode: 500, url: url))
        }
        do {
            _ = try await client.fetchStatus(serverURL)
            Issue.record("expected fetchStatus to throw")
        } catch let AuthClientError.server(statusCode) {
            #expect(statusCode == 500)
        }
    }

    @Test("fetchStatus unexpected error: transport failure is wrapped, not propagated raw")
    func fetchStatusTransportFailure() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage()) { _ in
            throw NetworkError.transport(TestFailure.offline)
        }
        await #expect(throws: AuthClientError.self) {
            _ = try await client.fetchStatus(serverURL)
        }
    }

    @Test("Only an http address answered from https on the same host counts as upgraded")
    func redirectToHTTPS() {
        let http = URL(string: Constants.statusURLString)!
        #expect(LocalAuthService.redirectsToHTTPS(requested: http, answered: URL(string: Constants.authStatusURL)))
        #expect(!LocalAuthService.redirectsToHTTPS(requested: http, answered: http))
        #expect(!LocalAuthService.redirectsToHTTPS(requested: http, answered: URL(string: "https://elsewhere.example.com/api/auth/status")))
        #expect(!LocalAuthService.redirectsToHTTPS(requested: URL(string: TestHost.serverURLString)!, answered: URL(string: TestHost.serverURLString)))
        #expect(!LocalAuthService.redirectsToHTTPS(requested: http, answered: nil))
    }

    @Test(
        "The port the server answered on is kept only when it is not the default https port",
        arguments: [
            (Constants.authStatusURLWithPort, Constants.authStatusURL, nil as Int?),
            (Constants.authStatusURLWithPort, "https://files.example.com:443/api/auth/status", nil as Int?),
            (Constants.authStatusURLWithPort, "https://files.example.com:9443/api/auth/status", 9443),
            ("http://files.example.com:8443/api/auth/status", "https://files.example.com:8443/api/auth/status", 8443),
            (Constants.statusURLString, Constants.authStatusURL, nil as Int?),
        ]
    )
    func redirectedPort(requested: String, answered: String, expected: Int?) throws {
        let requestedURL = try #require(URL(string: requested))
        let answeredURL = try #require(URL(string: answered))
        #expect(LocalAuthService.redirectsToHTTPS(requested: requestedURL, answered: answeredURL))
        #expect(LocalAuthService.answeredPort(answeredURL) == expected)
    }

    @Test("A missing answered URL has no port to carry")
    func noAnsweredURLHasNoPort() {
        #expect(LocalAuthService.answeredPort(nil) == nil)
    }

    @Test("fetchStatus reports the port of the https address that answered an http one")
    func fetchStatusCarriesTheAnsweredPort() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage()) { request in
            let url = try #require(request.url)
            let host = try #require(url.host)
            let answered = try #require(URL(string: "https://\(host):9443/api/auth/status"))
            let body = try AuthClientFixture.statusLocalOnly.data()
            return try (body, response(statusCode: 200, url: answered))
        }
        let requested = try #require(URL(string: "http://files.example.com:8080"))
        let status = try await client.fetchStatus(requested)
        #expect(status.redirectsToHTTPS)
        #expect(status.redirectedPort == 9443)
    }

    @Test("fetchStatus without a redirect carries no port")
    func fetchStatusWithoutRedirectHasNoPort() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage()) { request in
            let url = try #require(request.url)
            let body = try AuthClientFixture.statusLocalOnly.data()
            return try (body, response(statusCode: 200, url: url))
        }
        let status = try await client.fetchStatus(serverURL)
        #expect(!status.redirectsToHTTPS)
        #expect(status.redirectedPort == nil)
    }
}

private enum Constants {
    static let statusURLString = "http://files.example.com/api/auth/status"
    static let authStatusURL = "https://files.example.com/api/auth/status"
    static let authStatusURLWithPort = "http://files.example.com:8080/api/auth/status"
}
