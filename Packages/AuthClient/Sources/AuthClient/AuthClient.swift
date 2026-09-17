import CoreModels
import DependenciesMacros
import Foundation

@DependencyClient
public struct AuthClient: Sendable {
    public var fetchStatus: @Sendable (_ serverURL: URL) async throws -> AuthStatus
    public var login: @Sendable (_ serverURL: URL, _ identifier: String, _ password: String) async throws -> User
    /// Runs the passkey capable OIDC bridge (ASWebAuthenticationSession + PKCE code exchange)
    /// and, on success, persists the resulting session the same way `login` does. Throws
    /// `AuthClientError.oidcCancelled` when the user dismisses the web sheet.
    public var loginOIDC: @Sendable (_ serverURL: URL) async throws -> User
    public var me: @Sendable (_ serverURL: URL) async throws -> User
    public var logout: @Sendable (_ serverURL: URL) async throws -> Void
    /// Restores the active account's session (installs its cookie), or `nil` if no account is
    /// stored.
    public var restoreSession: @Sendable () async -> SessionCredentials?
    /// Every signed-in account, active first is not guaranteed; callers match `activeAccountID`.
    public var listSessions: @Sendable () async -> [SessionCredentials] = { [] }
    /// The `accountID` of the active account, or `nil` when none.
    public var activeAccountID: @Sendable () async -> String?
    /// Switches the active account and installs its cookie (no re-authentication). Returns the
    /// now-active credentials, or `nil` if the id is unknown.
    public var switchAccount: @Sendable (_ accountID: String) async -> SessionCredentials?
    /// Signs one account out: best-effort server logout, drops its stored credentials and cookie,
    /// and returns whatever account is active afterwards (`nil` when none remain).
    public var removeAccount: @Sendable (_ accountID: String) async -> SessionCredentials?
    /// Tears down just the active account (session expiry / 401) and returns the next remaining
    /// account, or `nil` when none are left.
    public var clearActiveSession: @Sendable () async -> SessionCredentials?
    /// Full teardown: every account signed out (hard reset of the stored set and its cookies).
    public var clearAllSessions: @Sendable () async -> Void
}
