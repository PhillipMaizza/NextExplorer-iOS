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

    // MARK: - persist / loadPersisted

    @Test("persist happy path: round-trips through the keychain and installs the cookie")
    func persistRoundTripsAndInstalls() throws {
        let keychainClient = KeychainClient.inMemory()
        let store = makeStore(keychainClient: keychainClient)
        let serverURL = uniqueServerURL()
        let host = try #require(serverURL.host)
        let credentials = SessionCredentials(
            serverBaseURL: serverURL,
            authMode: .local,
            cookieName: AuthClientConfiguration.CookieName.local,
            cookieValue: "persisted-value",
            cookieDomain: host,
            cookiePath: "/",
            cookieIsSecure: false,
            expiresAt: nil,
            username: "phillip"
        )

        try store.persist(credentials)

        let loaded = try #require(store.loadPersisted())
        #expect(loaded.cookieValue == "persisted-value")
        let installedCookies = try #require(HTTPCookieStorage.shared.cookies(for: serverURL))
        #expect(installedCookies.contains { $0.value == "persisted-value" })
    }

    @Test("loadPersisted edge case: nothing saved returns nil")
    func loadPersistedNothingSavedReturnsNil() {
        let store = makeStore()
        #expect(store.loadPersisted() == nil)
    }

    @Test("loadPersisted edge case: corrupted data returns nil rather than throwing")
    func loadPersistedCorruptedDataReturnsNil() throws {
        let keychainClient = KeychainClient.inMemory()
        try keychainClient.save("currentSession", Data("not valid json".utf8))
        let store = makeStore(keychainClient: keychainClient)
        #expect(store.loadPersisted() == nil)
    }

    // MARK: - clear

    @Test("clear happy path: removes the keychain entry and matching cookies for the server")
    func clearRemovesKeychainAndCookies() throws {
        let keychainClient = KeychainClient.inMemory()
        try keychainClient.save("currentSession", Data("placeholder".utf8))
        let store = makeStore(keychainClient: keychainClient)
        let serverURL = uniqueServerURL()
        let host = try #require(serverURL.host)
        let cookie = try #require(HTTPCookie(properties: [
            .name: AuthClientConfiguration.CookieName.local,
            .value: "abc",
            .domain: host,
            .path: "/",
        ]))
        HTTPCookieStorage.shared.setCookie(cookie)

        store.clear(serverURL: serverURL)

        #expect(try keychainClient.load("currentSession") == nil)
        #expect(HTTPCookieStorage.shared.cookies(for: serverURL)?.isEmpty ?? true)
    }

    @Test("clear edge case: a nil serverURL still removes the keychain entry, leaving cookies untouched")
    func clearWithNilServerURLOnlyClearsKeychain() throws {
        let keychainClient = KeychainClient.inMemory()
        try keychainClient.save("currentSession", Data("placeholder".utf8))
        let store = makeStore(keychainClient: keychainClient)
        let serverURL = uniqueServerURL()
        let host = try #require(serverURL.host)
        let cookie = try #require(HTTPCookie(properties: [
            .name: AuthClientConfiguration.CookieName.local,
            .value: "abc",
            .domain: host,
            .path: "/",
        ]))
        HTTPCookieStorage.shared.setCookie(cookie)

        store.clear(serverURL: nil)

        #expect(try keychainClient.load("currentSession") == nil)
        #expect(HTTPCookieStorage.shared.cookies(for: serverURL)?.contains { $0.value == "abc" } == true)
    }
}
