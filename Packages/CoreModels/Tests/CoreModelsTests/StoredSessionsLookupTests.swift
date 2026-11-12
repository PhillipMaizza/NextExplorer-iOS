@testable import CoreModels
import Foundation
import Testing
import TestUtils

@Suite("StoredSessions lookup and cookies")
struct StoredSessionsLookupTests {
    private func credentials(host: String, username: String?, expiresAt: Date? = nil, isSecure: Bool = true) -> SessionCredentials {
        SessionCredentials(
            serverBaseURL: URL(string: "https://\(host)") ?? URL(fileURLWithPath: "/"),
            authMode: .local,
            cookieName: TestSession.cookieName,
            cookieValue: TestSession.cookieValue,
            cookieDomain: host,
            cookiePath: "/",
            cookieIsSecure: isSecure,
            expiresAt: expiresAt,
            username: username
        )
    }

    @Test("session(id:) finds the account by its identity and nothing for an unknown one")
    func lookupByAccountID() {
        let first = credentials(host: TestHost.firstServer, username: TestAccount.username)
        let second = credentials(host: TestHost.secondServer, username: TestAccount.username)
        let stored = StoredSessions(sessions: [first, second], activeID: first.accountID)
        #expect(stored.session(id: second.accountID) == second)
        #expect(stored.session(id: first.accountID) == first)
        #expect(stored.session(id: "https://missing.example.com|nobody") == nil)
        #expect(StoredSessions().session(id: first.accountID) == nil)
    }

    @Test("an active id that no longer exists falls back to the first account")
    func staleActiveIDFallsBack() {
        let first = credentials(host: TestHost.firstServer, username: TestAccount.username)
        let second = credentials(host: TestHost.secondServer, username: TestAccount.username)
        let stored = StoredSessions(sessions: [first, second], activeID: "gone")
        #expect(stored.active == first)
    }

    @Test("a missing username is part of the account id as an empty suffix")
    func accountIDWithoutUsername() {
        #expect(credentials(host: TestHost.server, username: nil).accountID == "https://files.example.com|")
    }

    @Test("a persisted expiry is carried onto the reconstructed cookie")
    func cookieCarriesExpiry() throws {
        let cookie = try #require(credentials(host: TestHost.server, username: nil, expiresAt: MockDate.date).httpCookie)
        #expect(cookie.expiresDate == MockDate.date)
        #expect(!cookie.isSessionOnly)
    }

    @Test("a session scoped cookie has no expiry after reconstruction")
    func cookieWithoutExpiryIsSessionOnly() throws {
        let cookie = try #require(credentials(host: TestHost.server, username: nil).httpCookie)
        #expect(cookie.expiresDate == nil)
        #expect(cookie.isSessionOnly)
    }
}
