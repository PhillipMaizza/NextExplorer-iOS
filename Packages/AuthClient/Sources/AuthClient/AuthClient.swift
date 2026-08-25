import CoreModels
import DependenciesMacros
import Foundation

@DependencyClient
public struct AuthClient: Sendable {
    public var fetchStatus: @Sendable (_ serverURL: URL) async throws -> AuthStatus
    public var login: @Sendable (_ serverURL: URL, _ identifier: String, _ password: String) async throws -> User
    public var me: @Sendable (_ serverURL: URL) async throws -> User
    public var logout: @Sendable (_ serverURL: URL) async throws -> Void
    public var restoreSession: @Sendable () async -> SessionCredentials?
    public var clearSession: @Sendable () async -> Void
}
