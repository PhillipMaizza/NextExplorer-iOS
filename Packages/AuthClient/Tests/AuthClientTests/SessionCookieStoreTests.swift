@testable import AuthClient
import CoreModels
import Foundation
import Keychain
import Testing

@Suite("SessionCookieStore")
struct SessionCookieStoreTests {
    private func uniqueServerURL() -> URL {
        URL(string: "http://test-\(UUID().uuidString.lowercased()).invalid:3000") ?? URL(fileURLWithPath: "/")
    }

    private func makeStore(keychainClient: KeychainClient = .inMemory()) -> SessionCookieStore {
        SessionCookieStore(keychainClient: keychainClient, cookieStorage: .shared)
    }

    // MARK: - capture

    @Test("capture edge case: no cookies at all for the host returns nil")
    func captureNoCookiesReturnsNil() {
        let store = makeStore()
        let serverURL = uniqueServerURL()
        let credentials = store.capture(
            serverURL: serverURL,
            authMode: .local,
            cookieName: AuthClientConfiguration.CookieName.local,
            username: "phillip"
        )
        #expect(credentials == nil)
    }

    @Test("capture edge case: cookies present but none match the expected name returns nil")
    func captureNoMatchingCookieNameReturnsNil() throws {
        let store = makeStore()
        let serverURL = uniqueServerURL()
        let host = try #require(serverURL.host)
        let cookie = try #require(HTTPCookie(properties: [
            .name: "some-other-cookie",
            .value: "abc",
            .domain: host,
            .path: "/",
        ]))
        HTTPCookieStorage.shared.setCookie(cookie)

        let credentials = store.capture(
            serverURL: serverURL,
            authMode: .local,
            cookieName: AuthClientConfiguration.CookieName.local,
            username: "phillip"
        )
        #expect(credentials == nil)
    }

    @Test("capture happy path: builds credentials from the matching cookie, preserving its attributes")
    func captureBuildsMatchingCredentials() throws {
        let store = makeStore()
        let serverURL = uniqueServerURL()
        let host = try #require(serverURL.host)
        let expiresAt = Date(timeIntervalSinceNow: 3600)
        let cookie = try #require(HTTPCookie(properties: [
            .name: AuthClientConfiguration.CookieName.local,
            .value: "s%3Aabc123",
            .domain: host,
            .path: "/",
            .expires: expiresAt,
        ]))
        HTTPCookieStorage.shared.setCookie(cookie)

        let credentials = try #require(store.capture(
            serverURL: serverURL,
            authMode: .local,
            cookieName: AuthClientConfiguration.CookieName.local,
            username: "phillip"
        ))
        #expect(credentials.cookieValue == "s%3Aabc123")
        #expect(credentials.cookieDomain == host)
        #expect(credentials.cookiePath == "/")
        #expect(credentials.cookieIsSecure == false)
        #expect(credentials.username == "phillip")
        #expect(credentials.authMode == .local)
        #expect(credentials.expiresAt != nil)
    }

    private func credentials(serverURL: URL, value: String, username: String) throws -> SessionCredentials {
        let host = try #require(serverURL.host)
        return SessionCredentials(
            serverBaseURL: serverURL,
            authMode: .local,
            cookieName: AuthClientConfiguration.CookieName.local,
            cookieValue: value,
            cookieDomain: host,
            cookiePath: "/",
            cookieIsSecure: false,
            expiresAt: nil,
            username: username
        )
    }

    // MARK: - persist / activeCredentials

    @Test("persist happy path: round-trips through the keychain and installs the cookie")
    func persistRoundTripsAndInstalls() throws {
        let keychainClient = KeychainClient.inMemory()
        let store = makeStore(keychainClient: keychainClient)
        let serverURL = uniqueServerURL()
        let creds = try credentials(serverURL: serverURL, value: "persisted-value", username: "phillip")

        try store.persist(creds)

        let loaded = try #require(store.activeCredentials())
        #expect(loaded.cookieValue == "persisted-value")
        let installedCookies = try #require(HTTPCookieStorage.shared.cookies(for: serverURL))
        #expect(installedCookies.contains { $0.value == "persisted-value" })
    }

    @Test("activeCredentials edge case: nothing saved returns nil")
    func activeNothingSavedReturnsNil() {
        let store = makeStore()
        #expect(store.activeCredentials() == nil)
    }

    @Test("loadStored edge case: corrupted data returns an empty set rather than throwing")
    func loadStoredCorruptedDataReturnsEmpty() throws {
        let keychainClient = KeychainClient.inMemory()
        try keychainClient.save("storedSessions", Data("not valid json".utf8))
        let store = makeStore(keychainClient: keychainClient)
        #expect(store.activeCredentials() == nil)
    }

    // MARK: - migration

    @Test("migration: a legacy single-session blob is folded into the stored set and made active")
    func migratesLegacySingleSession() throws {
        let keychainClient = KeychainClient.inMemory()
        let serverURL = uniqueServerURL()
        let legacy = try credentials(serverURL: serverURL, value: "legacy", username: "phillip")
        try keychainClient.save("currentSession", JSONEncoder().encode(legacy))
        let store = makeStore(keychainClient: keychainClient)

        let active = try #require(store.activeCredentials())
        #expect(active.cookieValue == "legacy")
        #expect(store.allSessions().count == 1)
        // The legacy key is dropped so migration only happens once.
        #expect(try keychainClient.load("currentSession") == nil)
        #expect(try keychainClient.load("storedSessions") != nil)
    }

    // MARK: - multi-account switch / remove

    @Test("two accounts coexist; setActive switches the active one and installs its cookie")
    func switchesBetweenAccounts() throws {
        let store = makeStore(keychainClient: .inMemory())
        let serverA = uniqueServerURL()
        let serverB = uniqueServerURL()
        let credsA = try credentials(serverURL: serverA, value: "aaa", username: "phillip")
        let credsB = try credentials(serverURL: serverB, value: "bbb", username: "jane")

        try store.persist(credsA)
        try store.persist(credsB)
        #expect(store.allSessions().count == 2)
        #expect(store.activeCredentials()?.accountID == credsB.accountID)

        let switched = try #require(store.setActive(id: credsA.accountID))
        #expect(switched.accountID == credsA.accountID)
        #expect(store.activeCredentials()?.accountID == credsA.accountID)
        #expect(HTTPCookieStorage.shared.cookies(for: serverA)?.contains { $0.value == "aaa" } == true)
    }

    @Test("remove happy path: removing the active account returns the next remaining account and drops its cookie")
    func removeActiveReturnsNext() throws {
        let store = makeStore(keychainClient: .inMemory())
        let serverA = uniqueServerURL()
        let serverB = uniqueServerURL()
        let credsA = try credentials(serverURL: serverA, value: "aaa", username: "phillip")
        let credsB = try credentials(serverURL: serverB, value: "bbb", username: "jane")
        try store.persist(credsA)
        try store.persist(credsB) // B active

        let next = try #require(store.remove(id: credsB.accountID))
        #expect(next.accountID == credsA.accountID)
        #expect(store.allSessions().count == 1)
        #expect(HTTPCookieStorage.shared.cookies(for: serverB)?.contains { $0.value == "bbb" } != true)
    }

    @Test("remove edge case: removing the last account returns nil")
    func removeLastReturnsNil() throws {
        let store = makeStore(keychainClient: .inMemory())
        let serverA = uniqueServerURL()
        let credsA = try credentials(serverURL: serverA, value: "aaa", username: "phillip")
        try store.persist(credsA)

        #expect(store.remove(id: credsA.accountID) == nil)
        #expect(store.allSessions().isEmpty)
    }

    // MARK: - clearAll

    @Test("clearAll removes the stored set and every account's cookies")
    func clearAllRemovesEverything() throws {
        let keychainClient = KeychainClient.inMemory()
        let store = makeStore(keychainClient: keychainClient)
        let serverA = uniqueServerURL()
        try store.persist(credentials(serverURL: serverA, value: "aaa", username: "phillip"))

        store.clearAll()

        #expect(try keychainClient.load("storedSessions") == nil)
        #expect(HTTPCookieStorage.shared.cookies(for: serverA)?.isEmpty ?? true)
        #expect(store.activeCredentials() == nil)
    }
}
