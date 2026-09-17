import Foundation

/// The Keychain-persisted set of every signed-in account plus which one is active, so the app
/// can keep multiple servers logged in at once and switch between them without re-authenticating.
/// Replaces the single-session blob; a legacy single `SessionCredentials` is migrated into this
/// on first read (see `SessionCookieStore`).
public struct StoredSessions: Codable, Equatable, Sendable {
    public var sessions: [SessionCredentials]
    /// `accountID` of the active session, or `nil` when none remain (last account removed).
    public var activeID: String?

    public init(sessions: [SessionCredentials] = [], activeID: String? = nil) {
        self.sessions = sessions
        self.activeID = activeID
    }

    public var active: SessionCredentials? {
        guard let activeID else { return sessions.first }
        return sessions.first { $0.accountID == activeID } ?? sessions.first
    }

    public func session(id: String) -> SessionCredentials? {
        sessions.first { $0.accountID == id }
    }

    /// Adds a new account or replaces an existing one with the same identity, then makes it active.
    public mutating func upsert(_ credentials: SessionCredentials) {
        if let index = sessions.firstIndex(where: { $0.accountID == credentials.accountID }) {
            sessions[index] = credentials
        } else {
            sessions.append(credentials)
        }
        activeID = credentials.accountID
    }

    /// Removes an account. If it was active, the first remaining account becomes active (or `nil`
    /// when none are left).
    public mutating func remove(id: String) {
        sessions.removeAll { $0.accountID == id }
        if activeID == id {
            activeID = sessions.first?.accountID
        }
    }
}
