import Foundation

/// A credential for a script, issued from the signed in account (`GET /api/auth/tokens`,
/// `publicShape` in `backend/src/services/apiTokens.js`). The secret is never part of it: the
/// server hands that out once, when the token is made, as `IssuedAPIToken`.
public struct APIToken: Codable, Equatable, Sendable, Identifiable {
    /// A token reads, or it reads and writes. The server accepts nothing else.
    public enum Scope: String, Codable, CaseIterable, Sendable {
        case read
        case write
    }

    public let id: String
    public let name: String
    public let scope: Scope
    public let createdAt: String
    /// `nil` for a token that never expires.
    public let expiresAt: String?
    public let lastUsedAt: String?
    public let lastUsedIp: String?

    public init(
        id: String,
        name: String,
        scope: Scope,
        createdAt: String,
        expiresAt: String? = nil,
        lastUsedAt: String? = nil,
        lastUsedIp: String? = nil
    ) {
        self.id = id
        self.name = name
        self.scope = scope
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.lastUsedAt = lastUsedAt
        self.lastUsedIp = lastUsedIp
    }
}

/// The only reply that carries a token's value. It is not stored in readable form and no route
/// answers with it again, so losing it costs a new token.
public struct IssuedAPIToken: Codable, Equatable, Sendable, Identifiable {
    public var id: String {
        token.id
    }

    public let token: APIToken
    public let secret: String

    private enum CodingKeys: String, CodingKey {
        case token
        case secret
    }

    public init(token: APIToken, secret: String) {
        self.token = token
        self.secret = secret
    }
}

/// Limits the server enforces, so the form can say so before a round trip does.
public enum APITokenLimits {
    public static let maxNameLength = 60
    public static let maxExpiryDays = 3650
    public static let maxTokensPerAccount = 50
}
