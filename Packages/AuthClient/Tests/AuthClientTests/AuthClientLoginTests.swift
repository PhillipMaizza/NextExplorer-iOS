@testable import AuthClient
import CoreModels
import Foundation
import Keychain
import NetworkClient
import Testing

@Suite("AuthClient login")
struct AuthClientLoginTests: AuthClientLiveHarness {
    let serverURL = makeUniqueServerURL()

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
            let body = try AuthClientFixture.sessionUserAdmin.data()
            return try (body, response(statusCode: 200, url: url))
        }

        let user = try await client.login(serverURL, "phillip", "hunter2")
        #expect(user.username == "phillip")

        let stored = try #require(try keychainClient.load("storedSessions"))
        let sessions = try JSONDecoder().decode(StoredSessions.self, from: stored)
        let credentials = try #require(sessions.active)
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
        #expect(try keychainClient.load("storedSessions") == nil)
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
            let responseBody = try AuthClientFixture.sessionUserPhillipNoRoles.data()
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
            let body = try AuthClientFixture.sessionUserPhillipNoRoles.data()
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
            let body = try AuthClientFixture.sessionUserPhillipNoRoles.data()
            return try (body, response(statusCode: 200, url: url))
        }

        do {
            _ = try await client.login(serverURL, "phillip", "hunter2")
            Issue.record("expected login to throw")
        } catch AuthClientError.keychain {
            // expected
        }
    }
}
