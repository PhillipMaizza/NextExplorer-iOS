import CoreModels
import Foundation
import Keychain
import OSLog

/// Bridges NextExplorer's session cookies between three places: the Keychain (durable, read at
/// cold launch), `HTTPCookieStorage` (what `URLSessionConfiguration.default` actually attaches to
/// outgoing requests), and the `StoredSessions` value the rest of AuthClient works with.
///
/// Multi-server: every signed-in account's credentials are kept in the Keychain at once, with one
/// marked active. Only the active account's cookie is installed into `HTTPCookieStorage`: accounts
/// on the same server share a cookie name/domain/path and cannot coexist there, so switching
/// reinstalls the target's cookie. Switching never re-authenticates.
struct SessionCookieStore: Sendable {
    let keychainClient: KeychainClient
    let cookieStorage: HTTPCookieStorage

    private enum Constants {
        static let logSubsystem = "app.nextplorer.authclient"
        static let logCategory = "SessionCookieStore"
    }

    private static let logger = Logger(subsystem: Constants.logSubsystem, category: Constants.logCategory)
    private static let storageKey = "storedSessions"
    /// The single-session key used before multi-server. Migrated into `storageKey` on first read.
    private static let legacyStorageKey = "currentSession"

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

    // MARK: Stored set

    /// Loads the persisted account set, migrating a legacy single-session blob on the way if that
    /// is all that exists. A keychain that can't be read looks like no accounts here; use
    /// `loadStoredOrThrow` where the difference matters.
    func loadStored() -> StoredSessions {
        (try? loadStoredOrThrow()) ?? StoredSessions()
    }

    /// Like `loadStored`, but an unreadable keychain or an unreadable stored blob throws, while an
    /// empty keychain still returns no accounts.
    func loadStoredOrThrow() throws -> StoredSessions {
        var unreadable: (any Error)?
        if let data = try keychainClient.load(Self.storageKey) {
            do {
                return try JSONDecoder().decode(StoredSessions.self, from: data)
            } catch {
                unreadable = error
            }
        }
        // Migration: fold a legacy single session into the new shape. An unreadable
        // stored blob is only replaced by a valid legacy session, and that is logged; the old key
        // goes only once the new set is safely saved.
        if let legacyData = try keychainClient.load(Self.legacyStorageKey),
           let legacy = try? JSONDecoder().decode(SessionCredentials.self, from: legacyData)
        {
            var migrated = StoredSessions()
            migrated.upsert(legacy)
            if unreadable != nil {
                Self.logger.notice("Replaced an unreadable stored session set with the legacy session")
            }
            if (try? saveStored(migrated)) != nil {
                try? keychainClient.delete(Self.legacyStorageKey)
            }
            return migrated
        }
        if let unreadable {
            throw unreadable
        }
        return StoredSessions()
    }

    private func saveStored(_ stored: StoredSessions) throws {
        let data = try JSONEncoder().encode(stored)
        try keychainClient.save(Self.storageKey, data)
    }

    // MARK: Mutations

    /// Adds or replaces one account, marks it active, persists, and installs its cookie.
    func persist(_ credentials: SessionCredentials) throws {
        var stored = loadStored()
        stored.upsert(credentials)
        do {
            try saveStored(stored)
        } catch {
            throw error
        }
        install(credentials)
    }

    func allSessions() -> [SessionCredentials] {
        loadStored().sessions
    }

    func activeCredentials() -> SessionCredentials? {
        loadStored().active
    }

    /// Makes `id` the active account and installs its cookie. Returns the now-active credentials,
    /// or `nil` if the id is unknown.
    @discardableResult
    func setActive(id: String) -> SessionCredentials? {
        var stored = loadStored()
        guard let target = stored.session(id: id) else { return nil }
        stored.activeID = id
        try? saveStored(stored)
        install(target)
        return target
    }

    /// Removes one account, dropping its cookie, and returns whatever account is active afterwards
    /// (the caller uses `nil` to fall back to the login screen).
    @discardableResult
    func remove(id: String) -> SessionCredentials? {
        var stored = loadStored()
        let removed = stored.session(id: id)
        stored.remove(id: id)
        try? saveStored(stored)
        if let removed {
            deleteCookies(serverURL: removed.serverBaseURL)
        }
        if let active = stored.active {
            install(active)
            return active
        }
        return nil
    }

    /// Session-expiry / 401 teardown of the active account only: drops it and switches to the next
    /// remaining account if there is one. Returns the new active account, or `nil` when none left.
    @discardableResult
    func clearActive() -> SessionCredentials? {
        let stored = loadStored()
        guard let active = stored.active else {
            clearAll()
            return nil
        }
        return remove(id: active.accountID)
    }

    /// Full teardown: every account signed out (or a hard reset). Clears the Keychain set and all
    /// of its cookies from `HTTPCookieStorage`.
    func clearAll() {
        let stored = loadStored()
        try? keychainClient.delete(Self.storageKey)
        try? keychainClient.delete(Self.legacyStorageKey)
        for session in stored.sessions {
            deleteCookies(serverURL: session.serverBaseURL)
        }
    }

    // MARK: Cookie install

    func install(_ credentials: SessionCredentials) {
        guard let cookie = credentials.httpCookie else { return }
        // `HTTPCookieStorage.cookieAcceptPolicy` is a separate gate from
        // `URLSessionConfiguration.httpCookieAcceptPolicy` and silently no-ops `setCookie`
        // if left at a restrictive default (observed in headless/CLI test processes).
        cookieStorage.cookieAcceptPolicy = .always
        cookieStorage.setCookie(cookie)
    }

    private func deleteCookies(serverURL: URL) {
        guard let cookies = cookieStorage.cookies(for: serverURL) else { return }
        for cookie in cookies {
            cookieStorage.deleteCookie(cookie)
        }
    }
}
