@testable import AuthClient
import CoreModels
import Foundation
import Keychain
import NetworkClient
import Testing
import TestUtils

@Suite("AuthClient accounts")
struct AuthClientAccountsTests: AuthClientLiveHarness {
    let serverURL = makeUniqueServerURL()
    private let otherServerURL = makeUniqueServerURL()

    private func credentials(for url: URL, username: String, cookieValue: String) throws -> SessionCredentials {
        try SessionCredentials(
            serverBaseURL: url,
            authMode: .local,
            cookieName: AuthClientConfiguration.CookieName.local,
            cookieValue: cookieValue,
            cookieDomain: #require(url.host),
            cookiePath: "/",
            isCookieSecure: false,
            expiresAt: nil,
            username: username
        )
    }

    private struct Fixture {
        let client: AuthClient
        let keychain: KeychainClient
        let first: SessionCredentials
        let second: SessionCredentials
        let cookieStorage: HTTPCookieStorage
    }

    /// Two signed in accounts on two servers, the second one active.
    private func makeFixture() throws -> Fixture {
        let keychain = KeychainClient.inMemory()
        let first = try credentials(for: serverURL, username: TestUser.alice, cookieValue: TestSession.cookieValue)
        let second = try credentials(
            for: otherServerURL,
            username: TestUser.bob,
            cookieValue: TestSession.refreshedCookieValue
        )
        let stored = StoredSessions(sessions: [first, second], activeID: second.accountID)
        try keychain.save(TestStorageKey.storedSessions, JSONEncoder().encode(stored))
        let cookieStorage = makeCookieStorage()
        return Fixture(
            client: makeClient(cookieStorage: cookieStorage, keychainClient: keychain, handler: okHandler()),
            keychain: keychain,
            first: first,
            second: second,
            cookieStorage: cookieStorage
        )
    }

    private func storedSessions(_ keychain: KeychainClient) throws -> StoredSessions {
        let data = try #require(try keychain.load(TestStorageKey.storedSessions))
        return try JSONDecoder().decode(StoredSessions.self, from: data)
    }

    @Test("the active account id is the one marked active, and nil when nothing is stored")
    func activeAccountID() async throws {
        let fixture = try makeFixture()
        #expect(await fixture.client.activeAccountID() == fixture.second.accountID)

        let empty = makeClient(cookieStorage: makeCookieStorage(), handler: okHandler())
        #expect(await empty.activeAccountID() == nil)
    }

    @Test("switching installs the target's cookie, makes it active and persists the choice")
    func switchAccount() async throws {
        let fixture = try makeFixture()

        let switched = try await fixture.client.switchAccount(fixture.first.accountID)

        #expect(switched == fixture.first)
        #expect(await fixture.client.activeAccountID() == fixture.first.accountID)
        #expect(try storedSessions(fixture.keychain).activeID == fixture.first.accountID)
        let cookie = fixture.cookieStorage.cookies(for: serverURL)?
            .first { $0.name == AuthClientConfiguration.CookieName.local }
        #expect(cookie?.value == TestSession.cookieValue)
    }

    @Test("switching to an account that is not stored changes nothing")
    func switchToUnknownAccount() async throws {
        let fixture = try makeFixture()

        #expect(try await fixture.client.switchAccount(Constants.unknownAccountID) == nil)
        #expect(await fixture.client.activeAccountID() == fixture.second.accountID)
        #expect(try storedSessions(fixture.keychain) == StoredSessions(
            sessions: [fixture.first, fixture.second],
            activeID: fixture.second.accountID
        ))
    }

    @Test("clearing the active session drops only that account and promotes the next one")
    func clearActivePromotesNext() async throws {
        let fixture = try makeFixture()

        let next = try await fixture.client.clearActiveSession()

        #expect(next == fixture.first)
        let stored = try storedSessions(fixture.keychain)
        #expect(stored.sessions == [fixture.first])
        #expect(stored.activeID == fixture.first.accountID)
    }

    @Test("clearing the last remaining session leaves no account and no stored credentials")
    func clearLastSession() async throws {
        let fixture = try makeFixture()
        _ = try await fixture.client.clearActiveSession()

        #expect(try await fixture.client.clearActiveSession() == nil)
        #expect(await fixture.client.activeAccountID() == nil)
        #expect(try storedSessions(fixture.keychain) == StoredSessions())
    }

    @Test("removing an account that is not active logs it out with its own cookie, not the active one's")
    func removeInactiveAccountLogsOutWithItsOwnCookie() async throws {
        let fixture = try makeFixture()
        let seen = Recorded<URLRequest>()
        let client = makeClient(cookieStorage: fixture.cookieStorage, keychainClient: fixture.keychain) { request in
            seen.add(request)
            return try await okHandler()(request)
        }

        let next = try await client.removeAccount(fixture.first.accountID)

        #expect(next == fixture.second)
        let logout = try #require(seen.values.first)
        #expect(logout.url?.host() == serverURL.host())
        #expect(logout.value(forHTTPHeaderField: Constants.cookieHeader) == Constants.firstAccountCookie)
        #expect(logout.httpShouldHandleCookies == false)
    }

    @Test("switching, removing or clearing with an unreadable keychain throws and changes nothing")
    func unreadableKeychainThrows() async {
        let unreadable = KeychainClient(
            save: { _, _ in Issue.record("nothing may be saved over an unread set") },
            load: { _ in throw KeychainError.unexpectedStatus(errSecInteractionNotAllowed) },
            delete: { _ in Issue.record("nothing may be deleted when the set can't be read") }
        )
        let client = makeClient(cookieStorage: makeCookieStorage(), keychainClient: unreadable) { _ in
            Issue.record("no logout is sent for an account that can't be read")
            throw NetworkError.transport(TestFailure.offline)
        }

        await #expect(throws: AuthClientError.self) {
            _ = try await client.switchAccount(Constants.unknownAccountID)
        }
        await #expect(throws: AuthClientError.self) {
            _ = try await client.removeAccount(Constants.unknownAccountID)
        }
        await #expect(throws: AuthClientError.self) {
            _ = try await client.clearActiveSession()
        }
    }

    @Test("clearing with nothing stored returns nil and stores nothing")
    func clearWithNothingStored() async throws {
        let keychain = KeychainClient.inMemory()
        let client = makeClient(cookieStorage: makeCookieStorage(), keychainClient: keychain, handler: okHandler())

        #expect(try await client.clearActiveSession() == nil)
        #expect(try keychain.load(TestStorageKey.storedSessions) == nil)
    }
}

private enum Constants {
    static let unknownAccountID = "http://unknown.invalid|nobody"
    static let cookieHeader = "Cookie"
    static let firstAccountCookie = "connect.sid=abc"
}
