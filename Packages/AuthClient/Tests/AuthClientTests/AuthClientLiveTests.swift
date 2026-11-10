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

    // MARK: - second factor

    @Test("regression NXTIOS-0095: a 200 with totpRequired and no user is a second factor request, not invalid credentials, nothing persisted")
    func loginSecondFactorRequired() async throws {
        let keychainClient = KeychainClient.inMemory()
        let client = makeClient(cookieStorage: makeCookieStorage(), keychainClient: keychainClient) { request in
            let url = try #require(request.url)
            return try (Data(#"{"totpRequired":true}"#.utf8), response(statusCode: 200, url: url))
        }

        await #expect(throws: AuthClientError.secondFactorRequired) {
            _ = try await client.login(serverURL, "asmith", "hunter2")
        }
        #expect(try keychainClient.load("storedSessions") == nil)
    }

    @Test("login edge case: a 200 with neither a user nor totpRequired is a decoding error, not invalid credentials")
    func loginEmptyBodyIsNotInvalidCredentials() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage()) { request in
            let url = try #require(request.url)
            return try (Data("{}".utf8), response(statusCode: 200, url: url))
        }

        await #expect(throws: AuthClientError.decoding("sign in response had no user")) {
            _ = try await client.login(serverURL, "asmith", "hunter2")
        }
    }

    @Test("login edge case: totpRequired false with a user still signs in")
    func loginTOTPFalseSignsIn() async throws {
        let cookieStorage = makeCookieStorage()
        let client = makeClient(cookieStorage: cookieStorage) { request in
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
            let body = Data(#"{"totpRequired":false,"user":{"id":"1","username":"phillip","roles":[]}}"#.utf8)
            return try (body, response(statusCode: 200, url: url))
        }

        let user = try await client.login(serverURL, "phillip", "hunter2")
        #expect(user.username == "phillip")
    }

    @Test("loginTOTP happy path posts the code to the totp route, returns the user and persists the session cookie")
    func loginTOTPHappyPath() async throws {
        let cookieStorage = makeCookieStorage()
        let keychainClient = KeychainClient.inMemory()
        let client = makeClient(cookieStorage: cookieStorage, keychainClient: keychainClient) { request in
            let url = try #require(request.url)
            #expect(url.path == "/api/auth/login/totp")
            #expect(request.httpMethod == "POST")
            let body = try #require(request.httpBody)
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(json == ["code": "123456"])
            if let host = url.host {
                let cookie = try #require(HTTPCookie(properties: [
                    .name: AuthClientConfiguration.CookieName.local,
                    .value: "second-step-done",
                    .domain: host,
                    .path: "/",
                ]))
                cookieStorage.setCookie(cookie)
            }
            let responseBody = Data(#"{"user":{"id":"1","username":"asmith","roles":["admin"]},"usedRecoveryCode":false,"recoveryCodesLeft":null}"#.utf8)
            return try (responseBody, response(statusCode: 200, url: url))
        }

        let user = try await client.loginTOTP(serverURL, "123456")
        #expect(user.username == "asmith")

        let stored = try #require(try keychainClient.load("storedSessions"))
        let sessions = try JSONDecoder().decode(StoredSessions.self, from: stored)
        let credentials = try #require(sessions.active)
        #expect(credentials.cookieValue == "second-step-done")
        #expect(credentials.authMode == .local)
    }

    @Test("loginTOTP edge case: a recovery code is sent verbatim, not reshaped")
    func loginTOTPSendsRecoveryCodeVerbatim() async throws {
        let cookieStorage = makeCookieStorage()
        let client = makeClient(cookieStorage: cookieStorage) { request in
            let url = try #require(request.url)
            let body = try #require(request.httpBody)
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(json["code"] == "2HSMP-G9ZSJ")
            if let host = url.host {
                let cookie = try #require(HTTPCookie(properties: [
                    .name: AuthClientConfiguration.CookieName.local,
                    .value: "abc123",
                    .domain: host,
                    .path: "/",
                ]))
                cookieStorage.setCookie(cookie)
            }
            let responseBody = Data(#"{"user":{"id":"1","username":"asmith","roles":[]},"usedRecoveryCode":true,"recoveryCodesLeft":9}"#.utf8)
            return try (responseBody, response(statusCode: 200, url: url))
        }

        _ = try await client.loginTOTP(serverURL, "2HSMP-G9ZSJ")
    }

    @Test("loginTOTP error path: a 401 carrying AUTH_INVALID_TOTP_CODE is invalidCode, nothing persisted")
    func loginTOTPInvalidCode() async throws {
        let keychainClient = KeychainClient.inMemory()
        let client = makeClient(cookieStorage: makeCookieStorage(), keychainClient: keychainClient) { request in
            let url = try #require(request.url)
            let body = Data(#"{"success":false,"error":{"message":"That code is not right.","statusCode":401,"code":"AUTH_INVALID_TOTP_CODE"}}"#.utf8)
            return try (body, response(statusCode: 401, url: url))
        }

        await #expect(throws: AuthClientError.invalidCode) {
            _ = try await client.loginTOTP(serverURL, "000000")
        }
        #expect(try keychainClient.load("storedSessions") == nil)
    }

    @Test("loginTOTP error path: a 401 for a sign in no longer waiting is secondFactorExpired")
    func loginTOTPExpired() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage()) { request in
            let url = try #require(request.url)
            let body = Data(#"{"success":false,"error":{"message":"That sign-in is no longer waiting for a code. Sign in again.","statusCode":401,"code":"AUTH_INVALID_CREDENTIALS"}}"#.utf8)
            return try (body, response(statusCode: 401, url: url))
        }

        await #expect(throws: AuthClientError.secondFactorExpired) {
            _ = try await client.loginTOTP(serverURL, "123456")
        }
    }

    @Test("loginTOTP edge case: a 401 with an unreadable body is secondFactorExpired, never invalidCode")
    func loginTOTPUnreadableErrorBody() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage()) { request in
            let url = try #require(request.url)
            return try (Data("<html>proxy</html>".utf8), response(statusCode: 401, url: url))
        }

        await #expect(throws: AuthClientError.secondFactorExpired) {
            _ = try await client.loginTOTP(serverURL, "123456")
        }
    }

    @Test("loginTOTP error path: 429 surfaces as rateLimited, which covers the account lockout")
    func loginTOTPRateLimited() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage()) { request in
            let url = try #require(request.url)
            return try (Data(), response(statusCode: 429, url: url))
        }

        await #expect(throws: AuthClientError.rateLimited) {
            _ = try await client.loginTOTP(serverURL, "123456")
        }
    }

    @Test("loginTOTP error path: a 500 surfaces as server with its status code")
    func loginTOTPServerError() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage()) { request in
            let url = try #require(request.url)
            return try (Data(), response(statusCode: 500, url: url))
        }

        await #expect(throws: AuthClientError.server(statusCode: 500)) {
            _ = try await client.loginTOTP(serverURL, "123456")
        }
    }

    @Test("loginTOTP edge case: a 200 without a user is a decoding error")
    func loginTOTPNoUser() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage()) { request in
            let url = try #require(request.url)
            return try (Data("{}".utf8), response(statusCode: 200, url: url))
        }

        await #expect(throws: AuthClientError.decoding("code response had no user")) {
            _ = try await client.loginTOTP(serverURL, "123456")
        }
    }

    @Test("loginTOTP error path: a transport failure is wrapped as network")
    func loginTOTPTransportFailure() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage()) { _ in
            throw NetworkError.transport("offline")
        }

        await #expect(throws: AuthClientError.self) {
            _ = try await client.loginTOTP(serverURL, "123456")
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

    // MARK: - restoreSession / clearAllSessions

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

    @Test("clearAllSessions removes the persisted credentials")
    func clearAllSessionsRemovesPersisted() async throws {
        let keychainClient = KeychainClient.inMemory()
        try keychainClient.save("storedSessions", Data("placeholder".utf8))

        let client = makeClient(cookieStorage: makeCookieStorage(), keychainClient: keychainClient) { _ in
            throw NetworkError.transport("should not be called")
        }
        await client.clearAllSessions()
        #expect(try keychainClient.load("storedSessions") == nil)
    }

    // MARK: - logout (server-side only; local teardown is removeAccount's job)

    @Test("logout edge case: server unreachable is swallowed (best-effort) and the local session is left to removeAccount")
    func logoutServerUnreachableIsBestEffort() async throws {
        let cookieStorage = makeCookieStorage()
        let keychainClient = KeychainClient.inMemory()
        let credentials = try localCredentials()
        let store = SessionCookieStore(keychainClient: keychainClient, cookieStorage: cookieStorage)
        try store.persist(credentials)
        let attempts = RecordedPaths()
        let client = makeClient(cookieStorage: cookieStorage, keychainClient: keychainClient) { request in
            attempts.add(request.url?.path ?? "")
            throw NetworkError.transport("offline")
        }

        try await client.logout(serverURL)

        #expect(attempts.paths.count == 1, "the server was asked once and the failure was swallowed")
        #expect(attempts.paths.first?.contains("logout") == true)
        #expect(store.activeCredentials() == credentials, "logout is server side only: removing the account is what clears it locally")
    }

    @Test("removeAccount edge case: an unreachable server still clears the session and cookie locally")
    func removeAccountServerUnreachableStillClearsLocally() async throws {
        let cookieStorage = makeCookieStorage()
        let keychainClient = KeychainClient.inMemory()
        let credentials = try localCredentials()
        let store = SessionCookieStore(keychainClient: keychainClient, cookieStorage: cookieStorage)
        try store.persist(credentials)
        let client = makeClient(cookieStorage: cookieStorage, keychainClient: keychainClient) { _ in
            throw NetworkError.transport("offline")
        }

        let next = await client.removeAccount(credentials.accountID)

        #expect(next == nil)
        #expect(store.activeCredentials() == nil)
        #expect(store.allSessions().isEmpty)
        #expect(cookieStorage.cookies(for: serverURL)?.isEmpty ?? true)
    }

    private func localCredentials() throws -> SessionCredentials {
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

    // MARK: - removeAccount

    @Test("Only an http address answered from https on the same host counts as upgraded")
    func redirectToHTTPS() {
        let http = URL(string: "http://files.example.com/api/auth/status")!
        #expect(LocalAuthService.redirectsToHTTPS(requested: http, answered: URL(string: "https://files.example.com/api/auth/status")))
        #expect(!LocalAuthService.redirectsToHTTPS(requested: http, answered: http))
        #expect(!LocalAuthService.redirectsToHTTPS(requested: http, answered: URL(string: "https://elsewhere.example.com/api/auth/status")))
        #expect(!LocalAuthService.redirectsToHTTPS(requested: URL(string: "https://files.example.com")!, answered: URL(string: "https://files.example.com")))
        #expect(!LocalAuthService.redirectsToHTTPS(requested: http, answered: nil))
    }

    @Test(
        "The port the server answered on is kept only when it is not the default https port",
        arguments: [
            ("http://files.example.com:8080/api/auth/status", "https://files.example.com/api/auth/status", nil as Int?),
            ("http://files.example.com:8080/api/auth/status", "https://files.example.com:443/api/auth/status", nil as Int?),
            ("http://files.example.com:8080/api/auth/status", "https://files.example.com:9443/api/auth/status", 9443),
            ("http://files.example.com:8443/api/auth/status", "https://files.example.com:8443/api/auth/status", 8443),
            ("http://files.example.com/api/auth/status", "https://files.example.com/api/auth/status", nil as Int?),
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
            let body = Data(#"{"strategies":{"local":true,"oidc":false}}"#.utf8)
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
            let body = Data(#"{"strategies":{"local":true,"oidc":false}}"#.utf8)
            return try (body, response(statusCode: 200, url: url))
        }
        let status = try await client.fetchStatus(serverURL)
        #expect(!status.redirectsToHTTPS)
        #expect(status.redirectedPort == nil)
    }

    // MARK: loadSession

    private func credentials() throws -> SessionCredentials {
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

    private func okHandler() -> @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse) {
        { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (Data(), response)
        }
    }

    @Test("loadSession returns nil when nothing is stored, which is a signed out user")
    func loadSessionWithNothingStored() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage(), handler: okHandler())
        #expect(try await client.loadSession() == nil)
    }

    @Test("loadSession returns the active account and installs its cookie")
    func loadSessionReturnsTheActiveAccount() async throws {
        let keychain = KeychainClient.inMemory()
        let stored = try credentials()
        try SessionCookieStore(keychainClient: keychain, cookieStorage: makeCookieStorage()).persist(stored)
        let client = makeClient(cookieStorage: makeCookieStorage(), keychainClient: keychain, handler: okHandler())

        #expect(try await client.loadSession() == stored)
    }

    @Test("loadSession throws a keychain error when the keychain can't be read, instead of looking signed out")
    func loadSessionKeychainReadFailure() async throws {
        struct StubKeychainError: Error {}
        let unreadable = KeychainClient(
            save: { _, _ in },
            load: { _ in throw StubKeychainError() },
            delete: { _ in }
        )
        let client = makeClient(cookieStorage: makeCookieStorage(), keychainClient: unreadable, handler: okHandler())

        do {
            _ = try await client.loadSession()
            Issue.record("expected loadSession to throw")
        } catch AuthClientError.keychain {
            // expected
        }
        #expect(await client.restoreSession() == nil, "the old call still reads as no account")
    }

    @Test("listSessionsOrThrow returns every stored account")
    func listSessionsOrThrowReturnsTheStoredAccounts() async throws {
        let keychain = KeychainClient.inMemory()
        let stored = try credentials()
        try SessionCookieStore(keychainClient: keychain, cookieStorage: makeCookieStorage()).persist(stored)
        let client = makeClient(cookieStorage: makeCookieStorage(), keychainClient: keychain, handler: okHandler())

        #expect(try await client.listSessionsOrThrow() == [stored])
    }

    @Test("listSessionsOrThrow is empty for an empty keychain but throws for an unreadable one, where listSessions looks empty")
    func listSessionsOrThrowSeparatesEmptyFromUnreadable() async throws {
        struct StubKeychainError: Error {}
        let empty = makeClient(cookieStorage: makeCookieStorage(), handler: okHandler())
        #expect(try await empty.listSessionsOrThrow().isEmpty)

        let unreadable = KeychainClient(
            save: { _, _ in },
            load: { _ in throw StubKeychainError() },
            delete: { _ in }
        )
        let client = makeClient(cookieStorage: makeCookieStorage(), keychainClient: unreadable, handler: okHandler())
        #expect(await client.listSessions().isEmpty)
        await #expect(throws: AuthClientError.self) {
            _ = try await client.listSessionsOrThrow()
        }
    }

    @Test("loadSession throws when the stored blob can't be decoded")
    func loadSessionCorruptBlob() async throws {
        let keychain = KeychainClient.inMemory()
        try keychain.save("storedSessions", Data("not json".utf8))
        let client = makeClient(cookieStorage: makeCookieStorage(), keychainClient: keychain, handler: okHandler())

        await #expect(throws: AuthClientError.self) {
            _ = try await client.loadSession()
        }
    }
}

/// The request paths a fake network saw, safe to write from the network closure.
private final class RecordedPaths: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    var paths: [String] {
        lock.withLock { stored }
    }

    func add(_ path: String) {
        lock.withLock { stored.append(path) }
    }
}
