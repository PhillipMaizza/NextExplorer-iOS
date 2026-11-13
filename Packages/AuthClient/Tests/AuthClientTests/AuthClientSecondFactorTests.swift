@testable import AuthClient
import CoreModels
import Foundation
import Keychain
import NetworkClient
import Testing
import TestUtils

@Suite("AuthClient second factor")
struct AuthClientSecondFactorTests: AuthClientLiveHarness {
    let serverURL = makeUniqueServerURL()

    @Test(
        "regression NXTIOS-0095: a 200 with totpRequired and no user is a second factor request, not invalid credentials, nothing persisted"
    )
    func loginSecondFactorRequired() async throws {
        let keychainClient = KeychainClient.inMemory()
        let client = makeClient(cookieStorage: makeCookieStorage(), keychainClient: keychainClient) { request in
            let url = try #require(request.url)
            return try (AuthClientFixture.secondFactorTotpRequired.data(), response(statusCode: 200, url: url))
        }

        await #expect(throws: AuthClientError.secondFactorRequired) {
            _ = try await client.login(serverURL, TestUser.asmith, TestAccount.password)
        }
        #expect(try keychainClient.load(TestStorageKey.storedSessions) == nil)
    }

    @Test("login edge case: a 200 with neither a user nor totpRequired is a decoding error, not invalid credentials")
    func loginEmptyBodyIsNotInvalidCredentials() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage()) { request in
            let url = try #require(request.url)
            return try (AuthClientFixture.commonEmptyObject.data(), response(statusCode: 200, url: url))
        }

        await #expect(throws: AuthClientError.decoding("sign in response had no user")) {
            _ = try await client.login(serverURL, TestUser.asmith, TestAccount.password)
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
                    .value: TestSession.loginCookieValue,
                    .domain: host,
                    .path: "/",
                ]))
                cookieStorage.setCookie(cookie)
            }
            let body = try AuthClientFixture.secondFactorTotpDoneWithUser.data()
            return try (body, response(statusCode: 200, url: url))
        }

        let user = try await client.login(serverURL, TestAccount.username, TestAccount.password)
        #expect(user.username == TestAccount.username)
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
            #expect(json == ["code": TestAccount.totpCode])
            if let host = url.host {
                let cookie = try #require(HTTPCookie(properties: [
                    .name: AuthClientConfiguration.CookieName.local,
                    .value: "second-step-done",
                    .domain: host,
                    .path: "/",
                ]))
                cookieStorage.setCookie(cookie)
            }
            let responseBody = try AuthClientFixture.secondFactorLoginAdminRecoveryUnused.data()
            return try (responseBody, response(statusCode: 200, url: url))
        }

        let user = try await client.loginTOTP(serverURL, TestAccount.totpCode)
        #expect(user.username == TestUser.asmith)

        let stored = try #require(try keychainClient.load(TestStorageKey.storedSessions))
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
            #expect(json["code"] == TestAccount.recoveryCode)
            if let host = url.host {
                let cookie = try #require(HTTPCookie(properties: [
                    .name: AuthClientConfiguration.CookieName.local,
                    .value: TestSession.loginCookieValue,
                    .domain: host,
                    .path: "/",
                ]))
                cookieStorage.setCookie(cookie)
            }
            let responseBody = try AuthClientFixture.secondFactorLoginRecoveryUsed.data()
            return try (responseBody, response(statusCode: 200, url: url))
        }

        _ = try await client.loginTOTP(serverURL, TestAccount.recoveryCode)
    }

    @Test("loginTOTP error path: a 401 carrying AUTH_INVALID_TOTP_CODE is invalidCode, nothing persisted")
    func loginTOTPInvalidCode() async throws {
        let keychainClient = KeychainClient.inMemory()
        let client = makeClient(cookieStorage: makeCookieStorage(), keychainClient: keychainClient) { request in
            let url = try #require(request.url)
            let body = try AuthClientFixture.secondFactorErrorInvalidCode.data()
            return try (body, response(statusCode: 401, url: url))
        }

        await #expect(throws: AuthClientError.invalidCode) {
            _ = try await client.loginTOTP(serverURL, TestAccount.invalidTotpCode)
        }
        #expect(try keychainClient.load(TestStorageKey.storedSessions) == nil)
    }

    @Test("loginTOTP error path: a 401 for a sign in no longer waiting is secondFactorExpired")
    func loginTOTPExpired() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage()) { request in
            let url = try #require(request.url)
            let body = try AuthClientFixture.secondFactorErrorNotWaiting.data()
            return try (body, response(statusCode: 401, url: url))
        }

        await #expect(throws: AuthClientError.secondFactorExpired) {
            _ = try await client.loginTOTP(serverURL, TestAccount.totpCode)
        }
    }

    @Test("loginTOTP edge case: a 401 with an unreadable body is secondFactorExpired, never invalidCode")
    func loginTOTPUnreadableErrorBody() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage()) { request in
            let url = try #require(request.url)
            return try (Data("<html>proxy</html>".utf8), response(statusCode: 401, url: url))
        }

        await #expect(throws: AuthClientError.secondFactorExpired) {
            _ = try await client.loginTOTP(serverURL, TestAccount.totpCode)
        }
    }

    @Test("loginTOTP error path: 429 surfaces as rateLimited, which covers the account lockout")
    func loginTOTPRateLimited() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage()) { request in
            let url = try #require(request.url)
            return try (Data(), response(statusCode: 429, url: url))
        }

        await #expect(throws: AuthClientError.rateLimited) {
            _ = try await client.loginTOTP(serverURL, TestAccount.totpCode)
        }
    }

    @Test("loginTOTP error path: a 500 surfaces as server with its status code")
    func loginTOTPServerError() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage()) { request in
            let url = try #require(request.url)
            return try (Data(), response(statusCode: 500, url: url))
        }

        await #expect(throws: AuthClientError.server(statusCode: 500)) {
            _ = try await client.loginTOTP(serverURL, TestAccount.totpCode)
        }
    }

    @Test("loginTOTP edge case: a 200 without a user is a decoding error")
    func loginTOTPNoUser() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage()) { request in
            let url = try #require(request.url)
            return try (AuthClientFixture.commonEmptyObject.data(), response(statusCode: 200, url: url))
        }

        await #expect(throws: AuthClientError.decoding("code response had no user")) {
            _ = try await client.loginTOTP(serverURL, TestAccount.totpCode)
        }
    }

    @Test("loginTOTP error path: a transport failure is wrapped as network")
    func loginTOTPTransportFailure() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage()) { _ in
            throw NetworkError.transport(TestFailure.offline)
        }

        await #expect(throws: AuthClientError.self) {
            _ = try await client.loginTOTP(serverURL, TestAccount.totpCode)
        }
    }
}
