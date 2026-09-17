@testable import CoreModels
import Foundation
import Testing

@Suite("StoredSessions")
struct StoredSessionsTests {
    private func credentials(server: String, username: String) -> SessionCredentials {
        SessionCredentials(
            serverBaseURL: URL(string: server) ?? URL(fileURLWithPath: "/"),
            authMode: .local,
            cookieName: "connect.sid",
            cookieValue: "v",
            cookieDomain: URL(string: server)?.host ?? "",
            cookiePath: "/",
            cookieIsSecure: true,
            expiresAt: nil,
            username: username
        )
    }

    @Test("accountID distinguishes two users on the same server")
    func accountIDDistinguishesSameServerUsers() {
        let a = credentials(server: "https://s.example.com", username: "phillip")
        let b = credentials(server: "https://s.example.com", username: "jane")
        #expect(a.accountID != b.accountID)
    }

    @Test("upsert appends a new account and makes it active")
    func upsertAppendsAndActivates() {
        var stored = StoredSessions()
        let a = credentials(server: "https://a.example.com", username: "phillip")
        let b = credentials(server: "https://b.example.com", username: "jane")
        stored.upsert(a)
        stored.upsert(b)
        #expect(stored.sessions.count == 2)
        #expect(stored.activeID == b.accountID)
        #expect(stored.active?.accountID == b.accountID)
    }

    @Test("upsert replaces an existing account in place rather than duplicating it")
    func upsertReplacesInPlace() {
        var stored = StoredSessions()
        let a = credentials(server: "https://a.example.com", username: "phillip")
        stored.upsert(a)
        var updated = a
        updated.cookieValue = "new-value"
        stored.upsert(updated)
        #expect(stored.sessions.count == 1)
        #expect(stored.active?.cookieValue == "new-value")
    }

    @Test("removing the active account promotes the first remaining account")
    func removeActivePromotesNext() {
        var stored = StoredSessions()
        let a = credentials(server: "https://a.example.com", username: "phillip")
        let b = credentials(server: "https://b.example.com", username: "jane")
        stored.upsert(a)
        stored.upsert(b) // b active
        stored.remove(id: b.accountID)
        #expect(stored.sessions.count == 1)
        #expect(stored.activeID == a.accountID)
    }

    @Test("removing the last account leaves no active account")
    func removeLastClearsActive() {
        var stored = StoredSessions()
        let a = credentials(server: "https://a.example.com", username: "phillip")
        stored.upsert(a)
        stored.remove(id: a.accountID)
        #expect(stored.sessions.isEmpty)
        #expect(stored.activeID == nil)
        #expect(stored.active == nil)
    }

    @Test("removing a non-active account leaves the active one unchanged")
    func removeNonActiveKeepsActive() {
        var stored = StoredSessions()
        let a = credentials(server: "https://a.example.com", username: "phillip")
        let b = credentials(server: "https://b.example.com", username: "jane")
        stored.upsert(a)
        stored.upsert(b) // b active
        stored.remove(id: a.accountID)
        #expect(stored.activeID == b.accountID)
    }

    @Test("round-trips through Codable")
    func codableRoundTrip() throws {
        var stored = StoredSessions()
        stored.upsert(credentials(server: "https://a.example.com", username: "phillip"))
        stored.upsert(credentials(server: "https://b.example.com", username: "jane"))
        let data = try JSONEncoder().encode(stored)
        let decoded = try JSONDecoder().decode(StoredSessions.self, from: data)
        #expect(decoded == stored)
    }
}
