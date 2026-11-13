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
            cookieIsSecure: false,
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

        let switched = await fixture.client.switchAccount(fixture.first.accountID)

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

        #expect(await fixture.client.switchAccount(Constants.unknownAccountID) == nil)
        #expect(await fixture.client.activeAccountID() == fixture.second.accountID)
        #expect(try storedSessions(fixture.keychain) == StoredSessions(
            sessions: [fixture.first, fixture.second],
            activeID: fixture.second.accountID
        ))
    }

    @Test("clearing the active session drops only that account and promotes the next one")
    func clearActivePromotesNext() async throws {
        let fixture = try makeFixture()

        let next = await fixture.client.clearActiveSession()

        #expect(next == fixture.first)
        let stored = try storedSessions(fixture.keychain)
        #expect(stored.sessions == [fixture.first])
        #expect(stored.activeID == fixture.first.accountID)
    }

    @Test("clearing the last remaining session leaves no account and no stored credentials")
    func clearLastSession() async throws {
        let fixture = try makeFixture()
        _ = await fixture.client.clearActiveSession()

        #expect(await fixture.client.clearActiveSession() == nil)
        #expect(await fixture.client.activeAccountID() == nil)
        #expect(try storedSessions(fixture.keychain) == StoredSessions())
    }

    @Test("clearing with nothing stored returns nil and stores nothing")
    func clearWithNothingStored() async throws {
        let keychain = KeychainClient.inMemory()
        let client = makeClient(cookieStorage: makeCookieStorage(), keychainClient: keychain, handler: okHandler())

        #expect(await client.clearActiveSession() == nil)
        #expect(try keychain.load(TestStorageKey.storedSessions) == nil)
    }
}

private enum Constants {
    static let unknownAccountID = "http://unknown.invalid|nobody"
}
