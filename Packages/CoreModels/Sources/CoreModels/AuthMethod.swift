import Foundation

/// How a user can authenticate, from the admin `GET /api/users` list
/// (`authMethods: [{ method, provider }]`). Verified against
/// `backend/src/services/users/management.js` `listUsers`.
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
