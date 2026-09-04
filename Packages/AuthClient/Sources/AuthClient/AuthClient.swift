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
    public var restoreSession: @Sendable () async -> SessionCredentials?
    public var clearSession: @Sendable () async -> Void
}
