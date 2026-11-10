import Foundation

/// One way the signed in account can sign in, as `GET /api/auth/methods` lists it
/// (`backend/src/routes/auth.js`). Only the password method decides anything in the app: an
/// account created through single sign on has none until it adds one.
public struct SignInMethod: Codable, Equatable, Sendable, Identifiable {
    public static let localPasswordType = "local_password"

    public let id: String
    public let type: String
    public let provider: String
    public let lastUsedAt: String?
    public let createdAt: String?

    public init(id: String, type: String, provider: String, lastUsedAt: String? = nil, createdAt: String? = nil) {
        self.id = id
        self.type = type
        self.provider = provider
        self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt
    }
}

public extension [SignInMethod] {
    var hasPassword: Bool {
        contains { $0.type == SignInMethod.localPasswordType }
    }
}
