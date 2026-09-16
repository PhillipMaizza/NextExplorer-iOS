@testable import AuthClient
import CoreModels
import Foundation
import Keychain
import NetworkClient
import Testing

@Suite("AuthClient live implementation")
struct AuthClientLiveTests {
    private let serverURL = URL(
        string: "http://test-\(UUID().uuidString.lowercased()).invalid:3000"
    ) ?? URL(fileURLWithPath: "/")

    private func makeCookieStorage() -> HTTPCookieStorage {
        .shared
    }

    private func makeClient(
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

    private func response(statusCode: Int, url: URL) throws -> HTTPURLResponse {
        try #require(HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil))
    }

    // MARK: - fetchStatus

    @Test("fetchStatus happy path decodes both flags")
    func fetchStatusHappyPath() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage()) { request in
            let url = try #require(request.url)
            let body = Data(#"{"strategies":{"local":true,"oidc":false}}"#.utf8)
            return try (body, response(statusCode: 200, url: url))
        }
        let status = try await client.fetchStatus(serverURL)
        #expect(status.localEnabled == true)
        #expect(status.oidcEnabled == false)
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
            throw NetworkError.transport("offline")
        }
        await #expect(throws: AuthClientError.self) {
            _ = try await client.fetchStatus(serverURL)
        }
    }

    // MARK: - login

    @Test("login happy path returns the user and persists the session cookie")
    func loginHappyPath() async throws {
        let cookieStorage = makeCookieStorage()
        let keychainClient = KeychainClient.inMemory()

        let client = makeClient(cookieStorage: cookieStorage, keychainClient: keychainClient) { request in
            let url = try #require(request.url)
            if let host = url.host {
                let cookie = try #require(HTTPCookie(properties: [
                    .name: AuthClientConfiguration.CookieName.local,
                    .value: "abc123",
                    .domain: host,
                    .path: "/",
                ]))
                cookieStorage.setCookie(cookie)
            }
            let body = Data(#"{"user":{"id":"1","username":"phillip","roles":["admin"]}}"#.utf8)
            return try (body, response(statusCode: 200, url: url))
        }

        let user = try await client.login(serverURL, "phillip", "hunter2")
        #expect(user.username == "phillip")

        let stored = try #require(try keychainClient.load("currentSession"))
        let credentials = try JSONDecoder().decode(SessionCredentials.self, from: stored)
        #expect(credentials.cookieValue == "abc123")
        #expect(credentials.authMode == .local)
    }

    @Test("login edge case: invalid credentials surfaces as AuthClientError.invalidCredentials, nothing persisted")
    func loginInvalidCredentials() async throws {
        let keychainClient = KeychainClient.inMemory()
        let client = makeClient(cookieStorage: makeCookieStorage(), keychainClient: keychainClient) { request in
            let url = try #require(request.url)
            return try (Data(), response(statusCode: 401, url: url))
        }

        await #expect(throws: AuthClientError.invalidCredentials) {
            _ = try await client.login(serverURL, "phillip", "wrong")
        }
        #expect(try keychainClient.load("currentSession") == nil)
    }

    @Test("regression: login request body sends the identifier as `email`, matching the real server's field name")
    func loginSendsEmailField() async throws {
        let cookieStorage = makeCookieStorage()
        let client = makeClient(cookieStorage: cookieStorage) { request in
            let url = try #require(request.url)
            let body = try #require(request.httpBody)
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(json["email"] == "phillip")
            #expect(json["identifier"] == nil)
            if let host = url.host {
                let cookie = try #require(HTTPCookie(properties: [
                    .name: AuthClientConfiguration.CookieName.local,
                    .value: "abc123",
                    .domain: host,
                    .path: "/",
                ]))
                cookieStorage.setCookie(cookie)
            }
            let responseBody = Data(#"{"user":{"id":"1","username":"phillip","roles":[]}}"#.utf8)
            return try (responseBody, response(statusCode: 200, url: url))
        }

        _ = try await client.login(serverURL, "phillip", "hunter2")
    }

    @Test("regression: 429 from the login route surfaces as AuthClientError.rateLimited")
    func loginRateLimited() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage()) { request in
            let url = try #require(request.url)
            return try (Data(), response(statusCode: 429, url: url))
        }

        await #expect(throws: AuthClientError.rateLimited) {
            _ = try await client.login(serverURL, "phillip", "hunter2")
        }
    }

    @Test("login edge case: 200 with no matching cookie throws sessionCookieMissing")
    func loginMissingCookie() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage()) { request in
            let url = try #require(request.url)
            let body = Data(#"{"user":{"id":"1","username":"phillip","roles":[]}}"#.utf8)
            return try (body, response(statusCode: 200, url: url))
        }

        await #expect(throws: AuthClientError.sessionCookieMissing) {
            _ = try await client.login(serverURL, "phillip", "hunter2")
        }
    }

    @Test("login edge case: malformed body on 200 surfaces as AuthClientError.decoding")
    func loginMalformedBody() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage()) { request in
            let url = try #require(request.url)
            return try (Data("not json".utf8), response(statusCode: 200, url: url))
        }
        await #expect(throws: AuthClientError.self) {
            _ = try await client.login(serverURL, "phillip", "hunter2")
        }
    }

    @Test("login error path: a keychain write failure surfaces as AuthClientError.keychain")
    func loginKeychainWriteFailureSurfaces() async throws {
        struct StubKeychainError: Error {}
        let cookieStorage = makeCookieStorage()
        let failingKeychainClient = KeychainClient(
            save: { _, _ in throw StubKeychainError() },
            load: { _ in nil },
            delete: { _ in }
        )

        let client = makeClient(cookieStorage: cookieStorage, keychainClient: failingKeychainClient) { request in
            let url = try #require(request.url)
            if let host = url.host {
                let cookie = try #require(HTTPCookie(properties: [
                    .name: AuthClientConfiguration.CookieName.local,
                    .value: "abc123",
                    .domain: host,
                    .path: "/",
                ]))
                cookieStorage.setCookie(cookie)
            }
            let body = Data(#"{"user":{"id":"1","username":"phillip","roles":[]}}"#.utf8)
            return try (body, response(statusCode: 200, url: url))
        }

        do {
            _ = try await client.login(serverURL, "phillip", "hunter2")
            Issue.record("expected login to throw")
        } catch AuthClientError.keychain {
            // expected
        }
    }

    // MARK: - me

    @Test("me happy path returns the decoded user")
    func meHappyPath() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage()) { request in
            let url = try #require(request.url)
            let body = Data(#"{"user":{"id":"1","username":"phillip","roles":["admin"]}}"#.utf8)
            return try (body, response(statusCode: 200, url: url))
        }
        let user = try await client.me(serverURL)
        #expect(user.username == "phillip")
        #expect(user.isAdmin == true)
    }

    @Test("me edge case: expired session surfaces as AuthClientError.sessionExpired")
    func meSessionExpired() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage()) { request in
            let url = try #require(request.url)
            return try (Data(), response(statusCode: 401, url: url))
        }
        await #expect(throws: AuthClientError.sessionExpired) {
            _ = try await client.me(serverURL)
        }
    }

    @Test("me edge case: 200 with a null user (server's alternate expired-session shape) still surfaces sessionExpired")
    func meNullUserWith200IsSessionExpired() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage()) { request in
            let url = try #require(request.url)
            return try (Data(#"{"user":null}"#.utf8), response(statusCode: 200, url: url))
        }
        await #expect(throws: AuthClientError.sessionExpired) {
            _ = try await client.me(serverURL)
        }
    }

    // MARK: - restoreSession / clearSession

    @Test("restoreSession happy path reinstalls the persisted cookie")
    func restoreSessionHappyPath() async throws {
        let keychainClient = KeychainClient.inMemory()
        let credentials = try SessionCredentials(
            serverBaseURL: serverURL,
            authMode: .local,
            cookieName: AuthClientConfiguration.CookieName.local,
            cookieValue: "restored-value",
            cookieDomain: #require(serverURL.host),
            cookiePath: "/",
            cookieIsSecure: false,
            expiresAt: nil,
            username: "phillip"
        )
        try keychainClient.save("currentSession", JSONEncoder().encode(credentials))

        let cookieStorage = makeCookieStorage()
        let client = makeClient(cookieStorage: cookieStorage, keychainClient: keychainClient) { _ in
            throw NetworkError.transport("should not be called")
        }

        let restored = try #require(await client.restoreSession())
        #expect(restored.cookieValue == "restored-value")

        let installedCookies = try #require(cookieStorage.cookies(for: serverURL))
        #expect(installedCookies.contains { $0.value == "restored-value" })
    }

    @Test("restoreSession edge case: nothing persisted returns nil")
    func restoreSessionNothingPersisted() async {
        let client = makeClient(cookieStorage: makeCookieStorage()) { _ in
            throw NetworkError.transport("should not be called")
        }
        let restored = await client.restoreSession()
        #expect(restored == nil)
    }

    @Test("clearSession removes the persisted credentials")
    func clearSessionRemovesPersisted() async throws {
        let keychainClient = KeychainClient.inMemory()
        try keychainClient.save("currentSession", Data("placeholder".utf8))

        let client = makeClient(cookieStorage: makeCookieStorage(), keychainClient: keychainClient) { _ in
            throw NetworkError.transport("should not be called")
        }
        await client.clearSession()
        #expect(try keychainClient.load("currentSession") == nil)
    }

    // MARK: - logout

    @Test("logout happy path: calls the server and clears the local session")
    func logoutHappyPath() async throws {
        let cookieStorage = makeCookieStorage()
        let keychainClient = KeychainClient.inMemory()
        try keychainClient.save("currentSession", Data("placeholder".utf8))
        if let host = serverURL.host {
            let cookie = try #require(HTTPCookie(properties: [
                .name: AuthClientConfiguration.CookieName.local,
                .value: "abc123",
                .domain: host,
                .path: "/",
            ]))
            cookieStorage.setCookie(cookie)
        }

        let client = makeClient(cookieStorage: cookieStorage, keychainClient: keychainClient) { request in
            let url = try #require(request.url)
            return try (Data(), response(statusCode: 200, url: url))
        }

        try await client.logout(serverURL)

        #expect(try keychainClient.load("currentSession") == nil)
        #expect(cookieStorage.cookies(for: serverURL)?.isEmpty ?? true)
    }

    @Test("logout edge case: server unreachable still clears the local session (best-effort)")
    func logoutServerUnreachableStillClearsLocalSession() async throws {
        let cookieStorage = makeCookieStorage()
        let keychainClient = KeychainClient.inMemory()
        try keychainClient.save("currentSession", Data("placeholder".utf8))

        let client = makeClient(cookieStorage: cookieStorage, keychainClient: keychainClient) { _ in
            throw NetworkError.transport("offline")
        }

        try await client.logout(serverURL)

        #expect(try keychainClient.load("currentSession") == nil)
    }

    @Test("logout edge case: session already expired (401) still clears the local session")
    func logoutAlreadyExpiredStillClearsLocalSession() async throws {
        let keychainClient = KeychainClient.inMemory()
        try keychainClient.save("currentSession", Data("placeholder".utf8))

        let client = makeClient(cookieStorage: makeCookieStorage(), keychainClient: keychainClient) { request in
            let url = try #require(request.url)
            return try (Data(), response(statusCode: 401, url: url))
        }

        try await client.logout(serverURL)

        #expect(try keychainClient.load("currentSession") == nil)
    }

    @Test("logout edge case: unexpected server error (500) still clears the local session")
    func logoutServerErrorStillClearsLocalSession() async throws {
        let keychainClient = KeychainClient.inMemory()
        try keychainClient.save("currentSession", Data("placeholder".utf8))

        let client = makeClient(cookieStorage: makeCookieStorage(), keychainClient: keychainClient) { request in
            let url = try #require(request.url)
            return try (Data(), response(statusCode: 500, url: url))
        }

        try await client.logout(serverURL)

        #expect(try keychainClient.load("currentSession") == nil)
    }
}
