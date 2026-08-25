import CoreModels
import Foundation
import Keychain

/// Bridges NextExplorer's session cookie between three places: the Keychain (durable,
/// read at cold launch), `HTTPCookieStorage` (what `URLSessionConfiguration.default`
/// actually attaches to outgoing requests), and the `SessionCredentials` value the rest
/// of AuthClient works with.
struct SessionCookieStore: Sendable {
    let keychainClient: KeychainClient
    let cookieStorage: HTTPCookieStorage

    private static let storageKey = "currentSession"

    func capture(
        serverURL: URL,
        authMode: AuthMode,
        cookieName: String,
        username: String?
    ) -> SessionCredentials? {
        guard let host = serverURL.host else { return nil }
        let matching = cookieStorage.cookies(for: serverURL)?.first { $0.name == cookieName }
        guard let cookie = matching else { return nil }

        return SessionCredentials(
            serverBaseURL: serverURL,
            authMode: authMode,
            cookieName: cookie.name,
            cookieValue: cookie.value,
            cookieDomain: cookie.domain.isEmpty ? host : cookie.domain,
            cookiePath: cookie.path.isEmpty ? "/" : cookie.path,
            cookieIsSecure: cookie.isSecure,
            expiresAt: cookie.expiresDate,
            username: username
        )
    }

    func persist(_ credentials: SessionCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        try keychainClient.save(Self.storageKey, data)
        install(credentials)
    }

    func loadPersisted() -> SessionCredentials? {
        guard let data = try? keychainClient.load(Self.storageKey) else {
            return nil
        }
        return try? JSONDecoder().decode(SessionCredentials.self, from: data)
    }

    func install(_ credentials: SessionCredentials) {
        guard let cookie = credentials.httpCookie else { return }
        // `HTTPCookieStorage.cookieAcceptPolicy` is a separate gate from
        // `URLSessionConfiguration.httpCookieAcceptPolicy` and silently no-ops `setCookie`
        // if left at a restrictive default (observed in headless/CLI test processes).
        cookieStorage.cookieAcceptPolicy = .always
        cookieStorage.setCookie(cookie)
    }

    func clear(serverURL: URL?) {
        try? keychainClient.delete(Self.storageKey)
        guard let serverURL, let cookies = cookieStorage.cookies(for: serverURL) else { return }
        for cookie in cookies {
            cookieStorage.deleteCookie(cookie)
        }
    }
}
