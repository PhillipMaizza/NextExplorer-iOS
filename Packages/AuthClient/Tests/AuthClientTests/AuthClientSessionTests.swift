@testable import AuthClient
import CoreModels
import Foundation
import Keychain
import NetworkClient
import Testing
import TestUtils

@Suite("AuthClient sessions")
struct AuthClientSessionTests: AuthClientLiveHarness {
    let serverURL = makeUniqueServerURL()

    @Test("me happy path returns the decoded user")
    func meHappyPath() async throws {
        let client = makeClient(cookieStorage: makeCookieStorage()) { request in
            let url = try #require(request.url)
            let body = try AuthClientFixture.sessionUserAdmin.data()
            return try (body, response(statusCode: 200, url: url))
        }
        let user = try await client.me(serverURL)
        #expect(user.username == TestAccount.username)
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
            return try (AuthClientFixture.sessionUserNull.data(), response(statusCode: 200, url: url))
        }
        await #expect(throws: AuthClientError.sessionExpired) {
            _ = try await client.me(serverURL)
        }
    }

    @Test("restoreSession happy path reinstalls the persisted cookie")
    func restoreSessionHappyPath() async throws {
        let keychainClient = KeychainClient.inMemory()
        let credentials = try SessionCredentials(
            serverBaseURL: serverURL,
            authMode: .local,
            cookieName: AuthClientConfiguration.CookieName.local,
            cookieValue: Constants.restoredValue,
            cookieDomain: #require(serverURL.host),
            cookiePath: "/",
            cookieIsSecure: false,
            expiresAt: nil,
            username: TestAccount.username
        )
        try keychainClient.save(TestStorageKey.legacySession, JSONEncoder().encode(credentials))

        let cookieStorage = makeCookieStorage()
        let client = makeClient(cookieStorage: cookieStorage, keychainClient: keychainClient) { _ in
            throw NetworkError.transport(Constants.unexpectedCallMessage)
        }

        let restored = try #require(await client.restoreSession())
        #expect(restored.cookieValue == Constants.restoredValue)

        let installedCookies = try #require(cookieStorage.cookies(for: serverURL))
        #expect(installedCookies.contains { $0.value == Constants.restoredValue })
    }

    @Test("restoreSession edge case: nothing persisted returns nil")
    func restoreSessionNothingPersisted() async {
        let client = makeClient(cookieStorage: makeCookieStorage()) { _ in
            throw NetworkError.transport(Constants.unexpectedCallMessage)
        }
        let restored = await client.restoreSession()
        #expect(restored == nil)
    }

    @Test("clearAllSessions removes the persisted credentials")
    func clearAllSessionsRemovesPersisted() async throws {
        let keychainClient = KeychainClient.inMemory()
        try keychainClient.save(TestStorageKey.storedSessions, Data("placeholder".utf8))

        let client = makeClient(cookieStorage: makeCookieStorage(), keychainClient: keychainClient) { _ in
            throw NetworkError.transport(Constants.unexpectedCallMessage)
        }
        await client.clearAllSessions()
        #expect(try keychainClient.load(TestStorageKey.storedSessions) == nil)
    }

    @Test("logout edge case: server unreachable is swallowed (best-effort) and the local session is left to removeAccount")
    func logoutServerUnreachableIsBestEffort() async throws {
        let cookieStorage = makeCookieStorage()
        let keychainClient = KeychainClient.inMemory()
        let credentials = try credentials()
        let store = SessionCookieStore(keychainClient: keychainClient, cookieStorage: cookieStorage)
        try store.persist(credentials)
        let attempts = RecordedPaths()
        let client = makeClient(cookieStorage: cookieStorage, keychainClient: keychainClient) { request in
            attempts.add(request.url?.path ?? "")
            throw NetworkError.transport(TestFailure.offline)
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
        let credentials = try credentials()
        let store = SessionCookieStore(keychainClient: keychainClient, cookieStorage: cookieStorage)
        try store.persist(credentials)
        let client = makeClient(cookieStorage: cookieStorage, keychainClient: keychainClient) { _ in
            throw NetworkError.transport(TestFailure.offline)
        }

        let next = await client.removeAccount(credentials.accountID)

        #expect(next == nil)
        #expect(store.activeCredentials() == nil)
        #expect(store.allSessions().isEmpty)
        #expect(cookieStorage.cookies(for: serverURL)?.isEmpty ?? true)
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
        try keychain.save(TestStorageKey.storedSessions, Data("not json".utf8))
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

private enum Constants {
    static let restoredValue = "restored-value"
    static let unexpectedCallMessage = "should not be called"
}
