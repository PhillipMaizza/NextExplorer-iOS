import Foundation

/// One way a user can authenticate, as returned inside the admin `GET /api/users` list
/// (`authMethods: [{ method, provider }]`) — confirmed against
/// `backend/src/services/users/management.js`'s `listUsers`.
public struct AuthMethod: Codable, Equatable, Sendable, Hashable {
    public let method: String
    public let provider: String?

    public init(method: String, provider: String? = nil) {
        self.method = method
        self.provider = provider
    }

    public var isPassword: Bool { method == "local_password" }
    public var isOIDC: Bool { method == "oidc" }
}
